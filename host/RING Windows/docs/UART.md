# Proposed UART boundary — version 1

Each serial player uses its selected port: 115200 baud, 8 data bits, no parity, one stop bit, no flow control (DTR/RTS disabled). Defaults preserve STM32 on COM4 and FPGA simulated; FPGA can be explicitly switched to serial on a distinct selected port. The STATE/ACT fields and terminators match the existing DroneFC firmware unchanged. See DUAL-UART.md for configuration.

ASCII comma-separated lines ending in LF (receiver may accept CRLF). Uppercase tokens, no whitespace, decimal integers only. Maximum buffered line: 192 characters; discard oversized or malformed frames through the next LF.

Host request:

```text
STATE,1,42,L,424,271,-5,3,180,200,960,480,80
```

Fields in order: STATE, protocol version, physics tick, side (L/R), ball X, ball Y, velocity X, velocity Y, own paddle center Y, opponent paddle center Y, field width, field height, paddle height. Positions are logical pixels, velocities pixels/second. Origin top left; positive Y points down. Host values round to the nearest integer with midpoint ties away from zero, independently of locale.

Device response:

```text
ACT,1,42,UP
ACT,1,42,DOWN
ACT,1,42,STAY
```

Send one response per request, echoing its tick. The parser requires the exact expected nonnegative tick, version 1 and one valid action. Invalid/stale/future responses yield no accepted decision; the adapter uses STAY. Tick is a signed 64-bit nonnegative decimal integer, increasing by two between 60 Hz requests. Simple embedded implementations can preserve the tick as decimal text and echo it rather than perform 64-bit arithmetic.

## Phase 2 adapter scheduling

`IController.Decide` must never wait for a serial read. Use one worker per port. On each decision call, consume a completed response for the preceding request and queue the new snapshot. Define a response deadline of one decision period (16.67 ms), with bounded single outstanding work; discard late replies. Both sides must use the same policy. The adapter tracks the expected request tick for parsing; it must not compare the response with the newly queued snapshot's tick.

The game tick restarts on R; the adapter offsets the existing integer wire tick so it remains unique across resets. A process-time-derived starting offset separates normal application restarts. The firmware already validates and echoes this signed-64-bit-range tick text. Reset also invalidates outstanding results by generation; reconnect discards host input and clears accepted actions. Log entries show both wire tick and game tick. No new protocol fields or handshake are introduced. Responses must also be fresh by game tick and wall-clock age; actions are consumed only once.

Track valid decisions, latency, deadlines and malformed/stale replies in the serial adapter. Never put serial framing or port state into PongGame. Device logic owns only its choice of UP/DOWN/STAY; the host owns all movement and physics.
