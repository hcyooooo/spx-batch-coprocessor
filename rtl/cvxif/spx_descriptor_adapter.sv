module spx_descriptor_adapter #(
    parameter int MEM_WORDS_PER_CYCLE = 1,
    parameter int MEM_ADDR_WIDTH      = 32
) (
    input  logic                                      clk,
    input  logic                                      rst_n,

    input  logic                                      start,
    input  logic [MEM_ADDR_WIDTH-1:0]                 descriptor_addr,

    output logic                                      busy,
    output logic                                      done,
    output logic                                      error,
    output logic [31:0]                               status,

    output logic                                      mem_valid,
    input  logic                                      mem_ready,
    output logic                                      mem_we,
    output logic [MEM_ADDR_WIDTH-1:0]                 mem_addr,
    output logic [(32*MEM_WORDS_PER_CYCLE)-1:0]       mem_wdata,
    input  logic [(32*MEM_WORDS_PER_CYCLE)-1:0]       mem_rdata,
    input  logic                                      mem_error,

    output logic [31:0]                               perf_load_cycles,
    output logic [31:0]                               perf_core_cycles,
    output logic [31:0]                               perf_store_cycles,
    output logic [31:0]                               perf_total_cycles
);
  timeunit 1ns;
  timeprecision 1ps;

  localparam int ALIGN_BYTES       = 16;
  localparam int DESC_HEADER_WORDS = 8;
  localparam int PUB_SEED_WORDS    = 4;
  localparam int ADDR_WORDS        = 32;
  localparam int WOTS_INPUT_WORDS  = 16;
  localparam int OUTPUT_WORDS      = 16;

  localparam int DESC_FLAGS_STATUS_WORD = 0;
  localparam int DESC_CONFIG_WORD       = 1;
  localparam int DESC_PUB_SEED_PTR_WORD = 2;
  localparam int DESC_ADDR_BASE_WORD    = 3;
  localparam int DESC_INPUT_BASE_WORD   = 4;
  localparam int DESC_OUTPUT_BASE_WORD  = 5;
  localparam int DESC_CHAIN_CTRL_WORD   = 7;

  localparam int FLAG_INLINE_PUB_SEED_BIT = 0;
  localparam int STATUS_DONE_BIT          = 1;
  localparam int STATUS_ERROR_BIT         = 2;
  localparam int STATUS_ERROR_CODE_LSB    = 4;

  localparam logic [7:0] CONFIG_VARIANT_SHAKE_128F_SIMPLE = 8'h01;
  localparam logic [3:0] CONFIG_LANES_X4                  = 4'h4;
  localparam int CONFIG_OP_TYPE_LSB = 16;

  localparam logic [7:0] OP_TYPE_THASHX4       = 8'h00;
  localparam logic [7:0] OP_TYPE_WOTS_CHAINX4  = 8'h01;

  localparam int CHAIN_CTRL_START_STEP_LSB = 0;
  localparam int CHAIN_CTRL_NUM_STEPS_LSB  = 8;

  localparam logic [3:0] ERR_NONE        = 4'h0;
  localparam logic [3:0] ERR_BAD_CONFIG  = 4'h1;
  localparam logic [3:0] ERR_BAD_ALIGN   = 4'h2;
  localparam logic [3:0] ERR_MEM_READ    = 4'h3;
  localparam logic [3:0] ERR_MEM_WRITE   = 4'h4;
  localparam logic [3:0] ERR_BAD_OP_TYPE = 4'h5;
  localparam logic [3:0] ERR_BAD_CHAIN   = 4'h6;

  localparam logic [MEM_ADDR_WIDTH-1:0] MEM_ALIGN_MASK =
      MEM_ADDR_WIDTH'(ALIGN_BYTES - 1);
  localparam logic [MEM_ADDR_WIDTH-1:0] INLINE_SEED_DESC_OFFSET =
      MEM_ADDR_WIDTH'(DESC_HEADER_WORDS * 4);

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_READ_DESC,
    ST_PARSE_DESC,
    ST_READ_PUB_SEED,
    ST_READ_ADDR,
    ST_READ_INPUT,
    ST_START_CORE,
    ST_WAIT_CORE,
    ST_WRITE_OUTPUT,
    ST_WRITE_STATUS
  } state_e;

  state_e state_q;

  logic [31:0] desc_word_q [0:DESC_HEADER_WORDS-1];

  logic [MEM_ADDR_WIDTH-1:0] descriptor_addr_q;
  logic [MEM_ADDR_WIDTH-1:0] pub_seed_ptr_q;
  logic [MEM_ADDR_WIDTH-1:0] addr_base_ptr_q;
  logic [MEM_ADDR_WIDTH-1:0] input_base_ptr_q;
  logic [MEM_ADDR_WIDTH-1:0] output_base_ptr_q;
  logic [MEM_ADDR_WIDTH-1:0] burst_base_addr;

  logic [7:0]  transfer_word_q;
  logic [7:0]  transfer_word_next;
  logic [7:0]  burst_total_words;
  logic [7:0]  input_total_words_q;
  logic [3:0]  input_words_per_lane_q;
  logic [1:0]  inblocks_q;
  logic [7:0]  op_type_q;
  logic [7:0]  start_step_q;
  logic [7:0]  num_steps_q;
  logic        inline_pub_seed_q;
  logic        busy_q;
  logic        done_q;
  logic        error_q;
  logic [3:0]  error_code_q;
  logic        start_accept;
  logic        mem_accept;
  logic        read_accept;
  logic        write_accept;
  logic        transfer_last;
  logic        op_type_known;
  logic        common_config_ok;
  logic        thash_config_ok;
  logic        wots_config_ok;
  logic        wots_chain_window_ok;
  logic        pointers_aligned;
  logic        descriptor_aligned;
  logic [31:0] final_status_word;
  logic [7:0]  desc_op_type;
  logic [7:0]  desc_start_step;
  logic [7:0]  desc_num_steps;
  logic [8:0]  desc_chain_end_step;

  logic [127:0] pub_seed_q;
  logic [255:0] addr_q [0:3];
  logic [255:0] input_q [0:3];

  logic         thash_core_start;
  logic         wots_core_start;
  logic         core_done;
  logic         core_error;
  logic         shared_thash_start;
  logic         shared_thash_done;
  logic         shared_thash_busy_q;
  logic [1:0]   shared_thash_inblocks;
  logic [127:0] shared_thash_pub_seed;
  logic [255:0] shared_thash_addr0;
  logic [255:0] shared_thash_addr1;
  logic [255:0] shared_thash_addr2;
  logic [255:0] shared_thash_addr3;
  logic [255:0] shared_thash_in0;
  logic [255:0] shared_thash_in1;
  logic [255:0] shared_thash_in2;
  logic [255:0] shared_thash_in3;
  logic         wots_core_done;
  logic         unused_wots_core_busy;
  logic         wots_core_error;
  logic         wots_req_valid;
  logic         wots_req_ready;
  logic [127:0] wots_req_pub_seed;
  logic [255:0] wots_req_addr0;
  logic [255:0] wots_req_addr1;
  logic [255:0] wots_req_addr2;
  logic [255:0] wots_req_addr3;
  logic [255:0] wots_req_in0;
  logic [255:0] wots_req_in1;
  logic [255:0] wots_req_in2;
  logic [255:0] wots_req_in3;
  logic         wots_rsp_valid;
  logic [127:0] thash_core_out0;
  logic [127:0] thash_core_out1;
  logic [127:0] thash_core_out2;
  logic [127:0] thash_core_out3;
  logic [127:0] wots_core_out0;
  logic [127:0] wots_core_out1;
  logic [127:0] wots_core_out2;
  logic [127:0] wots_core_out3;
  logic [127:0] core_out0;
  logic [127:0] core_out1;
  logic [127:0] core_out2;
  logic [127:0] core_out3;

  assign busy  = busy_q;
  assign done  = done_q;
  assign error = error_q;

  assign start_accept = start && !busy_q;
  assign mem_accept   = mem_valid && mem_ready;
  assign read_accept  = mem_accept && !mem_we;
  assign write_accept = mem_accept && mem_we;
  assign thash_core_start = (state_q == ST_START_CORE) &&
                            (op_type_q == OP_TYPE_THASHX4);
  assign wots_core_start = (state_q == ST_START_CORE) &&
                           (op_type_q == OP_TYPE_WOTS_CHAINX4);
  assign wots_req_ready = (op_type_q == OP_TYPE_WOTS_CHAINX4) &&
                          !shared_thash_busy_q;
  assign wots_rsp_valid = (op_type_q == OP_TYPE_WOTS_CHAINX4) &&
                          shared_thash_done;
  assign shared_thash_start = thash_core_start ||
                              (wots_req_valid && wots_req_ready);
  assign shared_thash_inblocks = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                                 2'd1 : inblocks_q;
  assign shared_thash_pub_seed = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                                 wots_req_pub_seed : pub_seed_q;
  assign shared_thash_addr0 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                              wots_req_addr0 : addr_q[0];
  assign shared_thash_addr1 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                              wots_req_addr1 : addr_q[1];
  assign shared_thash_addr2 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                              wots_req_addr2 : addr_q[2];
  assign shared_thash_addr3 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                              wots_req_addr3 : addr_q[3];
  assign shared_thash_in0 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                            wots_req_in0 : input_q[0];
  assign shared_thash_in1 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                            wots_req_in1 : input_q[1];
  assign shared_thash_in2 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                            wots_req_in2 : input_q[2];
  assign shared_thash_in3 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                            wots_req_in3 : input_q[3];

  assign transfer_word_next = transfer_word_q + 8'(MEM_WORDS_PER_CYCLE);
  assign transfer_last = (transfer_word_next >= burst_total_words);

  assign descriptor_aligned = ((descriptor_addr & MEM_ALIGN_MASK) == '0);

  assign desc_op_type =
      desc_word_q[DESC_CONFIG_WORD][CONFIG_OP_TYPE_LSB +: 8];
  assign desc_start_step =
      desc_word_q[DESC_CHAIN_CTRL_WORD][CHAIN_CTRL_START_STEP_LSB +: 8];
  assign desc_num_steps =
      desc_word_q[DESC_CHAIN_CTRL_WORD][CHAIN_CTRL_NUM_STEPS_LSB +: 8];
  assign desc_chain_end_step = {1'b0, desc_start_step} + {1'b0, desc_num_steps};

  assign op_type_known = (desc_op_type == OP_TYPE_THASHX4) ||
                         (desc_op_type == OP_TYPE_WOTS_CHAINX4);
  assign common_config_ok =
      (desc_word_q[DESC_CONFIG_WORD][7:4] == CONFIG_LANES_X4) &&
      (desc_word_q[DESC_CONFIG_WORD][15:8] == CONFIG_VARIANT_SHAKE_128F_SIMPLE);
  assign thash_config_ok =
      common_config_ok &&
      ((desc_word_q[DESC_CONFIG_WORD][1:0] == 2'd1) ||
       (desc_word_q[DESC_CONFIG_WORD][1:0] == 2'd2));
  assign wots_chain_window_ok =
      (desc_num_steps != 8'd0) &&
      (desc_num_steps <= 8'd15) &&
      (desc_start_step < 8'd16) &&
      (desc_chain_end_step <= 9'd16);
  assign wots_config_ok = common_config_ok && wots_chain_window_ok;

  assign pointers_aligned =
      ((desc_word_q[DESC_ADDR_BASE_WORD][MEM_ADDR_WIDTH-1:0] & MEM_ALIGN_MASK) == '0) &&
      ((desc_word_q[DESC_INPUT_BASE_WORD][MEM_ADDR_WIDTH-1:0] & MEM_ALIGN_MASK) == '0) &&
      ((desc_word_q[DESC_OUTPUT_BASE_WORD][MEM_ADDR_WIDTH-1:0] & MEM_ALIGN_MASK) == '0) &&
      (desc_word_q[DESC_FLAGS_STATUS_WORD][FLAG_INLINE_PUB_SEED_BIT] ||
       ((desc_word_q[DESC_PUB_SEED_PTR_WORD][MEM_ADDR_WIDTH-1:0] & MEM_ALIGN_MASK) == '0));

  always_comb begin
    burst_total_words = 8'd0;
    unique case (state_q)
      ST_READ_DESC: begin
        burst_total_words = 8'(DESC_HEADER_WORDS);
      end
      ST_READ_PUB_SEED: begin
        burst_total_words = 8'(PUB_SEED_WORDS);
      end
      ST_READ_ADDR: begin
        burst_total_words = 8'(ADDR_WORDS);
      end
      ST_READ_INPUT: begin
        burst_total_words = input_total_words_q;
      end
      ST_WRITE_OUTPUT: begin
        burst_total_words = 8'(OUTPUT_WORDS);
      end
      ST_WRITE_STATUS: begin
        burst_total_words = MEM_WORDS_PER_CYCLE[7:0];
      end
      default: begin
        burst_total_words = 8'd0;
      end
    endcase
  end

  always_comb begin
    burst_base_addr = '0;
    unique case (state_q)
      ST_READ_DESC: begin
        burst_base_addr = descriptor_addr_q;
      end
      ST_READ_PUB_SEED: begin
        if (inline_pub_seed_q) begin
          burst_base_addr = descriptor_addr_q + INLINE_SEED_DESC_OFFSET;
        end else begin
          burst_base_addr = pub_seed_ptr_q;
        end
      end
      ST_READ_ADDR: begin
        burst_base_addr = addr_base_ptr_q;
      end
      ST_READ_INPUT: begin
        burst_base_addr = input_base_ptr_q;
      end
      ST_WRITE_OUTPUT: begin
        burst_base_addr = output_base_ptr_q;
      end
      ST_WRITE_STATUS: begin
        burst_base_addr = descriptor_addr_q;
      end
      default: begin
        burst_base_addr = '0;
      end
    endcase
  end

  assign mem_valid = (state_q == ST_READ_DESC) || (state_q == ST_READ_PUB_SEED) ||
                     (state_q == ST_READ_ADDR) || (state_q == ST_READ_INPUT) ||
                     (state_q == ST_WRITE_OUTPUT) || (state_q == ST_WRITE_STATUS);
  assign mem_we = (state_q == ST_WRITE_OUTPUT) || (state_q == ST_WRITE_STATUS);
  assign mem_addr = burst_base_addr + MEM_ADDR_WIDTH'(transfer_word_q) * MEM_ADDR_WIDTH'(4);

  always_comb begin
    final_status_word = desc_word_q[DESC_FLAGS_STATUS_WORD];
    final_status_word[STATUS_DONE_BIT]  = 1'b1;
    final_status_word[STATUS_ERROR_BIT] = error_q;
    final_status_word[STATUS_ERROR_CODE_LSB +: 4] = error_code_q;
  end

  always_comb begin
    status = 32'd0;
    status[0] = busy_q;
    status[1] = done_q;
    status[2] = error_q;
    status[9:8] = inblocks_q;
    status[15:12] = op_type_q[3:0];
    status[19:16] = error_code_q;
  end

  always_comb begin
    mem_wdata = '0;
    for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
      int unsigned word_idx;
      int unsigned out_lane;
      int unsigned out_word;
      logic [31:0] packed_word;

      word_idx = int'(transfer_word_q) + lane;
      out_lane = word_idx / 4;
      out_word = word_idx % 4;
      packed_word = 32'd0;

      if (state_q == ST_WRITE_OUTPUT) begin
        unique case (out_lane)
          0: packed_word = core_out0[32 * out_word +: 32];
          1: packed_word = core_out1[32 * out_word +: 32];
          2: packed_word = core_out2[32 * out_word +: 32];
          3: packed_word = core_out3[32 * out_word +: 32];
          default: packed_word = 32'd0;
        endcase
      end else if (state_q == ST_WRITE_STATUS) begin
        if (word_idx == 0) begin
          packed_word = final_status_word;
        end else if (word_idx < DESC_HEADER_WORDS) begin
          packed_word = desc_word_q[word_idx];
        end else begin
          packed_word = 32'd0;
        end
      end

      mem_wdata[32 * lane +: 32] = packed_word;
    end
  end

  assign core_done = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                     wots_core_done : shared_thash_done;
  assign core_error = (op_type_q == OP_TYPE_WOTS_CHAINX4) && wots_core_error;
  assign core_out0 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                     wots_core_out0 : thash_core_out0;
  assign core_out1 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                     wots_core_out1 : thash_core_out1;
  assign core_out2 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                     wots_core_out2 : thash_core_out2;
  assign core_out3 = (op_type_q == OP_TYPE_WOTS_CHAINX4) ?
                     wots_core_out3 : thash_core_out3;

  spx_thashx4_core u_thashx4_core (
      .clk(clk),
      .rst_n(rst_n),
      .start(shared_thash_start),
      .inblocks(shared_thash_inblocks),
      .pub_seed(shared_thash_pub_seed),
      .addr0(shared_thash_addr0),
      .addr1(shared_thash_addr1),
      .addr2(shared_thash_addr2),
      .addr3(shared_thash_addr3),
      .in0(shared_thash_in0),
      .in1(shared_thash_in1),
      .in2(shared_thash_in2),
      .in3(shared_thash_in3),
      .done(shared_thash_done),
      .out0(thash_core_out0),
      .out1(thash_core_out1),
      .out2(thash_core_out2),
      .out3(thash_core_out3)
  );

  spx_wots_chainx4_core u_wots_chainx4_core (
      .clk(clk),
      .rst_n(rst_n),
      .start(wots_core_start),
      .pub_seed(pub_seed_q),
      .addr0(addr_q[0]),
      .addr1(addr_q[1]),
      .addr2(addr_q[2]),
      .addr3(addr_q[3]),
      .in0(input_q[0][127:0]),
      .in1(input_q[1][127:0]),
      .in2(input_q[2][127:0]),
      .in3(input_q[3][127:0]),
      .start_step(start_step_q),
      .num_steps(num_steps_q),
      .done(wots_core_done),
      .busy(unused_wots_core_busy),
      .error(wots_core_error),
      .out0(wots_core_out0),
      .out1(wots_core_out1),
      .out2(wots_core_out2),
      .out3(wots_core_out3),
      .wots_req_valid(wots_req_valid),
      .wots_req_ready(wots_req_ready),
      .wots_req_pub_seed(wots_req_pub_seed),
      .wots_req_addr0(wots_req_addr0),
      .wots_req_addr1(wots_req_addr1),
      .wots_req_addr2(wots_req_addr2),
      .wots_req_addr3(wots_req_addr3),
      .wots_req_in0(wots_req_in0),
      .wots_req_in1(wots_req_in1),
      .wots_req_in2(wots_req_in2),
      .wots_req_in3(wots_req_in3),
      .wots_rsp_valid(wots_rsp_valid),
      .wots_rsp_out0(thash_core_out0),
      .wots_rsp_out1(thash_core_out1),
      .wots_rsp_out2(thash_core_out2),
      .wots_rsp_out3(thash_core_out3)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q                <= ST_IDLE;
      descriptor_addr_q      <= '0;
      pub_seed_ptr_q         <= '0;
      addr_base_ptr_q        <= '0;
      input_base_ptr_q       <= '0;
      output_base_ptr_q      <= '0;
      transfer_word_q        <= 8'd0;
      input_total_words_q    <= 8'd0;
      input_words_per_lane_q <= 4'd0;
      inblocks_q             <= 2'd0;
      op_type_q              <= OP_TYPE_THASHX4;
      start_step_q           <= 8'd0;
      num_steps_q            <= 8'd0;
      inline_pub_seed_q      <= 1'b0;
      busy_q                 <= 1'b0;
      done_q                 <= 1'b0;
      error_q                <= 1'b0;
      error_code_q           <= ERR_NONE;
      shared_thash_busy_q    <= 1'b0;
      pub_seed_q             <= '0;
      addr_q[0]              <= '0;
      addr_q[1]              <= '0;
      addr_q[2]              <= '0;
      addr_q[3]              <= '0;
      input_q[0]             <= '0;
      input_q[1]             <= '0;
      input_q[2]             <= '0;
      input_q[3]             <= '0;
      perf_load_cycles       <= 32'd0;
      perf_core_cycles       <= 32'd0;
      perf_store_cycles      <= 32'd0;
      perf_total_cycles      <= 32'd0;
      for (int word = 0; word < DESC_HEADER_WORDS; word++) begin
        desc_word_q[word] <= 32'd0;
      end
    end else begin
      if (shared_thash_start) begin
        shared_thash_busy_q <= 1'b1;
      end else if (shared_thash_done) begin
        shared_thash_busy_q <= 1'b0;
      end

      if (busy_q) begin
        perf_total_cycles <= perf_total_cycles + 32'd1;
      end

      unique case (state_q)
        ST_IDLE: begin
          if (start_accept) begin
            descriptor_addr_q      <= descriptor_addr;
            transfer_word_q        <= 8'd0;
            done_q                 <= 1'b0;
            error_q                <= !descriptor_aligned;
            error_code_q           <= descriptor_aligned ? ERR_NONE : ERR_BAD_ALIGN;
            busy_q                 <= 1'b1;
            perf_load_cycles       <= 32'd0;
            perf_core_cycles       <= 32'd0;
            perf_store_cycles      <= 32'd0;
            perf_total_cycles      <= 32'd1;
            pub_seed_q             <= '0;
            addr_q[0]              <= '0;
            addr_q[1]              <= '0;
            addr_q[2]              <= '0;
            addr_q[3]              <= '0;
            input_q[0]             <= '0;
            input_q[1]             <= '0;
            input_q[2]             <= '0;
            input_q[3]             <= '0;
            op_type_q              <= OP_TYPE_THASHX4;
            start_step_q           <= 8'd0;
            num_steps_q            <= 8'd0;
            shared_thash_busy_q    <= 1'b0;
            if (descriptor_aligned) begin
              state_q <= ST_READ_DESC;
            end else begin
              state_q <= ST_WRITE_STATUS;
            end
          end
        end

        ST_READ_DESC: begin
          perf_load_cycles <= perf_load_cycles + 32'd1;
          if (read_accept) begin
            if (mem_error) begin
              error_q         <= 1'b1;
              error_code_q    <= ERR_MEM_READ;
              transfer_word_q <= 8'd0;
              state_q         <= ST_WRITE_STATUS;
            end else begin
              for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
                int unsigned word_idx;
                word_idx = int'(transfer_word_q) + lane;
                if (word_idx < DESC_HEADER_WORDS) begin
                  desc_word_q[word_idx] <= mem_rdata[32 * lane +: 32];
                end
              end

              if (transfer_last) begin
                transfer_word_q <= 8'd0;
                state_q <= ST_PARSE_DESC;
              end else begin
                transfer_word_q <= transfer_word_next;
              end
            end
          end
        end

        ST_PARSE_DESC: begin
          inline_pub_seed_q <= desc_word_q[DESC_FLAGS_STATUS_WORD][FLAG_INLINE_PUB_SEED_BIT];
          op_type_q <= desc_op_type;
          start_step_q <= desc_start_step;
          num_steps_q <= desc_num_steps;
          inblocks_q <= (desc_op_type == OP_TYPE_WOTS_CHAINX4) ?
                        2'd1 : desc_word_q[DESC_CONFIG_WORD][1:0];
          input_words_per_lane_q <=
              ((desc_op_type == OP_TYPE_THASHX4) &&
               (desc_word_q[DESC_CONFIG_WORD][1:0] == 2'd2)) ? 4'd8 : 4'd4;
          input_total_words_q <=
              (desc_op_type == OP_TYPE_WOTS_CHAINX4) ? 8'(WOTS_INPUT_WORDS) :
              ((desc_word_q[DESC_CONFIG_WORD][1:0] == 2'd2) ? 8'd32 : 8'd16);
          pub_seed_ptr_q <= desc_word_q[DESC_PUB_SEED_PTR_WORD][MEM_ADDR_WIDTH-1:0];
          addr_base_ptr_q <= desc_word_q[DESC_ADDR_BASE_WORD][MEM_ADDR_WIDTH-1:0];
          input_base_ptr_q <= desc_word_q[DESC_INPUT_BASE_WORD][MEM_ADDR_WIDTH-1:0];
          output_base_ptr_q <= desc_word_q[DESC_OUTPUT_BASE_WORD][MEM_ADDR_WIDTH-1:0];
          transfer_word_q <= 8'd0;

          if (!op_type_known) begin
            error_q      <= 1'b1;
            error_code_q <= ERR_BAD_OP_TYPE;
            state_q      <= ST_WRITE_STATUS;
          end else if (((desc_op_type == OP_TYPE_THASHX4) && !thash_config_ok) ||
                       ((desc_op_type == OP_TYPE_WOTS_CHAINX4) &&
                        !common_config_ok)) begin
            error_q      <= 1'b1;
            error_code_q <= ERR_BAD_CONFIG;
            state_q      <= ST_WRITE_STATUS;
          end else if ((desc_op_type == OP_TYPE_WOTS_CHAINX4) &&
                       !wots_config_ok) begin
            error_q      <= 1'b1;
            error_code_q <= ERR_BAD_CHAIN;
            state_q      <= ST_WRITE_STATUS;
          end else if (!pointers_aligned) begin
            error_q      <= 1'b1;
            error_code_q <= ERR_BAD_ALIGN;
            state_q      <= ST_WRITE_STATUS;
          end else begin
            error_q      <= 1'b0;
            error_code_q <= ERR_NONE;
            state_q      <= ST_READ_PUB_SEED;
          end
        end

        ST_READ_PUB_SEED: begin
          perf_load_cycles <= perf_load_cycles + 32'd1;
          if (read_accept) begin
            if (mem_error) begin
              error_q         <= 1'b1;
              error_code_q    <= ERR_MEM_READ;
              transfer_word_q <= 8'd0;
              state_q         <= ST_WRITE_STATUS;
            end else begin
              for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
                int unsigned word_idx;
                word_idx = int'(transfer_word_q) + lane;
                if (word_idx < PUB_SEED_WORDS) begin
                  pub_seed_q[32 * word_idx +: 32] <= mem_rdata[32 * lane +: 32];
                end
              end

              if (transfer_last) begin
                transfer_word_q <= 8'd0;
                state_q <= ST_READ_ADDR;
              end else begin
                transfer_word_q <= transfer_word_next;
              end
            end
          end
        end

        ST_READ_ADDR: begin
          perf_load_cycles <= perf_load_cycles + 32'd1;
          if (read_accept) begin
            if (mem_error) begin
              error_q         <= 1'b1;
              error_code_q    <= ERR_MEM_READ;
              transfer_word_q <= 8'd0;
              state_q         <= ST_WRITE_STATUS;
            end else begin
              for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
                int unsigned word_idx;
                logic [1:0] addr_lane;
                logic [2:0] addr_word;
                word_idx = int'(transfer_word_q) + lane;
                addr_lane = 2'(word_idx / 8);
                addr_word = 3'(word_idx % 8);
                if (word_idx < ADDR_WORDS) begin
                  addr_q[addr_lane][32 * addr_word +: 32] <= mem_rdata[32 * lane +: 32];
                end
              end

              if (transfer_last) begin
                transfer_word_q <= 8'd0;
                state_q <= ST_READ_INPUT;
              end else begin
                transfer_word_q <= transfer_word_next;
              end
            end
          end
        end

        ST_READ_INPUT: begin
          perf_load_cycles <= perf_load_cycles + 32'd1;
          if (read_accept) begin
            if (mem_error) begin
              error_q         <= 1'b1;
              error_code_q    <= ERR_MEM_READ;
              transfer_word_q <= 8'd0;
              state_q         <= ST_WRITE_STATUS;
            end else begin
              for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
                int unsigned word_idx;
                logic [1:0] input_lane;
                logic [2:0] input_word;
                word_idx = int'(transfer_word_q) + lane;
                input_lane = 2'(word_idx / int'(input_words_per_lane_q));
                input_word = 3'(word_idx % int'(input_words_per_lane_q));
                if (word_idx < input_total_words_q) begin
                  input_q[input_lane][32 * input_word +: 32] <= mem_rdata[32 * lane +: 32];
                end
              end

              if (transfer_last) begin
                transfer_word_q <= 8'd0;
                state_q <= ST_START_CORE;
              end else begin
                transfer_word_q <= transfer_word_next;
              end
            end
          end
        end

        ST_START_CORE: begin
          perf_core_cycles <= perf_core_cycles + 32'd1;
          state_q <= ST_WAIT_CORE;
        end

        ST_WAIT_CORE: begin
          if (core_done) begin
            transfer_word_q <= 8'd0;
            if (core_error) begin
              error_q      <= 1'b1;
              error_code_q <= ERR_BAD_CHAIN;
              state_q      <= ST_WRITE_STATUS;
            end else begin
              state_q <= ST_WRITE_OUTPUT;
            end
          end else begin
            perf_core_cycles <= perf_core_cycles + 32'd1;
          end
        end

        ST_WRITE_OUTPUT: begin
          perf_store_cycles <= perf_store_cycles + 32'd1;
          if (write_accept) begin
            if (mem_error) begin
              error_q         <= 1'b1;
              error_code_q    <= ERR_MEM_WRITE;
              transfer_word_q <= 8'd0;
              state_q <= ST_WRITE_STATUS;
            end else begin
              if (transfer_last) begin
                transfer_word_q <= 8'd0;
                state_q <= ST_WRITE_STATUS;
              end else begin
                transfer_word_q <= transfer_word_next;
              end
            end
          end
        end

        ST_WRITE_STATUS: begin
          perf_store_cycles <= perf_store_cycles + 32'd1;
          if (write_accept) begin
            if (mem_error) begin
              error_q      <= 1'b1;
              error_code_q <= ERR_MEM_WRITE;
            end
            busy_q <= 1'b0;
            done_q <= 1'b1;
            state_q <= ST_IDLE;
          end
        end

        default: begin
          state_q <= ST_IDLE;
          busy_q  <= 1'b0;
        end
      endcase
    end
  end
endmodule
