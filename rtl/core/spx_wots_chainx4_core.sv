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
    output logic [127:0] out3,

    output logic         wots_req_valid,
    input  logic         wots_req_ready,
    output logic [127:0] wots_req_pub_seed,
    output logic [255:0] wots_req_addr0,
    output logic [255:0] wots_req_addr1,
    output logic [255:0] wots_req_addr2,
    output logic [255:0] wots_req_addr3,
    output logic [255:0] wots_req_in0,
    output logic [255:0] wots_req_in1,
    output logic [255:0] wots_req_in2,
    output logic [255:0] wots_req_in3,

    input  logic         wots_rsp_valid,
    input  logic [127:0] wots_rsp_out0,
    input  logic [127:0] wots_rsp_out1,
    input  logic [127:0] wots_rsp_out2,
    input  logic [127:0] wots_rsp_out3
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

  logic [8:0] requested_end;
  logic       start_config_ok;

  assign busy = (state_q != ST_IDLE);
  assign wots_req_valid = (state_q == ST_START_THASH);
  assign wots_req_pub_seed = pub_seed_q;
  assign wots_req_addr0 = addr0_q;
  assign wots_req_addr1 = addr1_q;
  assign wots_req_addr2 = addr2_q;
  assign wots_req_addr3 = addr3_q;
  assign wots_req_in0 = {128'd0, chain0_q};
  assign wots_req_in1 = {128'd0, chain1_q};
  assign wots_req_in2 = {128'd0, chain2_q};
  assign wots_req_in3 = {128'd0, chain3_q};
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
          if (wots_req_ready) begin
            state_q <= ST_WAIT_THASH;
          end
        end

        ST_WAIT_THASH: begin
          if (wots_rsp_valid) begin
            if (steps_left_q == 8'd1) begin
              out0         <= wots_rsp_out0;
              out1         <= wots_rsp_out1;
              out2         <= wots_rsp_out2;
              out3         <= wots_rsp_out3;
              steps_left_q <= 8'd0;
              done         <= 1'b1;
              state_q      <= ST_IDLE;
            end else begin
              chain0_q     <= wots_rsp_out0;
              chain1_q     <= wots_rsp_out1;
              chain2_q     <= wots_rsp_out2;
              chain3_q     <= wots_rsp_out3;
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
