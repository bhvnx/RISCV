// FPGA top-level for the RV32I core.
// Targeted at Digilent Zybo Z7-20 (XC7Z020-1CLG400C, 125 MHz).
//
// Stimulus:
//   btn0 (K18) = active-high reset.  Press to restart execution.
//   The instruction ROM (test_basic.hex) IS the stimulus — the processor
//   runs the ADDI/ADD/SUB/LUI/SW/LW/BEQ/ECALL sequence automatically.
//
// Observation:
//   4 user LEDs (LD0-LD3):
//     LD0 = halt_seen  — lights when ECALL is reached
//     LD1 = UART sending — blinks while streaming results
//     LD2 = snap_x3[3] — bit 3 of x3; since ADD gives x3=8=0b1000
//                         this bit = 1 confirms the ADD test passed
//     LD3 = running    — on while executing, off when halted
//
//   UART TX (115200 8N1) on JA Pmod pin 1 (N15):
//     *** The Zybo Z7 USB-UART is wired to the PS (ARM), not the PL.    ***
//     *** Connect a USB-UART cable: JA-pin1(N15)→RX, JA-pin5(GND)→GND. ***
//     Outputs "RV32I HALT\r\nx1=XXXXXXXX\r\nx3=XXXXXXXX\r\nx4=XXXXXXXX\r\n"
//     once after ECALL is reached.
//
//   ILA: mark_debug signals (ila_*) are auto-inserted by Vivado's
//     Tools → Set Up Debug flow after synthesis, letting you view PC,
//     instruction, and register writes live in Hardware Manager.

module fpga_top #(
  parameter string HEX_FILE = "test_basic.hex",
  parameter int    ClkHz    = 125_000_000       // Zybo Z7 oscillator
) (
  input  logic       clk,      // 125 MHz system clock (K17)
  input  logic       btn0,     // BTN0 active-high reset (K18)
  output logic [3:0] led,      // LD0-LD3 (M14, M15, G14, D18)
  output logic       uart_txd  // JA Pmod pin 1 (N15) — connect to USB-UART RX
);

  //-----------------------------------------------------------------------
  // Reset synchroniser  (button is active-high; core uses active-low)
  //-----------------------------------------------------------------------

  logic [1:0] rst_sync_q;
  logic       rst_n;

  always_ff @(posedge clk) begin
    rst_sync_q <= {rst_sync_q[0], ~btn0};
  end
  assign rst_n = rst_sync_q[1];

  //-----------------------------------------------------------------------
  // RISC-V core
  //-----------------------------------------------------------------------

  logic [31:0] dbg_pc, dbg_instr, dbg_wb_data;
  logic        dbg_reg_wr;
  logic [4:0]  dbg_rd_addr;

  riscv_core #(.HEX_FILE(HEX_FILE)) u_riscv_core (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .dbg_pc_o      (dbg_pc),
    .dbg_instr_o   (dbg_instr),
    .dbg_reg_wr_o  (dbg_reg_wr),
    .dbg_rd_addr_o (dbg_rd_addr),
    .dbg_wb_data_o (dbg_wb_data)
  );

  //-----------------------------------------------------------------------
  // Halt detection  (ECALL = 0x00000073)
  //-----------------------------------------------------------------------

  logic halt_seen;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) halt_seen <= 1'b0;
    else if (dbg_instr == 32'h0000_0073) halt_seen <= 1'b1;
  end

  //-----------------------------------------------------------------------
  // Register snapshot  (latch writes to x1, x3, x4 as they happen)
  //-----------------------------------------------------------------------

  logic [31:0] snap_x1, snap_x3, snap_x4;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      snap_x1 <= '0;
      snap_x3 <= '0;
      snap_x4 <= '0;
    end else if (dbg_reg_wr) begin
      unique case (dbg_rd_addr)
        5'd1:    snap_x1 <= dbg_wb_data;
        5'd3:    snap_x3 <= dbg_wb_data;
        5'd4:    snap_x4 <= dbg_wb_data;
        default: ;
      endcase
    end
  end

  //-----------------------------------------------------------------------
  // ILA probe registers  (* mark_debug = "true" *)
  // Vivado's "Set Up Debug" wizard will find these and wire an ILA core.
  //-----------------------------------------------------------------------

  (* mark_debug = "true" *) logic [31:0] ila_pc;
  (* mark_debug = "true" *) logic [31:0] ila_instr;
  (* mark_debug = "true" *) logic        ila_reg_wr;
  (* mark_debug = "true" *) logic [4:0]  ila_rd_addr;
  (* mark_debug = "true" *) logic [31:0] ila_wb_data;
  (* mark_debug = "true" *) logic        ila_halt;

  always_ff @(posedge clk) begin
    ila_pc      <= dbg_pc;
    ila_instr   <= dbg_instr;
    ila_reg_wr  <= dbg_reg_wr;
    ila_rd_addr <= dbg_rd_addr;
    ila_wb_data <= dbg_wb_data;
    ila_halt    <= halt_seen;
  end

  //-----------------------------------------------------------------------
  // UART TX — 115200 baud, 8N1
  // Outputs the register snapshot when halt is detected (once per reset).
  //-----------------------------------------------------------------------

  // nibble → ASCII hex character
  function automatic logic [7:0] n2h(input logic [3:0] n);
    return (n < 4'hA) ? (8'h30 + {4'h0, n}) : (8'h37 + {4'h0, n});
  endfunction

  // Message: "RV32I HALT\r\nx1=XXXXXXXX\r\nx3=XXXXXXXX\r\nx4=XXXXXXXX\r\n"
  //          indices 0-11       12-24          25-37          38-50
  localparam int MSG_LEN = 51;

  function automatic logic [7:0] get_byte(
    input logic [5:0]  idx,
    input logic [31:0] x1, x3, x4
  );
    case (idx)
      6'd0:  return 8'h52; // 'R'
      6'd1:  return 8'h56; // 'V'
      6'd2:  return 8'h33; // '3'
      6'd3:  return 8'h32; // '2'
      6'd4:  return 8'h49; // 'I'
      6'd5:  return 8'h20; // ' '
      6'd6:  return 8'h48; // 'H'
      6'd7:  return 8'h41; // 'A'
      6'd8:  return 8'h4C; // 'L'
      6'd9:  return 8'h54; // 'T'
      6'd10: return 8'h0D; // CR
      6'd11: return 8'h0A; // LF
      6'd12: return 8'h78; // 'x'
      6'd13: return 8'h31; // '1'
      6'd14: return 8'h3D; // '='
      6'd15: return n2h(x1[31:28]);
      6'd16: return n2h(x1[27:24]);
      6'd17: return n2h(x1[23:20]);
      6'd18: return n2h(x1[19:16]);
      6'd19: return n2h(x1[15:12]);
      6'd20: return n2h(x1[11: 8]);
      6'd21: return n2h(x1[ 7: 4]);
      6'd22: return n2h(x1[ 3: 0]);
      6'd23: return 8'h0D;
      6'd24: return 8'h0A;
      6'd25: return 8'h78; // 'x'
      6'd26: return 8'h33; // '3'
      6'd27: return 8'h3D; // '='
      6'd28: return n2h(x3[31:28]);
      6'd29: return n2h(x3[27:24]);
      6'd30: return n2h(x3[23:20]);
      6'd31: return n2h(x3[19:16]);
      6'd32: return n2h(x3[15:12]);
      6'd33: return n2h(x3[11: 8]);
      6'd34: return n2h(x3[ 7: 4]);
      6'd35: return n2h(x3[ 3: 0]);
      6'd36: return 8'h0D;
      6'd37: return 8'h0A;
      6'd38: return 8'h78; // 'x'
      6'd39: return 8'h34; // '4'
      6'd40: return 8'h3D; // '='
      6'd41: return n2h(x4[31:28]);
      6'd42: return n2h(x4[27:24]);
      6'd43: return n2h(x4[23:20]);
      6'd44: return n2h(x4[19:16]);
      6'd45: return n2h(x4[15:12]);
      6'd46: return n2h(x4[11: 8]);
      6'd47: return n2h(x4[ 7: 4]);
      6'd48: return n2h(x4[ 3: 0]);
      6'd49: return 8'h0D;
      6'd50: return 8'h0A;
      default: return 8'h00;
    endcase
  endfunction

  logic       uart_valid, uart_ready;
  logic [7:0] uart_data;
  logic [5:0] msg_ptr;
  logic       sending;
  logic       msg_done;  // prevent re-trigger after message is sent

  uart_tx #(.ClkHz(ClkHz)) u_uart_tx (
    .clk_i   (clk),
    .rst_ni  (rst_n),
    .data_i  (uart_data),
    .valid_i (uart_valid),
    .ready_o (uart_ready),
    .tx_o    (uart_txd)
  );

  assign uart_data  = get_byte(msg_ptr, snap_x1, snap_x3, snap_x4);
  assign uart_valid = sending;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sending  <= 1'b0;
      msg_ptr  <= '0;
      msg_done <= 1'b0;
    end else if (halt_seen && !sending && !msg_done) begin
      sending <= 1'b1;
    end else if (sending && uart_ready) begin
      if (msg_ptr == MSG_LEN - 1) begin
        sending  <= 1'b0;
        msg_ptr  <= '0;
        msg_done <= 1'b1;
      end else begin
        msg_ptr <= msg_ptr + 1;
      end
    end
  end

  //-----------------------------------------------------------------------
  // LEDs  (Zybo Z7 has 4 user LEDs: LD0-LD3)
  //-----------------------------------------------------------------------

  assign led[0] = halt_seen;           // LD0: on when ECALL reached
  assign led[1] = sending;             // LD1: on while streaming UART
  assign led[2] = snap_x3[3];          // LD2: 1 iff x3=8 (ADD test passed)
  assign led[3] = rst_n & ~halt_seen;  // LD3: on while processor is running

endmodule : fpga_top
