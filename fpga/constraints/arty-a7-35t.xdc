# Verified against local Arty-A7-35-Master.xdc and Digilent/digilent-xdc.
# USB J10: A9 is FPGA RX (PC TX); D10 is FPGA TX (PC RX).
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports uart_rx_in]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_tx_out]
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
create_clock -period 10.000 -name sys_clk [get_ports CLK100MHZ]
create_generated_clock -name nn_clk -source [get_ports CLK100MHZ] -divide_by 2 [get_pins nn_clock_reg/Q]
# Only asynchronous input to the first synchronizer stage is excluded.
set_false_path -from [get_ports uart_rx_in] -to [get_cells -hier -filter {NAME =~ *rx/meta_reg}]
# TX and diagnostic LEDs are asynchronous external observations, not clocked interfaces.
set_false_path -to [get_ports {uart_tx_out led[*]}]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
