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

    output logic [31:0]                               perf_load_cycles,
    output logic [31:0]                               perf_core_cycles,
    output logic [31:0]                               perf_store_cycles,
    output logic [31:0]                               perf_total_cycles
);
  timeunit 1ns;
  timeprecision 1ps;

  localparam int MEM_BYTES_PER_CYCLE = 4 * MEM_WORDS_PER_CYCLE;
  localparam int DESC_HEADER_WORDS   = 8;
  localparam int PUB_SEED_WORDS      = 4;
  localparam int ADDR_WORDS          = 32;
  localparam int OUTPUT_WORDS        = 16;

  localparam int DESC_FLAGS_STATUS_WORD = 0;
  localparam int DESC_CONFIG_WORD       = 1;
  localparam int DESC_PUB_SEED_PTR_WORD = 2;
  localparam int DESC_ADDR_BASE_WORD    = 3;
  localparam int DESC_INPUT_BASE_WORD   = 4;
  localparam int DESC_OUTPUT_BASE_WORD  = 5;

  localparam int FLAG_INLINE_PUB_SEED_BIT = 0;
  localparam int STATUS_DONE_BIT          = 1;
  localparam int STATUS_ERROR_BIT         = 2;
  localparam int STATUS_ERROR_CODE_LSB    = 4;

  localparam logic [7:0] CONFIG_VARIANT_SHAKE_128F_SIMPLE = 8'h01;
  localparam logic [3:0] CONFIG_LANES_X4                  = 4'h4;

  localparam logic [3:0] ERR_NONE        = 4'h0;
  localparam logic [3:0] ERR_BAD_CONFIG  = 4'h1;
  localparam logic [3:0] ERR_BAD_ALIGN   = 4'h2;

  localparam logic [MEM_ADDR_WIDTH-1:0] MEM_ALIGN_MASK =
      MEM_ADDR_WIDTH'(MEM_BYTES_PER_CYCLE - 1);
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
  logic        config_ok;
  logic        pointers_aligned;
  logic        descriptor_aligned;
  logic [31:0] final_status_word;

  logic [127:0] pub_seed_q;
  logic [255:0] addr_q [0:3];
  logic [255:0] input_q [0:3];

  logic         core_start;
  logic         core_done;
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
  assign core_start   = (state_q == ST_START_CORE);

  assign transfer_word_next = transfer_word_q + 8'(MEM_WORDS_PER_CYCLE);
  assign transfer_last = (transfer_word_next >= burst_total_words);

  assign descriptor_aligned = ((descriptor_addr & MEM_ALIGN_MASK) == '0);

  assign config_ok =
      ((desc_word_q[DESC_CONFIG_WORD][1:0] == 2'd1) ||
       (desc_word_q[DESC_CONFIG_WORD][1:0] == 2'd2)) &&
      (desc_word_q[DESC_CONFIG_WORD][7:4] == CONFIG_LANES_X4) &&
      (desc_word_q[DESC_CONFIG_WORD][15:8] == CONFIG_VARIANT_SHAKE_128F_SIMPLE);

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

  spx_thashx4_core u_thashx4_core (
      .clk(clk),
      .rst_n(rst_n),
      .start(core_start),
      .inblocks(inblocks_q),
      .pub_seed(pub_seed_q),
      .addr0(addr_q[0]),
      .addr1(addr_q[1]),
      .addr2(addr_q[2]),
      .addr3(addr_q[3]),
      .in0(input_q[0]),
      .in1(input_q[1]),
      .in2(input_q[2]),
      .in3(input_q[3]),
      .done(core_done),
      .out0(core_out0),
      .out1(core_out1),
      .out2(core_out2),
      .out3(core_out3)
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
      inline_pub_seed_q      <= 1'b0;
      busy_q                 <= 1'b0;
      done_q                 <= 1'b0;
      error_q                <= 1'b0;
      error_code_q           <= ERR_NONE;
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
            if (descriptor_aligned) begin
              state_q <= ST_READ_DESC;
            end else begin
              state_q <= ST_IDLE;
              busy_q  <= 1'b0;
              done_q  <= 1'b1;
            end
          end
        end

        ST_READ_DESC: begin
          if (read_accept) begin
            perf_load_cycles <= perf_load_cycles + 32'd1;
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

        ST_PARSE_DESC: begin
          inline_pub_seed_q <= desc_word_q[DESC_FLAGS_STATUS_WORD][FLAG_INLINE_PUB_SEED_BIT];
          inblocks_q <= desc_word_q[DESC_CONFIG_WORD][1:0];
          input_words_per_lane_q <= (desc_word_q[DESC_CONFIG_WORD][1:0] == 2'd2) ? 4'd8 : 4'd4;
          input_total_words_q <= (desc_word_q[DESC_CONFIG_WORD][1:0] == 2'd2) ? 8'd32 : 8'd16;
          pub_seed_ptr_q <= desc_word_q[DESC_PUB_SEED_PTR_WORD][MEM_ADDR_WIDTH-1:0];
          addr_base_ptr_q <= desc_word_q[DESC_ADDR_BASE_WORD][MEM_ADDR_WIDTH-1:0];
          input_base_ptr_q <= desc_word_q[DESC_INPUT_BASE_WORD][MEM_ADDR_WIDTH-1:0];
          output_base_ptr_q <= desc_word_q[DESC_OUTPUT_BASE_WORD][MEM_ADDR_WIDTH-1:0];
          transfer_word_q <= 8'd0;

          if (!config_ok) begin
            error_q      <= 1'b1;
            error_code_q <= ERR_BAD_CONFIG;
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
          if (read_accept) begin
            perf_load_cycles <= perf_load_cycles + 32'd1;
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

        ST_READ_ADDR: begin
          if (read_accept) begin
            perf_load_cycles <= perf_load_cycles + 32'd1;
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

        ST_READ_INPUT: begin
          if (read_accept) begin
            perf_load_cycles <= perf_load_cycles + 32'd1;
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

        ST_START_CORE: begin
          perf_core_cycles <= perf_core_cycles + 32'd1;
          state_q <= ST_WAIT_CORE;
        end

        ST_WAIT_CORE: begin
          if (core_done) begin
            transfer_word_q <= 8'd0;
            state_q <= ST_WRITE_OUTPUT;
          end else begin
            perf_core_cycles <= perf_core_cycles + 32'd1;
          end
        end

        ST_WRITE_OUTPUT: begin
          if (write_accept) begin
            perf_store_cycles <= perf_store_cycles + 32'd1;
            if (transfer_last) begin
              transfer_word_q <= 8'd0;
              state_q <= ST_WRITE_STATUS;
            end else begin
              transfer_word_q <= transfer_word_next;
            end
          end
        end

        ST_WRITE_STATUS: begin
          if (write_accept) begin
            perf_store_cycles <= perf_store_cycles + 32'd1;
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
