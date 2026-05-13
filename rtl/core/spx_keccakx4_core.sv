module spx_keccakx4_core (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          start,
    input  logic [1599:0] state0_i,
    input  logic [1599:0] state1_i,
    input  logic [1599:0] state2_i,
    input  logic [1599:0] state3_i,
    output logic          done,
    output logic [1599:0] state0_o,
    output logic [1599:0] state1_o,
    output logic [1599:0] state2_o,
    output logic [1599:0] state3_o
);
  timeunit 1ns;
  timeprecision 1ps;

  import spx_thashx4_pkg::*;

  logic          busy_q;
  logic [4:0]    round_q;
  logic [KECCAK_STATE_BITS-1:0] state0_q;
  logic [KECCAK_STATE_BITS-1:0] state1_q;
  logic [KECCAK_STATE_BITS-1:0] state2_q;
  logic [KECCAK_STATE_BITS-1:0] state3_q;

  logic [KECCAK_STATE_BITS-1:0] state0_round;
  logic [KECCAK_STATE_BITS-1:0] state1_round;
  logic [KECCAK_STATE_BITS-1:0] state2_round;
  logic [KECCAK_STATE_BITS-1:0] state3_round;

  spx_keccak_round u_round0 (
      .round_i(round_q),
      .state_i(state0_q),
      .state_o(state0_round)
  );

  spx_keccak_round u_round1 (
      .round_i(round_q),
      .state_i(state1_q),
      .state_o(state1_round)
  );

  spx_keccak_round u_round2 (
      .round_i(round_q),
      .state_i(state2_q),
      .state_o(state2_round)
  );

  spx_keccak_round u_round3 (
      .round_i(round_q),
      .state_i(state3_q),
      .state_o(state3_round)
  );

  assign state0_o = state0_q;
  assign state1_o = state1_q;
  assign state2_o = state2_q;
  assign state3_o = state3_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q   <= 1'b0;
      done     <= 1'b0;
      round_q  <= 5'd0;
      state0_q <= '0;
      state1_q <= '0;
      state2_q <= '0;
      state3_q <= '0;
    end else begin
      done <= 1'b0;

      if (busy_q) begin
        state0_q <= state0_round;
        state1_q <= state1_round;
        state2_q <= state2_round;
        state3_q <= state3_round;

        if (round_q == KECCAK_LAST_ROUND) begin
          busy_q  <= 1'b0;
          round_q <= 5'd0;
          done    <= 1'b1;
        end else begin
          round_q <= round_q + 5'd1;
        end
      end else if (start) begin
        busy_q   <= 1'b1;
        round_q  <= 5'd0;
        state0_q <= state0_i;
        state1_q <= state1_i;
        state2_q <= state2_i;
        state3_q <= state3_i;
      end
    end
  end
endmodule
