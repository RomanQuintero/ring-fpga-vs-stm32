# Read-only JTAG enumeration; no program_hw_devices / configuration flash commands.
open_hw_manager
connect_hw_server
set out [open hardware_detected.txt w]
set targets [get_hw_targets]
puts $out "Targets: $targets"
if {[llength $targets] == 1} {
 open_hw_target [lindex $targets 0]
 foreach device [get_hw_devices] {
  puts $out "Device: $device PART=[get_property PART $device]"
 }
 close_hw_target
}
close $out
close_hw_manager
exit
