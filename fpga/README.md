# FPGA — Arty A7-35T

Existing verified RTL, copied without logic changes.

- `rtl/`: 5→16→3 INT8 NN, weights/requantization, UART RX/TX, STATE parser, input quantizer, RING top and loopback top.
- `constraints/arty-a7-35t.xdc`: unchanged contents of the original `ring_arty.xdc`, renamed. Loopback constraints are also retained.
- `sim/`: testbenches, Python reference generators and recorded vectors.
- `tools/`: existing Vivado Tcl scripts and physical UART test scripts. Only the renamed XDC reference was updated.
- `run.ps1`: prepares a flat temporary workspace so existing scripts keep their relative-path assumptions.

From the repository root, with NumPy and Vivado 2026.1 installed:

```powershell
.\fpga\run.ps1 -Task Simulate -Python python -VivadoBin 'C:\AMDDesignTools\2026.1\Vivado\bin'
.\fpga\run.ps1 -Task Build -VivadoBin 'C:\AMDDesignTools\2026.1\Vivado\bin'
```

Use your actual tool locations. Omit `-VivadoBin` if tools are on PATH. `-Task Synthesize` checks only the NN; `-Task Prepare` stages sources without running tools. Simulation requires explicit PASS output for both regressions, not just a zero exit code.

The complete build writes `fpga/build/work/build/ring_fpga_top.bit`. No task programs hardware or changes drivers. To program SRAM, review and explicitly run `program_sram.tcl` from the workspace with the intended board connected. Physical UART tests also require selecting the board's COM port.

Historical evidence is in `../docs/results/fpga/` and `../docs/results/dual-physical-match.txt`: 30,243 NN vectors, 38 UART cases, WNS +0.186 ns and zero DRC violations. Place-and-route was not repeated while packaging; a new implementation must check its own timing.

The historical FTDI 1 ms setting was specific to the test machine and board. Unit-specific driver scripts are excluded. Packaging does not change drivers; higher USB latency may exceed the host deadline.
