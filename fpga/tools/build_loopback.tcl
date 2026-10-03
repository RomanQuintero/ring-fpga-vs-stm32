file mkdir build_debug
read_verilog -sv uart_loopback_top.sv
read_xdc uart_loopback.xdc
synth_design -top uart_loopback_top -part xc7a35tcsg324-1
opt_design
place_design
route_design
report_timing_summary -file build_debug/loopback_timing.txt
report_drc -file build_debug/loopback_drc.txt
write_bitstream -force build_debug/uart_loopback.bit
exit
