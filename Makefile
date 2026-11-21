RTL_SRCS = rtl/riscv_pkg.sv \
           rtl/pc_incrementer.sv \
           rtl/instr_mem.sv \
           rtl/control_unit.sv \
           rtl/imm_gen.sv \
           rtl/reg_file.sv \
           rtl/alu.sv \
           rtl/data_mem.sv \
           rtl/riscv_core.sv

TB_SRCS  = tb/riscv_core_tb.sv

# riscv-dv test directories: any verif/logs/ subdirectory that has both
# an instr_mem.hex and a spike_parsed.json is a valid regression test.
.PHONY: all sim run gen regress fullregress clean

all: sim

sim: obj_dir/Vriscv_core_tb

obj_dir/Vriscv_core_tb: $(RTL_SRCS) $(TB_SRCS)
	mkdir -p verif/logs
	verilator --sv --cc --exe --main --timing \
	  --top-module riscv_core_tb \
	  --Mdir obj_dir \
	  $(RTL_SRCS) $(TB_SRCS)
	make -C obj_dir -f Vriscv_core_tb.mk

run: obj_dir/Vriscv_core_tb
	mkdir -p verif/logs
	cd $(CURDIR) && obj_dir/Vriscv_core_tb

# ---------------------------------------------------------------------------
# Test generation target
#
# Reads verif/tests.yaml, calls riscv-dv to generate .S files, compiles them
# to ELF + instr_mem.hex, and runs Spike to produce spike_parsed.json.
# All outputs land in verif/logs/<test_name>_N/.
# Existing test folders are detected and skipped automatically.
# ---------------------------------------------------------------------------
gen:
	python3 verif/scripts/gen_all.py

# Full flow: generate new tests then simulate them against the DUT.
fullregress: gen regress

# ---------------------------------------------------------------------------
# Regression target
#
# For each test directory:
#   1. Fix the hex file address: riscv-dv objcopy emits @20000000 (word
#      address for 0x80000000), but instr_mem indexes mem[pc[9:2]] so it
#      expects @00000000.  A sed one-liner rewrites it into a temp file.
#   2. Run the simulator with +HEX_FILE, +DUT_LOG, +REGRESSION=1, and a
#      generous +MAX_CYCLES so long tests run to their ECALL halt.
#   3. Compare DUT commit log against Spike golden log.
# ---------------------------------------------------------------------------
MAX_REGRESS_CYCLES ?= 200000

regress: obj_dir/Vriscv_core_tb
	@pass=0; fail=0; skip=0; \
	for d in $$(ls -d verif/logs/riscv_arithmetic_basic_test_* 2>/dev/null | sort -V); do \
	  hex=$$d/instr_mem.hex; \
	  spike=$$d/spike_parsed.json; \
	  dut=$$d/dut.log; \
	  if [ ! -f "$$hex" ] || [ ! -f "$$spike" ]; then \
	    echo "SKIP $$d (missing hex or spike log)"; \
	    skip=$$((skip + 1)); continue; \
	  fi; \
	  echo ""; \
	  echo "=== $$d ==="; \
	  awk '/^@/{c++; if(c==1){print "@00000000"; next} else {exit}} {print}' "$$hex" > $(CURDIR)/verif/logs/.regress_active.hex; \
	  $(CURDIR)/obj_dir/Vriscv_core_tb \
	    +DUT_LOG="$$dut" \
	    +MAX_CYCLES=$(MAX_REGRESS_CYCLES) \
	    +REGRESSION=1; \
	  if python3 verif/scripts/compare_logs.py "$$spike" "$$dut"; then \
	    pass=$$((pass + 1)); \
	  else \
	    fail=$$((fail + 1)); \
	  fi; \
	done; \
	echo ""; \
	echo "=== Regression complete: $$pass passed, $$fail failed, $$skip skipped ==="; \
	rm -f $(CURDIR)/verif/logs/.regress_active.hex

clean:
	rm -rf obj_dir verif/logs/dut.log
