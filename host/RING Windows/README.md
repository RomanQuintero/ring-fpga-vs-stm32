# Project 15 — RING / Pong: FPGA vs STM32, dual UART preparation

Windows now supports two independent generic SerialController instances, per-player simulated/serial modes, manual port selection, port enumeration with driver metadata and duplicate-port prevention. Defaults still preserve FPGA simulated and STM32 serial COM4. See [dual UART setup and FPGA expectations](docs/DUAL-UART.md) for commands and the final architecture. No FPGA UART/HDL or STM32 firmware changes were made.

Dual-controller regression on 2026-10-03: all existing and new automated tests passed. With FPGA deliberately assigned to nonexistent COM999 and physical STM32 on COM4, the real window ran 40 seconds (4,801 physics steps), scored 6–6, and exited with code 0. STM32 received 2,351 ACT, applied 2,327, latest latency 8.46 ms, zero timeouts/invalid replies/connection errors. FPGA reported its missing port independently and used STAY. Fifty queued STM32 snapshots were replaced during scheduling. The rendered image was inspected. Evidence: `bin/verification-dual-absent/match.txt`, `match.png`, and separate role logs.

A small C# / WinForms Windows Pong host. FPGA (Arty A7-35T) remains simulated; STM32 (NUCLEO-H7A3ZI-Q) uses SerialController on COM4, 115200 baud, 8N1, no flow control. The Windows host owns physics, rendering and scoring. Without valid ACT replies, the STM32 paddle stays still and the match continues.

## Build and run

From this directory in Windows PowerShell:

```powershell
.\build.ps1 -Test
.\build.ps1 -Run
```

Or double-click `bin/PongExperiment.exe` after building. The build uses the .NET Framework C# compiler included on this Windows machine; no SDK, NuGet packages or network access is needed. C# 5 syntax keeps it compatible with that compiler. Requires Windows and .NET Framework 4.x. `bin` is generated and ignored by Git.

Space pauses/resumes; R resets the match and telemetry; Escape closes. Both paddles always receive their actions through `IController`.

## Architecture

- `src/PongGame.cs`: deterministic game state, 120 Hz physics, walls, paddles, score, and a 0.75 second automatic serve delay. Ball speed is 540 logical pixels/second; paddle speed is 270. Contact position determines the bounce angle (up to 60 degrees). Serves follow a repeatable angle/direction sequence. Scores continue indefinitely.
- `src/Controllers.cs`: immutable snapshots, `IController`, and a simple simulated controller. It follows the ball vertically with a six pixel dead zone.
- `src/Program.cs`: WinForms window and rendering. A stopwatch accumulator drives fixed steps; long UI stalls are capped at 100 ms of catch-up, so the game slows during a stall rather than jumping forward.
- `src/UartProtocol.cs`: invariant integer serialization and strict response parsing. It performs no I/O.
- `src/SerialController.cs`: generic per-port worker, bounded latest-snapshot queue, correlated replies, deadline, reconnection, per-device diagnostics and process port ownership.
- `src/ControllerOptions.cs`: per-player mode/port argument parsing and duplicate-port validation.
- `src/SerialPortCatalog.cs`: enumeration plus optional Windows registry driver descriptions/hardware IDs; no automatic board identity claim.
- `tests/Checks.cs`: dependency-free checks for wall/paddle collisions, scoring, reset, equal snapshots, bounds, reproducibility, autonomous rallies/scoring, and protocol rejection.

Controllers are called at 60 Hz. Both snapshots are made before either paddle moves, with identical ball information. `Decide(snapshot)` returns `Up`, `Down` or `Stay` promptly. Coordinates are global: origin at the field's top left, X rightwards, Y downwards, paddle Y at its center. Velocities are pixels/second. Snapshots also contain the side, tick, opponent paddle center, field dimensions, and paddle height.

The window now constructs `PongGame(new SimulatedController(), stm32)` with `stm32` a SerialController. Physics and scoring are unchanged. Every serial decision queues STATE and consumes a valid ACT from the preceding request. The worker retains one active exchange and one latest queued snapshot. Invalid/stale/late/missing replies use STAY, never simulated fallback. An accepted response is consumed once, only on the next game decision, with at most 33.33 ms wall-clock age. Read response deadline: 16.67 ms; poll timeout: 2 ms; write timeout: 15 ms. Open failures retry once per second. DTR/RTS are disabled.

Wire ticks use the existing nonnegative integer field with a unique process-time-derived offset, advancing with game ticks. Reset rebases that offset and invalidates outstanding results, so old ACT replies cannot match a new match. Logs show both game and wire ticks. No protocol fields, version or terminators were changed.

Existing game telemetry is preserved. The STM32 panel adds COM4 status, ACT count, latest latency, timeouts and invalid replies. `bin/logs/stm32-uart.log` records connection failures and sampled ACT actions/timeouts, with wire/game ticks and statistics. Serial telemetry includes sent, received, applied, skipped snapshots and connection errors; these counters persist across R, which resets game counters only. Logging failures cannot close the game.

## Verification

`build.ps1 -Test` runs ten minutes of simulated fixed steps twice and checks equal results. A GUI verification mode runs the real WinForms timer for 40 seconds, renders the form to a PNG and writes telemetry before closing:

```powershell
.\bin\PongExperiment.exe --verify "$PWD\bin\verification"
```

This mode uses the same window, controllers, rendering and game loop as a normal launch. The generated PNG uses the same renderer at a fixed 1100 x 760 size, independently of whether the window is minimized; it is not a desktop screenshot.

Verified on 2026-10-03: warning-free build, all automated checks passed; two ten-minute simulations produced the same 24–8 score and 160/152 paddle hits. The real window ran 4,801 physics steps, reached 2–1 with 10 hits per side and 2,401 decisions per side, and exited with code 0. Its rendered image was inspected. An earlier verification capture failed when the window dimensions were invalid; fixed-size rendering corrected that failure.

## Physical STM32 setup and Phase 2 verification

Inspected `stm32`: README, `Core/Src/pong_protocol.c`, `freertos.c` and `main.c`. The existing 13-field STATE parser and ACT/LF replies match the host exactly. No firmware or historical `.ioc` was modified or regenerated.

Load the prepared `DroneFC/Build/PongSTM32.elf` through the existing CubeIDE/ST-LINK debug configuration or STM32CubeProgrammer and start/resume execution. Close serial terminals and other RING instances, then run:

```powershell
.\build.ps1 -Test -Run
```

Confirm `COM4 / CONNECTED`, increasing ACT count and movement of the orange paddle; FPGA remains SIMULATED. A halted debugger cannot answer UART. If ACT stays zero, inspect the log, loaded/running firmware, USART3 and ST-LINK bridges. The adapter stays responsive on port occupied/disconnect/missing replies and uses STAY.

For a 40-second actual game test with serial telemetry:

```powershell
.\bin\PongExperiment.exe --verify "$PWD\bin\verification-stm32"
Get-Content .\bin\verification-stm32\match.txt
Get-Content .\bin\logs\stm32-uart.log -Tail 20
```

Automated serial tests cover valid actions, reset correlation, oversized-line recovery, invalid/stale replies, timeouts, occupied port, disconnect, disposal and nonblocking decisions. Earlier COM4 probes timed out before firmware was flashed; the real window still completed 4,801 physics steps with exit code 0 and no applied serial actions. No FPGA implementation or later-phase work is included.

After the user loaded the prepared firmware, physical verification on 2026-10-03 succeeded: all three UART probes returned the matching UP/DOWN/STAY ACT. The real window completed 40 seconds (4,801 physics steps) with COM4 CONNECTED, 2,361 valid responses, 2,356 applied actions, latest round-trip latency 8.37 ms, zero timeouts/invalid responses/connection errors, and 12 paddle hits per side. Forty queued snapshots were replaced during scheduling; accepted replies without application were discarded by freshness/decision timing. Match score was 0–0 during this rally-heavy interval; scoring remains covered by unchanged physics tests. Exit code was 0 and the rendered image was inspected. Evidence: `bin/verification-stm32-live/match.txt`, `match.png`, and `bin/logs/stm32-uart.log`.

See [the proposed UART protocol](docs/UART.md).
