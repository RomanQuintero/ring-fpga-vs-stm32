# STM32 Pong controller with FreeRTOS

Firmware for NUCLEO-H7A3ZI-Q (STM32H7A3ZITxQ). Windows owns the game; this device decides only its paddle action. The CubeIDE project retains the historical name `DroneFC` for import compatibility.

## Build

From this directory in PowerShell:

```powershell
.\build.ps1
```

The script finds GNU Tools for STM32 on PATH or under `C:/ST`. Use `-Toolchain 'path/to/tools/bin'` to select it explicitly. It rebuilds active sources and produces `Build/PongSTM32.elf` and its map without programming the board. GNU Tools for STM32 14.3.rel1 was used in the original build.

Alternatively import `.project` into STM32CubeIDE and rebuild Debug or Release. Both configurations use the Cortex-M7 r0p1 port. Create a local debug launch configuration; a machine-specific launch file is intentionally excluded.

## UART and tasks

- USART3: PD8 TX, PD9 RX, 115200 baud, 8N1, no flow control; use the ST-LINK Virtual COM Port and check the board's bridges.
- `pongTask`: receives UART interrupt bytes through a CMSIS-RTOS2 queue and answers valid STATE frames. It alone transmits on USART3.
- `blinkTask`: toggles PB0 once per second without writing UART.
- HSI at 64 MHz; TIM6 supplies HAL tick, SysTick supplies the kernel tick. I2C and USART2 are not initialized.

The simple controller returns UP when ball Y minus own paddle center is below −6, DOWN above +6, and STAY otherwise. It uses the same rule as the host's simulated controller, applied to integer wire coordinates.

## Existing protocol v1

ASCII lines terminated by LF; CRLF requests are accepted:

```text
STATE,1,42,R,424,271,-5,3,180,200,960,480,80
ACT,1,42,DOWN
```

STATE fields: token, version, nonnegative tick, L/R, ball X/Y, velocity X/Y, own/opponent paddle center Y, field width, field height, paddle height. The parser validates tick up to 9223372036854775807 and echoes its value. The nine state values must fit int32. Dimensions must be positive and paddle height must fit the field. No spaces, empty/extra fields or unsupported versions.

Input is bounded to 192 characters before LF. Invalid/oversized/NUL-containing lines are discarded; UART errors/lost bytes resynchronize at LF. No startup/error text is emitted on the game channel. Transmission timeout is 5 ms with no retry, avoiding duplicated/late replies.

`Core/Src/pong_protocol.c` is HAL/RTOS-independent. `Core/Src/freertos.c` contains tasks and UART callbacks. `tests/pong_protocol_test.c` supplies the 18 original native parser checks. The host connection is documented in [UART.md](../host/RING%20Windows/docs/UART.md).

## Historical configuration

`DroneFC.ioc` contains the old CubeMX configuration and does not match the maintained Pong firmware. **Do not regenerate sources from it.** Build uses the C sources and project metadata, not the `.ioc`. Original drone/sensor legacy material is excluded from this focused Pong repository. ST, CMSIS and FreeRTOS licenses remain in their respective folders.
