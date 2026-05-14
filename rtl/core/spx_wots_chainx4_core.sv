module spx_wots_chainx4_core (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,

    input  logic [127:0] pub_seed,

    input  logic [255:0] addr0,
    input  logic [255:0] addr1,
    input  logic [255:0] addr2,
    input  logic [255:0] addr3,

    input  logic [127:0] in0,
    input  logic [127:0] in1,
    input  logic [127:0] in2,
    input  logic [127:0] in3,

    input  logic [7:0]   start_step,
    input  logic [7:0]   num_steps,

    output logic         done,
    output logic         busy,
    output logic         error,

    output logic [127:0] out0,
    output logic [127:0] out1,
    output logic [127:0] out2,
    output logic [127:0] out3
);
  timeunit 1ns;
  timeprecision 1ps;

  localparam int unsigned SPX_WOTS_W      = 16;
  localparam int unsigned SPX_HASH_OFFSET = 31;

  typedef enum logic [1:0] {
    ST_IDLE,
    ST_START_THASH,
    ST_WAIT_THASH
  } state_e;

  state_e state_q;

  logic [127:0] pub_seed_q;
  logic [255:0] addr0_q;
  logic [255:0] addr1_q;
  logic [255:0] addr2_q;
  logic [255:0] addr3_q;
  logic [127:0] chain0_q;
  logic [127:0] chain1_q;
  logic [127:0] chain2_q;
  logic [127:0] chain3_q;
  logic [7:0]   step_q;
  logic [7:0]   steps_left_q;

  logic         thash_start;
  logic         thash_done;
  logic [127:0] thash_out0;
  logic [127:0] thash_out1;
  logic [127:0] thash_out2;
  logic [127:0] thash_out3;

  logic [8:0] requested_end;
  logic       start_config_ok;

  assign busy = (state_q != ST_IDLE);
  assign thash_start = (state_q == ST_START_THASH);
  assign requested_end = {1'b0, start_step} + {1'b0, num_steps};
  assign start_config_ok = (start_step <= 8'(SPX_WOTS_W)) &&
                           (num_steps <= 8'(SPX_WOTS_W - 1)) &&
                           (requested_end <= 9'(SPX_WOTS_W));

  function automatic logic [255:0] addr_with_hash(
      input logic [255:0] addr,
      input logic [7:0] hash_step
  );
    logic [255:0] updated;
    begin
      updated = addr;
      updated[8 * SPX_HASH_OFFSET +: 8] = hash_step;
      addr_with_hash = updated;
    end
  endfunction

  spx_thashx4_core u_thashx4_core (
      .clk(clk),
      .rst_n(rst_n),
      .start(thash_start),
      .inblocks(2'd1),
      .pub_seed(pub_seed_q),
      .addr0(addr0_q),
      .addr1(addr1_q),
      .addr2(addr2_q),
      .addr3(addr3_q),
      .in0({128'd0, chain0_q}),
      .in1({128'd0, chain1_q}),
      .in2({128'd0, chain2_q}),
      .in3({128'd0, chain3_q}),
      .done(thash_done),
      .out0(thash_out0),
      .out1(thash_out1),
      .out2(thash_out2),
      .out3(thash_out3)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= ST_IDLE;
      done         <= 1'b0;
      error        <= 1'b0;
      pub_seed_q   <= '0;
      addr0_q      <= '0;
      addr1_q      <= '0;
      addr2_q      <= '0;
      addr3_q      <= '0;
      chain0_q     <= '0;
      chain1_q     <= '0;
      chain2_q     <= '0;
      chain3_q     <= '0;
      step_q       <= '0;
      steps_left_q <= '0;
      out0         <= '0;
      out1         <= '0;
      out2         <= '0;
      out3         <= '0;
    end else begin
      done <= 1'b0;

      unique case (state_q)
        ST_IDLE: begin
          if (start) begin
            error <= !start_config_ok;
            if (!start_config_ok) begin
              out0 <= '0;
              out1 <= '0;
              out2 <= '0;
              out3 <= '0;
              done <= 1'b1;
            end else if (num_steps == 8'd0) begin
              out0  <= in0;
              out1  <= in1;
              out2  <= in2;
              out3  <= in3;
              done  <= 1'b1;
              error <= 1'b0;
            end else begin
              pub_seed_q   <= pub_seed;
              addr0_q      <= addr_with_hash(addr0, start_step);
              addr1_q      <= addr_with_hash(addr1, start_step);
              addr2_q      <= addr_with_hash(addr2, start_step);
              addr3_q      <= addr_with_hash(addr3, start_step);
              chain0_q     <= in0;
              chain1_q     <= in1;
              chain2_q     <= in2;
              chain3_q     <= in3;
              step_q       <= start_step;
              steps_left_q <= num_steps;
              error        <= 1'b0;
              state_q      <= ST_START_THASH;
            end
          end
        end

        ST_START_THASH: begin
          state_q <= ST_WAIT_THASH;
        end

        ST_WAIT_THASH: begin
          if (thash_done) begin
            if (steps_left_q == 8'd1) begin
              out0         <= thash_out0;
              out1         <= thash_out1;
              out2         <= thash_out2;
              out3         <= thash_out3;
              steps_left_q <= 8'd0;
              done         <= 1'b1;
              state_q      <= ST_IDLE;
            end else begin
              chain0_q     <= thash_out0;
              chain1_q     <= thash_out1;
              chain2_q     <= thash_out2;
              chain3_q     <= thash_out3;
              step_q       <= step_q + 8'd1;
              steps_left_q <= steps_left_q - 8'd1;
              addr0_q      <= addr_with_hash(addr0_q, step_q + 8'd1);
              addr1_q      <= addr_with_hash(addr1_q, step_q + 8'd1);
              addr2_q      <= addr_with_hash(addr2_q, step_q + 8'd1);
              addr3_q      <= addr_with_hash(addr3_q, step_q + 8'd1);
              state_q      <= ST_START_THASH;
            end
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
