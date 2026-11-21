// 8N1 UART transmitter.
// Ready/valid handshake: assert valid_i with data_i; byte is accepted when
// ready_o is high in the same cycle. ready_o goes low during transmission.

module uart_tx #(
  parameter int ClkHz    = 100_000_000,
  parameter int BaudRate = 115_200
) (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic [7:0] data_i,
  input  logic       valid_i,
  output logic       ready_o,
  output logic       tx_o
);

  localparam int BIT_TICKS = ClkHz / BaudRate;  // 868 at 100 MHz / 115200

  typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_e;

  state_e              state_q;
  logic [$clog2(BIT_TICKS)-1:0] tick_q;
  logic [2:0]          bit_q;
  logic [7:0]          shift_q;

  assign ready_o = (state_q == IDLE);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      tx_o    <= 1'b1;
      tick_q  <= '0;
      bit_q   <= '0;
      shift_q <= '0;
    end else begin
      unique case (state_q)
        IDLE: begin
          tx_o <= 1'b1;
          if (valid_i) begin
            shift_q <= data_i;
            tick_q  <= '0;
            state_q <= START;
          end
        end

        START: begin
          tx_o <= 1'b0;
          if (tick_q == BIT_TICKS - 1) begin
            tick_q  <= '0;
            bit_q   <= '0;
            state_q <= DATA;
          end else begin
            tick_q <= tick_q + 1;
          end
        end

        DATA: begin
          tx_o <= shift_q[0];
          if (tick_q == BIT_TICKS - 1) begin
            tick_q  <= '0;
            shift_q <= {1'b0, shift_q[7:1]};
            if (bit_q == 3'd7) begin
              state_q <= STOP;
            end else begin
              bit_q <= bit_q + 1;
            end
          end else begin
            tick_q <= tick_q + 1;
          end
        end

        STOP: begin
          tx_o <= 1'b1;
          if (tick_q == BIT_TICKS - 1) begin
            tick_q  <= '0;
            state_q <= IDLE;
          end else begin
            tick_q <= tick_q + 1;
          end
        end

        default: state_q <= IDLE;
      endcase
    end
  end

endmodule : uart_tx
