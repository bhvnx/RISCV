// Combinational read-only instruction memory.
// The PC is byte-addressed; the lower 2 bits are ignored (word-aligned access).
// HEX_FILE parameter gives the default path; pass +HEX_FILE=<path> at runtime
// to override it (used by the regression Makefile target).

module instr_mem #(
  parameter            DepthWords = 32768,
  parameter string     HEX_FILE   = "sw/instr_mem.hex"
) (
  input  logic [31:0] pc_i,
  output logic [31:0] instr_o
);

  localparam AddrWidth = $clog2(DepthWords);

  logic [31:0] mem[DepthWords];

  // If the regression active hex exists (placed there by the Makefile regress
  // target), use it; otherwise fall back to the HEX_FILE parameter default.
  localparam string REGRESS_HEX = "verif/logs/.regress_active.hex";

  initial begin
    integer fd;
    fd = $fopen(REGRESS_HEX, "r");
    if (fd != 0) begin
      $fclose(fd);
      $readmemh(REGRESS_HEX, mem);
    end else begin
      $readmemh(HEX_FILE, mem);
    end
  end

  assign instr_o = mem[pc_i[AddrWidth+1:2]];

endmodule : instr_mem
