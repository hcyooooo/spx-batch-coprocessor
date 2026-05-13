module spx_thashx4_core (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic [1:0]   inblocks,

    input  logic [127:0] pub_seed,

    input  logic [255:0] addr0,
    input  logic [255:0] addr1,
    input  logic [255:0] addr2,
    input  logic [255:0] addr3,

    input  logic [255:0] in0,
    input  logic [255:0] in1,
    input  logic [255:0] in2,
    input  logic [255:0] in3,

    output logic         done,
    output logic [127:0] out0,
    output logic [127:0] out1,
    output logic [127:0] out2,
    output logic [127:0] out3
);
  timeunit 1ns;
  timeprecision 1ps;

  import spx_thashx4_pkg::*;

  typedef enum logic [1:0] {
    ST_IDLE,
    ST_START_CORE,
    ST_WAIT_CORE
  } state_e;

  state_e state_q;

  logic [KECCAK_STATE_BITS-1:0] absorb0_q;
  logic [KECCAK_STATE_BITS-1:0] absorb1_q;
  logic [KECCAK_STATE_BITS-1:0] absorb2_q;
  logic [KECCAK_STATE_BITS-1:0] absorb3_q;

  logic          core_start;
  logic          core_done;
  logic [KECCAK_STATE_BITS-1:0] core_state0;
  logic [KECCAK_STATE_BITS-1:0] core_state1;
  logic [KECCAK_STATE_BITS-1:0] core_state2;
  logic [KECCAK_STATE_BITS-1:0] core_state3;
  logic                         unused_core_state_bits;

  assign core_start = (state_q == ST_START_CORE);
  assign unused_core_state_bits = ^{
      core_state0[KECCAK_STATE_BITS-1:128],
      core_state1[KECCAK_STATE_BITS-1:128],
      core_state2[KECCAK_STATE_BITS-1:128],
      core_state3[KECCAK_STATE_BITS-1:128]
  };

  function automatic logic [KECCAK_STATE_BITS-1:0] build_absorb_state(
      input logic [127:0] pub_seed_f,
      input logic [255:0] addr_f,
      input logic [255:0] in_f,
      input logic [1:0]   inblocks_f
  );
    logic [KECCAK_STATE_BITS-1:0] state;
    int unsigned inbytes;
    begin
      state = '0;
      inbytes = (inblocks_f == 2'd2) ? 32 : 16;

      for (int i = 0; i < SPX_N; i++) begin
        state[8 * i +: 8] = pub_seed_f[8 * i +: 8];
      end

      for (int i = 0; i < SPX_ADDR_BYTES; i++) begin
        state[8 * (SPX_N + i) +: 8] = addr_f[8 * i +: 8];
      end

      for (int i = 0; i < 32; i++) begin
        if (i < inbytes) begin
          state[8 * (SPX_N + SPX_ADDR_BYTES + i) +: 8] = in_f[8 * i +: 8];
        end
      end

      state[8 * (SPX_N + SPX_ADDR_BYTES + inbytes) +: 8] = 8'h1f;
      state[8 * (SHAKE256_RATE - 1) +: 8] = 8'h80;
      build_absorb_state = state;
    end
  endfunction

  spx_keccakx4_core u_keccakx4 (
      .clk(clk),
      .rst_n(rst_n),
      .start(core_start),
      .state0_i(absorb0_q),
      .state1_i(absorb1_q),
      .state2_i(absorb2_q),
      .state3_i(absorb3_q),
      .done(core_done),
      .state0_o(core_state0),
      .state1_o(core_state1),
      .state2_o(core_state2),
      .state3_o(core_state3)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q   <= ST_IDLE;
      done      <= 1'b0;
      absorb0_q <= '0;
      absorb1_q <= '0;
      absorb2_q <= '0;
      absorb3_q <= '0;
      out0      <= '0;
      out1      <= '0;
      out2      <= '0;
      out3      <= '0;
    end else begin
      done <= 1'b0;

      unique case (state_q)
        ST_IDLE: begin
          if (start) begin
            if ((inblocks == 2'd1) || (inblocks == 2'd2)) begin
              absorb0_q <= build_absorb_state(pub_seed, addr0, in0, inblocks);
              absorb1_q <= build_absorb_state(pub_seed, addr1, in1, inblocks);
              absorb2_q <= build_absorb_state(pub_seed, addr2, in2, inblocks);
              absorb3_q <= build_absorb_state(pub_seed, addr3, in3, inblocks);
              state_q   <= ST_START_CORE;
            end else begin
              out0 <= '0;
              out1 <= '0;
              out2 <= '0;
              out3 <= '0;
              done <= 1'b1;
            end
          end
        end

        ST_START_CORE: begin
          state_q <= ST_WAIT_CORE;
        end

        ST_WAIT_CORE: begin
          if (core_done) begin
            out0    <= core_state0[127:0];
            out1    <= core_state1[127:0];
            out2    <= core_state2[127:0];
            out3    <= core_state3[127:0];
            done    <= 1'b1;
            state_q <= ST_IDLE;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
