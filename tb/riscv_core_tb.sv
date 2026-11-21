// Functional verification testbench for riscv_core.
//
// Instructions are loaded from sw/instr_mem.hex via $readmemh in instr_mem.
// See sw/test_basic.s for the program listing.

module riscv_core_tb;

  localparam int CLK_HALF = 5;  // 10 ns period

  logic clk;
  logic rst_n;

  int     pass_count;
  int     fail_count;
  integer log_fd;        // commit log file handle
  logic   halt_seen;     // stops logging once we reach the halt instruction
  string  log_path;      // dut.log destination — set by +DUT_LOG= or default
  string  hex_override;  // instruction hex override — set by +HEX_FILE=
  int     max_cycles;    // sim run length    — set by +MAX_CYCLES= or default
  int     regression;    // 1 = skip test_basic.s checks — set by +REGRESSION=1

  // Debug port wires
  logic [31:0] dbg_pc;
  logic [31:0] dbg_instr;
  logic        dbg_reg_wr;
  logic [4:0]  dbg_rd_addr;
  logic [31:0] dbg_wb_data;

  //-----------------------------------------------------------------------
  // DUT
  //-----------------------------------------------------------------------

  riscv_core u_riscv_core (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .dbg_pc_o      (dbg_pc),
    .dbg_instr_o   (dbg_instr),
    .dbg_reg_wr_o  (dbg_reg_wr),
    .dbg_rd_addr_o (dbg_rd_addr),
    .dbg_wb_data_o (dbg_wb_data)
  );

  //-----------------------------------------------------------------------
  // Clock
  //-----------------------------------------------------------------------

  initial clk = 1'b0;
  always #CLK_HALF clk = ~clk;

  //-----------------------------------------------------------------------
  // Commit log — one line per instruction, written to dut.log
  //
  // Format matches compare_logs.py:
  //   with rd write:  PC=0x....  INSTR=0x....  RD=xN  VAL=0x....
  //   without:        PC=0x....  INSTR=0x....
  //
  // In a single-cycle core every clock after reset is one commit.
  // Logging stops when the halt instruction (JAL x0, 0) is seen so
  // the log ends cleanly rather than repeating the halt forever.
  //-----------------------------------------------------------------------

  always @(posedge clk) begin
    if (rst_n && !halt_seen) begin
      if (dbg_reg_wr && dbg_rd_addr != 5'b0) begin
        $fwrite(log_fd, "PC=0x%08h INSTR=0x%08h RD=x%0d VAL=0x%08h\n",
                dbg_pc, dbg_instr, dbg_rd_addr, dbg_wb_data);
      end else begin
        $fwrite(log_fd, "PC=0x%08h INSTR=0x%08h\n",
                dbg_pc, dbg_instr);
      end
      if (regression == 0)
        $display("  [%0t ns]  PC=0x%08h  instr=0x%08h", $time, dbg_pc, dbg_instr);
      // ECALL (0x00000073) = halt sentinel, matches Spike's exit trigger
      if (dbg_instr == 32'h00000073) halt_seen = 1'b1;
    end
  end

  //-----------------------------------------------------------------------
  // Tasks
  //-----------------------------------------------------------------------

  task automatic check_reg(
    input int          reg_num,
    input logic [31:0] expected
  );
    logic [31:0] actual;
    actual = u_riscv_core.u_reg_file.regs_q[reg_num];
    if (actual === expected) begin
      $display("  PASS  x%-2d = 0x%08h", reg_num, actual);
      pass_count++;
    end else begin
      $display("  FAIL  x%-2d = 0x%08h  (expected 0x%08h)",
               reg_num, actual, expected);
      fail_count++;
    end
  endtask

  task automatic check_dmem(
    input int          word_index,
    input logic [31:0] expected
  );
    logic [31:0] actual;
    actual = u_riscv_core.u_data_mem.mem[word_index];
    if (actual === expected) begin
      $display("  PASS  dmem[%0d] = 0x%08h", word_index, actual);
      pass_count++;
    end else begin
      $display("  FAIL  dmem[%0d] = 0x%08h  (expected 0x%08h)",
               word_index, actual, expected);
      fail_count++;
    end
  endtask

  //-----------------------------------------------------------------------
  // Stimulus and checking
  //-----------------------------------------------------------------------

  initial begin
    pass_count = 0;
    fail_count = 0;
    halt_seen  = 1'b0;

    if (!$value$plusargs("DUT_LOG=%s",    log_path))   log_path   = "verif/logs/dut.log";
    if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) max_cycles = 25;
    if (!$value$plusargs("REGRESSION=%d", regression)) regression = 0;

    log_fd = $fopen(log_path, "w");
    if (log_fd == 0) begin
      $display("ERROR: could not open %s", log_path);
      $display("       Run simulation from C:/Users/marpa/RISCV/");
      $finish;
    end

    rst_n = 1'b0;

    // Hold reset for 2 cycles then release on a falling edge.
    repeat (2) @(posedge clk);

    @(negedge clk);
    rst_n = 1'b1;

    // Run until ECALL halt sentinel or max_cycles (whichever comes first).
    for (int cycle_i = 0; cycle_i < max_cycles; cycle_i++) begin
      @(posedge clk);
      if (halt_seen) break;
    end

    // Smoke checks for test_basic.s — skipped in regression mode.
    if (regression == 0) begin
      $display("");
      $display("=== Register File ===");
      check_reg(1, 32'd5);          // addi x1, x0, 5
      check_reg(2, 32'd3);          // addi x2, x0, 3
      check_reg(3, 32'd8);          // add  x3 = x1 + x2
      check_reg(4, 32'd2);          // sub  x4 = x1 - x2
      check_reg(8, 32'h80001000);   // lui  x8, 0x80001
      check_reg(5, 32'd8);          // lw   x5 = dmem[0] = 8
      check_reg(6, 32'h0AA);        // PASS: beq taken → addi x6 = 0xAA
      check_reg(7, 32'd0);          // FAIL skipped → x7 stays 0

      $display("=== Data Memory ===");
      check_dmem(0, 32'd8);

      $display("====================");
      $display("  %0d passed,  %0d failed", pass_count, fail_count);
      $display("====================");

      if (fail_count == 0) $display("ALL TESTS PASSED");
      else                 $display("TESTS FAILED");
    end

    $fclose(log_fd);
    $display("Commit log written to %s", log_path);
    $finish;
  end

  // Uncomment to dump waveforms for GTKWave:
  // initial begin
  //   $dumpfile("riscv_core_tb.vcd");
  //   $dumpvars(0, riscv_core_tb);
  // end

endmodule
