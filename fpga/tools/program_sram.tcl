# Run manually only with the intended Arty connected. Never writes flash.
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets]
if {[llength $targets] != 1} {error "Connect exactly one intended hardware target"}
open_hw_target [lindex $targets 0]
set devices [get_hw_devices -filter {PART =~ xc7a35t*}]
if {[llength $devices] != 1} {error "Expected exactly one xc7a35t device"}
set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device $device
set bitfile build/ring_fpga_top.bit
if {$argc == 1} {set bitfile [lindex $argv 0]}
puts "Programming SRAM only: [file normalize $bitfile]"
set_property PROGRAM.FILE [file normalize $bitfile] $device
program_hw_devices $device
close_hw_manager
exit
