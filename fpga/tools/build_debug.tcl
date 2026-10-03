file mkdir build_debug
read_verilog -sv {uart_rx.sv uart_tx.sv state_parser.sv input_quantizer.sv pong_nn.sv ring_fpga_top.sv}
read_xdc arty-a7-35t.xdc
synth_design -top ring_fpga_top -part xc7a35tcsg324-1
foreach pattern {uart_rxd_out* rx_valid* rx_data* frame_valid* nn_done* tx_busy* led*} {
 set matches [get_nets -hier -filter "NAME =~ $pattern"]
 puts "DEBUG NETS $pattern: $matches"
}
create_debug_core debug_ila ila
set_property C_DATA_DEPTH 8192 [get_debug_cores debug_ila]
set_property C_ADV_TRIGGER false [get_debug_cores debug_ila]
set_property C_EN_STRG_QUAL false [get_debug_cores debug_ila]
connect_debug_port debug_ila/clk [get_nets CLK100MHZ_IBUF_BUFG]
set debug_nets [get_nets {rx/sync_rx rx_valid frame_valid nn_done tx_busy}]
if {[llength $debug_nets] != 5} {error "Expected five debug signals: $debug_nets"}
set_property port_width 5 [get_debug_ports debug_ila/probe0]
connect_debug_port debug_ila/probe0 $debug_nets
implement_debug_core
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file build_debug/timing.txt
report_drc -file build_debug/drc.txt
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {error "Debug setup timing failed"}
if {[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]] < 0} {error "Debug hold timing failed"}
write_debug_probes -force build_debug/ring_debug.ltx
write_bitstream -force build_debug/ring_debug.bit
exit
