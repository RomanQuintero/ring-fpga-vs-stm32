# Windows ready for FPGA serial vs STM32 serial

No HDL, neural network, STM32 firmware, physics, scoring or STATE/ACT parser changes are included. Each player can be simulated or use the same generic SerialController implementation.

## Select ports and modes

Enumerate ports with Windows driver descriptions and hardware IDs when accessible:

```powershell
.\bin\PongExperiment.exe --list-ports
```

This shows a dialog and also writes `bin/ports.txt`. After a test build, a console alternative is:

```powershell
.\bin\Checks.exe --list-ports
```

Enumeration uses `SerialPort.GetPortNames()`. Read-only registry information under USB and FTDIBUS supplements the list with FriendlyName/DeviceDesc/HardwareID, including VID/PID where the driver supplies them. If unavailable, the COM name still remains selectable. Registry descriptions may be generic or ambiguous; VID/PID describes an interface, not proof of board identity or a working FPGA UART. No automatic board assignment or probing of unrelated ports occurs. Refresh by running the command again; selection is explicit at startup.

Observed on this machine: COM4 is described as STMicroelectronics STLink Virtual COM Port (VID_0483/PID_374E); COM5 is USB Serial Port with FTDI VID_0403/PID_6010. COM5 is a candidate to investigate manually, not a confirmed functioning Arty UART.

Build with `.\build.ps1 -Test`. Default launch preserves FPGA simulated and STM32 serial COM4:

```powershell
.\bin\PongExperiment.exe
```

For two physical serial controllers, after checking the FPGA port assignment:

```powershell
.\bin\PongExperiment.exe --fpga-mode serial --fpga-port COM5 --stm32-mode serial --stm32-port COM4
```

Replace COM5 with the FPGA port identified on your system. Supplying `--fpga-port` alone does not enable serial mode; specify both options. Each `--*-mode` accepts `serial` or `simulated`. STM32 defaults to serial/COM4; FPGA defaults to simulated with no port selected. FPGA serial requires an explicit port. A syntactically valid absent port can be selected in preparation for later connection. Restart the app to change selection; reconnecting the same port is automatic.

Both serial roles must use distinct COM names. Validation rejects duplicate ports case-insensitively before opening either. SerialController also reserves a port per process, rejecting duplicate ownership even outside configuration. Between different applications Windows enforces exclusive port ownership; a busy port becomes ERROR/RETRYING, not a game crash.

## Architecture, status and failures

IController → SimulatedController or SerialController(port, deviceName). Both game sides use the same abstraction and global coordinates. The game's left snapshot contains L; right contains R. Each serial instance has its own SerialPort, thread, wake event, bounded queue, outstanding request/tick, last accepted action, latency, counters and reconnect loop. Both use the existing 115200/8N1/no-flow-control settings and 16.67 ms response deadline.

The UI shows each player's mode, selected COM, status and current action. Port open starts WAITING; CONNECTED requires a valid ACT. Timeout displays WAITING (NO ACT); unavailable/busy/disconnected displays ERROR / RETRYING. Missing/invalid/stale replies return STAY, never implicit simulated fallback. To simulate an absent player, explicitly select simulated mode.

The game does not wait for I/O. One failing controller has no shared worker, lock, action or telemetry with the other. Ports reconnect with the existing worker policy. Configuration validation and process ownership are the only shared mechanisms.

Separate panels display TX (STATE sent), RX (valid ACT received), APPLY, TO (timeouts), BAD (invalid replies), ERR (connection errors) and latency. Existing hits/misses/game decisions remain visible. Logs are separate: `bin/logs/fpga-uart.log` and `bin/logs/stm32-uart.log`. Every event identifies its role and selected port. A game reset invalidates old results without resetting serial counters.

## What the FPGA must eventually implement

Existing v1 only: ASCII, comma-separated, LF terminated; host sends 13 fields:

```text
STATE,1,42,L,424,271,-5,3,180,200,960,480,80
```

Fields: STATE, version, echoed nonnegative signed-64-bit-range tick, side, ball X/Y, velocity X/Y, own/opponent paddle center Y, field width/height, paddle height. Coordinates are global, origin top left, positive Y down, velocity pixels/second. Host numbers are rounded integers. Actual wire ticks have the existing unique offset and can be large; echo the tick text rather than assuming a small counter.

Return exactly one corresponding line within the deadline:

```text
ACT,1,42,UP
```

UP, DOWN or STAY only. Matching version/tick required; CRLF responses are also accepted. Maximum line is 192 characters. Each port identifies its device, so no new device-ID field is required. See UART.md for the existing freshness/reset policy. Implementing this in FPGA is outside this Windows phase.

## Tests and physical regression

All existing game, protocol and serial tests are retained. Added tests cover independent ports and opposite L/R actions, configuration and direct-controller duplicate rejection, separate metrics, FPGA absent with STM32 responding, FPGA timeout while STM32 keeps responding, and FPGA disconnect/reconnect. These use injected transport fakes and do not claim an FPGA exists physically.

The physical regression deliberately selects nonexistent COM999 for FPGA and real COM4 for STM32:

```powershell
.\bin\PongExperiment.exe --fpga-mode serial --fpga-port COM999 --stm32-port COM4 --verify "$PWD\bin\verification-dual-absent"
```

This is an absence test, not a real FPGA assignment. Evidence is saved as `match.txt` and a render `match.png` in that directory. Final measured results are recorded in README.md.
