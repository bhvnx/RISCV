################################################################################
# run_impl.tcl  —  Synthesise, implement, and generate a bitstream.
#
# Usage (from RISCV project root or vivado/ directory):
#
#   vivado -mode tcl -source vivado/run_impl.tcl
#
# Or open the project in the Vivado GUI first, then source this script from the
# Tcl console.  The script opens the project if it is not already open.
#
# After generating the bitstream, program the Basys3 with:
#   Open Hardware Manager → Open Target → Auto Connect → Program Device
# Then select the .bit file from vivado/riscv_core_proj/riscv_core.runs/impl_1/
################################################################################

set script_dir [file dirname [file normalize [info script]]]
set proj_file  "$script_dir/riscv_core_proj/riscv_core.xpr"

# Open project if none is currently open
if {[catch {current_project}]} {
  if {![file exists $proj_file]} {
    error "Project not found: $proj_file\nRun create_project.tcl first."
  }
  open_project $proj_file
}

puts "=== Running synthesis ==="
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  error "Synthesis failed — check the Messages panel."
}
puts "    Synthesis complete."

# Optional: insert ILA for mark_debug signals automatically
# Comment out if you do not want an ILA core (saves LUTs).
puts "=== Inserting debug cores (ILA for mark_debug signals) ==="
open_run synth_1 -name synth_1
implement_debug_core

puts "=== Running implementation ==="
launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  error "Implementation failed — check the Messages panel."
}
puts "    Implementation complete."

puts "=== Generating bitstream ==="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bit_file [glob -nocomplain \
  "$script_dir/riscv_core_proj/riscv_core.runs/impl_1/*.bit"]
if {$bit_file eq ""} {
  error "Bitstream not found — check the Messages panel."
}
puts ""
puts "=== Bitstream ready: $bit_file ==="
puts ""
puts "To program the Zybo Z7-20:"
puts "  1. Open Hardware Manager in the Vivado GUI."
puts "  2. Connect the Zybo via micro-USB (PROG/UART port), power it on."
puts "  3. Open Target → Auto Connect."
puts "  4. Program Device and select the .bit file above."
puts "  5. Connect a USB-UART cable: JA pin1(N15)→RX, JA pin5→GND."
puts "  6. Open a terminal at 115200 8N1 on the USB-UART COM port."
puts "  7. Press BTN0 (K18) to reset, then release."
puts "  8. The terminal will print register values when ECALL is reached."
puts "  9. LD0 lights when halted; LD2 should be on (x3[3]=1 means x3=8)."
