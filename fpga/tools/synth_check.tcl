read_verilog -sv pong_nn.sv
synth_design -top pong_nn -part xc7a35tcsg324-1
report_utilization -file utilization.txt
report_timing_summary -file timing.txt
exit
