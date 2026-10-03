file mkdir build
set sources {uart_rx.sv uart_tx.sv state_parser.sv input_quantizer.sv pong_nn.sv ring_fpga_top.sv}
read_verilog -sv $sources
read_xdc arty-a7-35t.xdc
synth_design -top ring_fpga_top -part xc7a35tcsg324-1
report_utilization -file build/synth_utilization.txt
opt_design
place_design
phys_opt_design
route_design
report_utilization -file build/utilization.txt
report_timing_summary -report_unconstrained -file build/timing.txt
report_drc -file build/drc.txt
report_cdc -file build/cdc.txt
write_checkpoint -force build/ring_fpga_top_routed.dcp
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {error "100 MHz setup timing failed"}
if {[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]] < 0} {error "Hold timing failed"}
# No DRC severities are changed. write_bitstream enforces NSTD-1 and UCIO-1.
write_bitstream -force build/ring_fpga_top.bit
exit
