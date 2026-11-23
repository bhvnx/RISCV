################################################################################
# create_project.tcl  —  Vivado project setup for the RV32I core on Zybo Z7-20.
#
# Target board : Digilent Zybo Z7-20 (XC7Z020-1CLG400C, 125 MHz)
#
# Usage (from RISCV project root or from the vivado/ directory):
#
#   vivado -mode tcl -source vivado/create_project.tcl
#   # or, if already inside the vivado/ directory:
#   vivado -mode tcl -source create_project.tcl
#
# This script:
#   1. Creates a Vivado project targeting XC7Z020-1CLG400C (Zybo Z7-20 PL).
#   2. Adds all RTL sources and constraints/zybo_z7.xdc.
#   3. Overrides the HEX_FILE generic so instr_mem finds test_basic.hex.
#   4. Sets fpga_top as the top module.
#
# After running this script open the generated project:
#   vivado vivado/riscv_core_proj/riscv_core.xpr
# Then run:
#   source vivado/run_impl.tcl    # synthesise + implement + write bitstream
################################################################################

# ---- locate directories -------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize "$script_dir/.."]

puts "Project root : $proj_root"
puts "Script dir   : $script_dir"

# ---- create project -----------------------------------------------------------
# Part: XC7Z020-1CLG400C  (Zybo Z7-20 Zynq PL fabric)
set proj_dir "$script_dir/riscv_core_proj"
create_project riscv_core $proj_dir -part xc7z020clg400-1 -force

# ---- add RTL sources ----------------------------------------------------------
# Add package first (must elaborate before modules that import it)
add_files -norecurse [list \
  "$proj_root/rtl/riscv_pkg.sv"      \
  "$proj_root/rtl/pc_incrementer.sv" \
  "$proj_root/rtl/instr_mem.sv"      \
  "$proj_root/rtl/reg_file.sv"       \
  "$proj_root/rtl/control_unit.sv"   \
  "$proj_root/rtl/alu.sv"            \
  "$proj_root/rtl/imm_gen.sv"        \
  "$proj_root/rtl/data_mem.sv"       \
  "$proj_root/rtl/riscv_core.sv"     \
  "$proj_root/rtl/uart_tx.sv"        \
  "$proj_root/rtl/fpga_top.sv"       \
]

# Mark all as SystemVerilog (Vivado may default some to Verilog)
foreach f [get_files *.sv] {
  set_property file_type {SystemVerilog} $f
}

# ---- add hex data file --------------------------------------------------------
# Adding the hex file lets Vivado copy it into the project so $readmemh can
# find it during simulation inside the project.  The HEX_FILE generic below
# passes the absolute path for synthesis.
add_files -norecurse "$proj_root/sw/test_basic.hex"
set_property file_type {Memory Initialization Files} \
  [get_files test_basic.hex]

# ---- constraints --------------------------------------------------------------
add_files -fileset constrs_1 -norecurse \
  "$proj_root/constraints/zybo_z7.xdc"
set_property target_constrs_file \
  [get_files zybo_z7.xdc] [current_fileset -constrset]

# ---- set top module -----------------------------------------------------------
set_property top fpga_top [get_filesets sources_1]
update_compile_order -fileset sources_1

# ---- override HEX_FILE generic ------------------------------------------------
# Pass absolute path so Vivado synthesis resolves $readmemh correctly.
set hex_abs [file normalize "$proj_root/sw/test_basic.hex"]
# Convert Windows backslashes to forward slashes for Verilog string safety
set hex_abs [string map {\\ /} $hex_abs]
set_property generic "HEX_FILE=$hex_abs" [get_filesets sources_1]
puts "HEX_FILE set to: $hex_abs"

# ---- save & report ------------------------------------------------------------
save_project
puts ""
puts "=== Project created: $proj_dir/riscv_core.xpr ==="
puts "    Open in Vivado GUI, or run:"
puts "    vivado -mode tcl -source vivado/run_impl.tcl"
