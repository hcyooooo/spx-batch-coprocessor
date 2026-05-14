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
    input  logic         mixed_mode,
    input  logic [31:0]  start_steps_packed,
    input  logic [31:0]  num_steps_packed,

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

  localparam int unsigned LANES           = 4;
  localparam int unsigned SPX_WOTS_W      = 16;
  localparam int unsigned SPX_HASH_OFFSET = 31;

  typedef enum logic [1:0] {
    ST_IDLE,
    ST_START_THASH,
    ST_WAIT_THASH
  } state_e;

  state_e state_q;

  logic [127:0] pub_seed_q;
  logic [255:0] addr_q [0:LANES-1];
  logic [127:0] chain_q [0:LANES-1];
  logic [7:0]   step_q [0:LANES-1];
  logic [7:0]   steps_left_q [0:LANES-1];

  logic [255:0] addr_in [0:LANES-1];
  logic [127:0] chain_in [0:LANES-1];
  logic [127:0] rsp_lane [0:LANES-1];

  logic [7:0] cfg_start_step [0:LANES-1];
  logic [7:0] cfg_num_steps [0:LANES-1];
  logic [8:0] requested_end [0:LANES-1];
  logic       start_config_ok;
  logic       any_steps_requested;

  logic [3:0]   active_mask;
  logic [127:0] chain_next [0:LANES-1];
  logic [7:0]   step_next [0:LANES-1];
  logic [7:0]   steps_left_next [0:LANES-1];
  logic         all_steps_done_next;

  assign addr_in[0] = addr0;
  assign addr_in[1] = addr1;
  assign addr_in[2] = addr2;
  assign addr_in[3] = addr3;

  assign chain_in[0] = in0;
  assign chain_in[1] = in1;
  assign chain_in[2] = in2;
  assign chain_in[3] = in3;

  assign rsp_lane[0] = wots_rsp_out0;
  assign rsp_lane[1] = wots_rsp_out1;
  assign rsp_lane[2] = wots_rsp_out2;
  assign rsp_lane[3] = wots_rsp_out3;

  assign busy = (state_q != ST_IDLE);
  assign wots_req_valid = (state_q == ST_START_THASH);
  assign wots_req_pub_seed = pub_seed_q;
  assign wots_req_addr0 = addr_q[0];
  assign wots_req_addr1 = addr_q[1];
  assign wots_req_addr2 = addr_q[2];
  assign wots_req_addr3 = addr_q[3];
  assign wots_req_in0 = {128'd0, chain_q[0]};
  assign wots_req_in1 = {128'd0, chain_q[1]};
  assign wots_req_in2 = {128'd0, chain_q[2]};
  assign wots_req_in3 = {128'd0, chain_q[3]};

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

  always_comb begin
    start_config_ok = 1'b1;
    any_steps_requested = 1'b0;

    for (int lane = 0; lane < LANES; lane++) begin
      cfg_start_step[lane] = mixed_mode ? start_steps_packed[8 * lane +: 8] :
                                          start_step;
      cfg_num_steps[lane] = mixed_mode ? num_steps_packed[8 * lane +: 8] :
                                        num_steps;
      requested_end[lane] = {1'b0, cfg_start_step[lane]} +
                            {1'b0, cfg_num_steps[lane]};

      if ((cfg_start_step[lane] > 8'(SPX_WOTS_W)) ||
          (cfg_num_steps[lane] > 8'(SPX_WOTS_W - 1)) ||
          (requested_end[lane] > 9'(SPX_WOTS_W))) begin
        start_config_ok = 1'b0;
      end

      if (cfg_num_steps[lane] != 8'd0) begin
        any_steps_requested = 1'b1;
      end
    end
  end

  always_comb begin
    all_steps_done_next = 1'b1;

    for (int lane = 0; lane < LANES; lane++) begin
      active_mask[lane] = (steps_left_q[lane] != 8'd0);
      chain_next[lane] = chain_q[lane];
      step_next[lane] = step_q[lane];
      steps_left_next[lane] = steps_left_q[lane];

      if (active_mask[lane]) begin
        chain_next[lane] = rsp_lane[lane];
        step_next[lane] = step_q[lane] + 8'd1;
        steps_left_next[lane] = steps_left_q[lane] - 8'd1;
      end

      if (steps_left_next[lane] != 8'd0) begin
        all_steps_done_next = 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q    <= ST_IDLE;
      done       <= 1'b0;
      error      <= 1'b0;
      pub_seed_q <= '0;
      out0       <= '0;
      out1       <= '0;
      out2       <= '0;
      out3       <= '0;

      for (int lane = 0; lane < LANES; lane++) begin
        addr_q[lane]       <= '0;
        chain_q[lane]      <= '0;
        step_q[lane]       <= '0;
        steps_left_q[lane] <= '0;
      end
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
            end else if (!any_steps_requested) begin
              out0  <= in0;
              out1  <= in1;
              out2  <= in2;
              out3  <= in3;
              done  <= 1'b1;
              error <= 1'b0;
            end else begin
              pub_seed_q <= pub_seed;
              error      <= 1'b0;
              state_q    <= ST_START_THASH;

              for (int lane = 0; lane < LANES; lane++) begin
                addr_q[lane]       <= addr_with_hash(addr_in[lane],
                                                     cfg_start_step[lane]);
                chain_q[lane]      <= chain_in[lane];
                step_q[lane]       <= cfg_start_step[lane];
                steps_left_q[lane] <= cfg_num_steps[lane];
              end
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
            for (int lane = 0; lane < LANES; lane++) begin
              chain_q[lane]      <= chain_next[lane];
              step_q[lane]       <= step_next[lane];
              steps_left_q[lane] <= steps_left_next[lane];
              if (steps_left_next[lane] != 8'd0) begin
                addr_q[lane] <= addr_with_hash(addr_q[lane], step_next[lane]);
              end
            end

            if (all_steps_done_next) begin
              out0    <= chain_next[0];
              out1    <= chain_next[1];
              out2    <= chain_next[2];
              out3    <= chain_next[3];
              done    <= 1'b1;
              state_q <= ST_IDLE;
            end else begin
              state_q <= ST_START_THASH;
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
