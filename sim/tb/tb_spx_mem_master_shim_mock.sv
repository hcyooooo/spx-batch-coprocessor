module tb_spx_mem_master_shim_mock;
  timeunit 1ns;
  timeprecision 1ps;

  localparam int MEM_WORDS_PER_CYCLE = 4;
  localparam int MEM_ADDR_WIDTH      = 32;
  localparam int MEM_DATA_WIDTH      = 32 * MEM_WORDS_PER_CYCLE;
  localparam int MEM_WORDS           = 4096;
  localparam int DESC_BASE           = 32'h0000_0000;
  localparam int PUB_SEED_BASE       = 32'h0000_0100;
  localparam int ADDR_BASE           = 32'h0000_0200;
  localparam int INPUT_BASE          = 32'h0000_0500;
  localparam int OUTPUT_BASE         = 32'h0000_0900;

  localparam logic [7:0] INSTR_SPX_SET_DESC = 8'h10;
  localparam logic [7:0] INSTR_SPX_START    = 8'h11;
  localparam logic [7:0] INSTR_SPX_STATUS   = 8'h12;
  localparam logic [7:0] INSTR_SPX_CLEAR    = 8'h13;
  localparam logic [7:0] INSTR_SPX_WAIT     = 8'h14;

  localparam int DESC_FLAGS_STATUS_WORD = 0;
  localparam int DESC_CONFIG_WORD       = 1;
  localparam int DESC_PUB_SEED_PTR_WORD = 2;
  localparam int DESC_ADDR_BASE_WORD    = 3;
  localparam int DESC_INPUT_BASE_WORD   = 4;
  localparam int DESC_OUTPUT_BASE_WORD  = 5;
  localparam int DESC_LENGTH_WORD       = 6;
  localparam int DESC_INLINE_SEED_WORD  = 8;

  localparam int FLAG_INLINE_PUB_SEED_BIT = 0;
  localparam int STATUS_BUSY_BIT          = 0;
  localparam int STATUS_DONE_BIT          = 1;
  localparam int STATUS_ERROR_BIT         = 2;
  localparam int STATUS_ERROR_CODE_LSB    = 4;

  localparam logic [3:0] ERR_BAD_CONFIG = 4'h1;
  localparam logic [3:0] ERR_BAD_ALIGN  = 4'h2;
  localparam logic [3:0] ERR_MEM_READ   = 4'h3;
  localparam logic [3:0] ERR_MEM_WRITE  = 4'h4;

  localparam int BUS_ERR_NONE  = 0;
  localparam int BUS_ERR_READ  = 1;
  localparam int BUS_ERR_WRITE = 2;

  logic clk;
  logic rst_n;

  logic        instr_valid;
  logic        instr_ready;
  logic [7:0]  instr_op;
  logic [31:0] instr_rs1;
  logic        instr_resp_valid;
  logic [31:0] instr_resp_data;
  logic        instr_illegal;

  logic        desc_start;
  logic [31:0] desc_addr;
  logic        desc_busy;
  logic        desc_done;
  logic        desc_error;
  logic [31:0] desc_status;
  logic [3:0]  desc_error_code;

  logic                        mem_valid;
  logic                        mem_ready;
  logic                        mem_we;
  logic [MEM_ADDR_WIDTH-1:0]   mem_addr;
  logic [MEM_DATA_WIDTH-1:0]   mem_wdata;
  logic [MEM_DATA_WIDTH-1:0]   mem_rdata;
  logic                        mem_error;

  logic                        bus_req_valid;
  logic                        bus_req_ready;
  logic                        bus_req_we;
  logic [MEM_ADDR_WIDTH-1:0]   bus_req_addr;
  logic [MEM_DATA_WIDTH-1:0]   bus_req_wdata;
  logic                        bus_rsp_valid;
  logic [MEM_DATA_WIDTH-1:0]   bus_rsp_rdata;
  logic                        bus_rsp_error;

  logic [31:0] perf_load_cycles;
  logic [31:0] perf_core_cycles;
  logic [31:0] perf_store_cycles;
  logic [31:0] perf_total_cycles;

  logic [31:0] mem [0:MEM_WORDS-1];

  int unsigned cycle_q;
  int bus_read_latency_cycles;
  int bus_write_response_latency_cycles;
  int bus_request_wait_cycles;
  int bus_request_ready_pct;
  int bus_error_kind;
  int bus_error_read_index;
  int bus_error_write_index;
  logic [31:0] bus_model_seed;
  logic [31:0] bus_rng_q;

  logic bus_req_wait_pending_q;
  int   bus_req_wait_remaining_q;
  logic bus_rsp_pending_q;
  int   bus_rsp_wait_remaining_q;
  logic bus_rsp_we_q;
  logic [MEM_ADDR_WIDTH-1:0] bus_rsp_addr_q;
  logic [MEM_DATA_WIDTH-1:0] bus_rsp_wdata_q;
  logic [MEM_DATA_WIDTH-1:0] bus_rsp_rdata_q;
  logic bus_rsp_error_q;

  int bus_read_accept_count_q;
  int bus_write_accept_count_q;
  int bus_request_count_q;
  int bus_response_count_q;
  int shim_stall_cycles_q;

  logic bus_req_accept;
  logic bus_zero_response;
  logic bus_pending_response_due;

  spx_cvxif_desc_adapter u_cvxif_desc_adapter (
      .clk(clk),
      .rst_n(rst_n),
      .instr_valid(instr_valid),
      .instr_ready(instr_ready),
      .instr_op(instr_op),
      .instr_rs1(instr_rs1),
      .instr_resp_valid(instr_resp_valid),
      .instr_resp_data(instr_resp_data),
      .instr_illegal(instr_illegal),
      .desc_start(desc_start),
      .desc_addr(desc_addr),
      .desc_busy(desc_busy),
      .desc_done(desc_done),
      .desc_error(desc_error),
      .desc_error_code(desc_error_code)
  );

  spx_descriptor_adapter #(
      .MEM_WORDS_PER_CYCLE(MEM_WORDS_PER_CYCLE),
      .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH)
  ) u_descriptor_adapter (
      .clk(clk),
      .rst_n(rst_n),
      .start(desc_start),
      .descriptor_addr(desc_addr),
      .busy(desc_busy),
      .done(desc_done),
      .error(desc_error),
      .status(desc_status),
      .mem_valid(mem_valid),
      .mem_ready(mem_ready),
      .mem_we(mem_we),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_rdata(mem_rdata),
      .mem_error(mem_error),
      .perf_load_cycles(perf_load_cycles),
      .perf_core_cycles(perf_core_cycles),
      .perf_store_cycles(perf_store_cycles),
      .perf_total_cycles(perf_total_cycles)
  );

  spx_mem_master_shim_mock #(
      .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
      .MEM_DATA_WIDTH(MEM_DATA_WIDTH)
  ) u_mem_master_shim_mock (
      .clk(clk),
      .rst_n(rst_n),
      .mem_valid(mem_valid),
      .mem_ready(mem_ready),
      .mem_we(mem_we),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_rdata(mem_rdata),
      .mem_error(mem_error),
      .bus_req_valid(bus_req_valid),
      .bus_req_ready(bus_req_ready),
      .bus_req_we(bus_req_we),
      .bus_req_addr(bus_req_addr),
      .bus_req_wdata(bus_req_wdata),
      .bus_rsp_valid(bus_rsp_valid),
      .bus_rsp_rdata(bus_rsp_rdata),
      .bus_rsp_error(bus_rsp_error)
  );

  assign desc_error_code = desc_status[19:16];
  assign bus_req_accept  = bus_req_valid && bus_req_ready;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function automatic logic [31:0] xorshift32(input logic [31:0] value);
    logic [31:0] next_value;
    begin
      next_value = value;
      next_value ^= (next_value << 13);
      next_value ^= (next_value >> 17);
      next_value ^= (next_value << 5);
      xorshift32 = (next_value == 32'd0) ? 32'h1ace_b00c : next_value;
    end
  endfunction

  function automatic logic [MEM_DATA_WIDTH-1:0] read_bus_beat(
      input logic [MEM_ADDR_WIDTH-1:0] byte_addr
  );
    logic [MEM_DATA_WIDTH-1:0] data;
    int unsigned word_addr;
    begin
      data = '0;
      for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
        word_addr = int'(byte_addr[MEM_ADDR_WIDTH-1:2]) + lane;
        if (word_addr < MEM_WORDS) begin
          data[32 * lane +: 32] = mem[word_addr];
        end
      end
      read_bus_beat = data;
    end
  endfunction

  function automatic logic bus_error_for_request(input logic req_we);
    begin
      if (!req_we && (bus_error_kind == BUS_ERR_READ) &&
          (bus_read_accept_count_q == bus_error_read_index)) begin
        bus_error_for_request = 1'b1;
      end else if (req_we && (bus_error_kind == BUS_ERR_WRITE) &&
                   (bus_write_accept_count_q == bus_error_write_index)) begin
        bus_error_for_request = 1'b1;
      end else begin
        bus_error_for_request = 1'b0;
      end
    end
  endfunction

  always_comb begin
    bit wait_satisfied;
    bit random_satisfied;

    wait_satisfied = bus_req_wait_pending_q ?
                     (bus_req_wait_remaining_q == 0) :
                     (bus_request_wait_cycles == 0);

    if (bus_request_ready_pct >= 100) begin
      random_satisfied = 1'b1;
    end else if (bus_request_ready_pct <= 0) begin
      random_satisfied = 1'b0;
    end else begin
      random_satisfied = (int'(bus_rng_q % 100) < bus_request_ready_pct);
    end

    bus_req_ready = bus_req_valid && !bus_rsp_pending_q &&
                    wait_satisfied && random_satisfied;
  end

  always_comb begin
    int response_latency;

    response_latency = bus_req_we ? bus_write_response_latency_cycles :
                                    bus_read_latency_cycles;
    bus_zero_response = bus_req_accept && (response_latency == 0);
    bus_pending_response_due = bus_rsp_pending_q &&
                               (bus_rsp_wait_remaining_q == 0);
    bus_rsp_valid = bus_zero_response || bus_pending_response_due;

    if (bus_zero_response) begin
      bus_rsp_rdata = read_bus_beat(bus_req_addr);
      bus_rsp_error = bus_error_for_request(bus_req_we);
    end else begin
      bus_rsp_rdata = bus_rsp_rdata_q;
      bus_rsp_error = bus_rsp_error_q;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_q                    <= 0;
      bus_rng_q                  <= bus_model_seed;
      bus_req_wait_pending_q     <= 1'b0;
      bus_req_wait_remaining_q   <= 0;
      bus_rsp_pending_q          <= 1'b0;
      bus_rsp_wait_remaining_q   <= 0;
      bus_rsp_we_q               <= 1'b0;
      bus_rsp_addr_q             <= '0;
      bus_rsp_wdata_q            <= '0;
      bus_rsp_rdata_q            <= '0;
      bus_rsp_error_q            <= 1'b0;
      bus_read_accept_count_q    <= 0;
      bus_write_accept_count_q   <= 0;
      bus_request_count_q        <= 0;
      bus_response_count_q       <= 0;
      shim_stall_cycles_q        <= 0;
    end else begin
      int response_latency;
      logic accepted_error;
      logic [MEM_DATA_WIDTH-1:0] accepted_rdata;

      cycle_q   <= cycle_q + 1;
      bus_rng_q <= xorshift32(bus_rng_q);

      if (desc_busy && mem_valid && !mem_ready) begin
        shim_stall_cycles_q <= shim_stall_cycles_q + 1;
      end

      if (!bus_req_valid || bus_req_ready) begin
        bus_req_wait_pending_q   <= 1'b0;
        bus_req_wait_remaining_q <= 0;
      end else if (!bus_req_wait_pending_q) begin
        bus_req_wait_pending_q <= 1'b1;
        bus_req_wait_remaining_q <= (bus_request_wait_cycles > 0) ?
                                    (bus_request_wait_cycles - 1) : 0;
      end else if (bus_req_wait_remaining_q > 0) begin
        bus_req_wait_remaining_q <= bus_req_wait_remaining_q - 1;
      end

      if (bus_rsp_valid) begin
        bus_response_count_q <= bus_response_count_q + 1;
      end

      if (bus_rsp_pending_q) begin
        if (bus_rsp_wait_remaining_q > 0) begin
          bus_rsp_wait_remaining_q <= bus_rsp_wait_remaining_q - 1;
        end else begin
          if (bus_rsp_we_q && !bus_rsp_error_q) begin
            for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
              int unsigned word_addr;
              word_addr = int'(bus_rsp_addr_q[MEM_ADDR_WIDTH-1:2]) + lane;
              if (word_addr < MEM_WORDS) begin
                mem[word_addr] <= bus_rsp_wdata_q[32 * lane +: 32];
              end
            end
          end
          bus_rsp_pending_q        <= 1'b0;
          bus_rsp_wait_remaining_q <= 0;
        end
      end else if (bus_req_accept) begin
        response_latency = bus_req_we ? bus_write_response_latency_cycles :
                                      bus_read_latency_cycles;
        accepted_error = bus_error_for_request(bus_req_we);
        accepted_rdata = read_bus_beat(bus_req_addr);

        bus_request_count_q <= bus_request_count_q + 1;
        if (bus_req_we) begin
          bus_write_accept_count_q <= bus_write_accept_count_q + 1;
        end else begin
          bus_read_accept_count_q <= bus_read_accept_count_q + 1;
        end

        if (response_latency == 0) begin
          if (bus_req_we && !accepted_error) begin
            for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
              int unsigned word_addr;
              word_addr = int'(bus_req_addr[MEM_ADDR_WIDTH-1:2]) + lane;
              if (word_addr < MEM_WORDS) begin
                mem[word_addr] <= bus_req_wdata[32 * lane +: 32];
              end
            end
          end
        end else begin
          bus_rsp_pending_q        <= 1'b1;
          bus_rsp_wait_remaining_q <= response_latency - 1;
          bus_rsp_we_q             <= bus_req_we;
          bus_rsp_addr_q           <= bus_req_addr;
          bus_rsp_wdata_q          <= bus_req_wdata;
          bus_rsp_rdata_q          <= accepted_rdata;
          bus_rsp_error_q          <= accepted_error;
        end
      end
    end
  end

  task automatic configure_bus_model(
      input int read_latency_cycles,
      input int write_response_latency_cycles,
      input int request_wait_cycles,
      input int request_ready_pct,
      input int error_kind,
      input int error_read_index,
      input int error_write_index,
      input logic [31:0] seed
  );
    begin
      bus_read_latency_cycles           = read_latency_cycles;
      bus_write_response_latency_cycles = write_response_latency_cycles;
      bus_request_wait_cycles           = request_wait_cycles;
      bus_request_ready_pct             = request_ready_pct;
      bus_error_kind                    = error_kind;
      bus_error_read_index              = error_read_index;
      bus_error_write_index             = error_write_index;
      bus_model_seed                    = seed;
    end
  endtask

  task automatic clear_memory;
    begin
      for (int word = 0; word < MEM_WORDS; word++) begin
        mem[word] = 32'd0;
      end
    end
  endtask

  task automatic reset_dut;
    begin
      rst_n       = 1'b0;
      instr_valid = 1'b0;
      instr_op    = 8'd0;
      instr_rs1   = 32'd0;
      clear_memory();
      repeat (4) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic write_mem_word(input int byte_addr, input int word_offset,
                                input logic [31:0] data);
    int unsigned word_addr;
    begin
      word_addr = (byte_addr >> 2) + word_offset;
      if (word_addr >= MEM_WORDS) begin
        $fatal(1, "memory write out of range byte_addr=0x%08x word_offset=%0d",
               byte_addr, word_offset);
      end
      mem[word_addr] = data;
    end
  endtask

  function automatic logic [31:0] read_mem_word(input int byte_addr,
                                                input int word_offset);
    int unsigned word_addr;
    begin
      word_addr = (byte_addr >> 2) + word_offset;
      if (word_addr >= MEM_WORDS) begin
        $fatal(1, "memory read out of range byte_addr=0x%08x word_offset=%0d",
               byte_addr, word_offset);
      end
      read_mem_word = mem[word_addr];
    end
  endfunction

  task automatic issue_instr(input logic [7:0] op,
                             input logic [31:0] rs1,
                             output logic [31:0] resp_data,
                             output bit illegal);
    begin
      @(negedge clk);
      instr_valid = 1'b1;
      instr_op    = op;
      instr_rs1   = rs1;

      @(posedge clk);
      #1;
      if (!instr_ready) begin
        $fatal(1, "instruction was not ready op=0x%02x", op);
      end
      if (!instr_resp_valid) begin
        $fatal(1, "missing instruction response op=0x%02x", op);
      end

      resp_data  = instr_resp_data;
      illegal    = instr_illegal;
      instr_valid = 1'b0;
      instr_op    = 8'd0;
      instr_rs1   = 32'd0;
    end
  endtask

  task automatic expect_legal_instr(input logic [7:0] op,
                                    input logic [31:0] rs1,
                                    output logic [31:0] resp_data);
    bit illegal;
    begin
      issue_instr(op, rs1, resp_data, illegal);
      if (illegal) begin
        $fatal(1, "unexpected illegal instruction op=0x%02x", op);
      end
    end
  endtask

  task automatic setup_memory_case(
      input int expected_inblocks,
      input bit inline_pub_seed,
      input logic [127:0] pub_seed,
      input logic [255:0] addr0,
      input logic [255:0] addr1,
      input logic [255:0] addr2,
      input logic [255:0] addr3,
      input logic [255:0] in0,
      input logic [255:0] in1,
      input logic [255:0] in2,
      input logic [255:0] in3
  );
    int input_words_per_lane;
    begin
      clear_memory();
      input_words_per_lane = expected_inblocks * 4;

      write_mem_word(DESC_BASE, DESC_FLAGS_STATUS_WORD,
                     inline_pub_seed ? (32'(1) << FLAG_INLINE_PUB_SEED_BIT) : 32'd0);
      write_mem_word(DESC_BASE, DESC_CONFIG_WORD,
                     32'h0000_0100 | 32'h0000_0040 |
                     32'(expected_inblocks & 32'h0000_0003));
      write_mem_word(DESC_BASE, DESC_PUB_SEED_PTR_WORD, PUB_SEED_BASE[31:0]);
      write_mem_word(DESC_BASE, DESC_ADDR_BASE_WORD, ADDR_BASE[31:0]);
      write_mem_word(DESC_BASE, DESC_INPUT_BASE_WORD, INPUT_BASE[31:0]);
      write_mem_word(DESC_BASE, DESC_OUTPUT_BASE_WORD, OUTPUT_BASE[31:0]);
      write_mem_word(DESC_BASE, DESC_LENGTH_WORD, inline_pub_seed ? 32'd12 : 32'd8);

      for (int word = 0; word < 4; word++) begin
        if (inline_pub_seed) begin
          write_mem_word(DESC_BASE, DESC_INLINE_SEED_WORD + word,
                         pub_seed[32 * word +: 32]);
        end else begin
          write_mem_word(PUB_SEED_BASE, word, pub_seed[32 * word +: 32]);
        end
      end

      for (int word = 0; word < 8; word++) begin
        write_mem_word(ADDR_BASE, word, addr0[32 * word +: 32]);
        write_mem_word(ADDR_BASE, 8 + word, addr1[32 * word +: 32]);
        write_mem_word(ADDR_BASE, 16 + word, addr2[32 * word +: 32]);
        write_mem_word(ADDR_BASE, 24 + word, addr3[32 * word +: 32]);
      end

      for (int word = 0; word < input_words_per_lane; word++) begin
        write_mem_word(INPUT_BASE, word, in0[32 * word +: 32]);
        write_mem_word(INPUT_BASE, input_words_per_lane + word,
                       in1[32 * word +: 32]);
        write_mem_word(INPUT_BASE, 2 * input_words_per_lane + word,
                       in2[32 * word +: 32]);
        write_mem_word(INPUT_BASE, 3 * input_words_per_lane + word,
                       in3[32 * word +: 32]);
      end

      for (int word = 0; word < 16; word++) begin
        write_mem_word(OUTPUT_BASE, word, 32'hdeadc0de);
      end
    end
  endtask

  task automatic setup_zero_valid_case(input int inblocks);
    logic [127:0] pub_seed;
    logic [255:0] addr0;
    logic [255:0] addr1;
    logic [255:0] addr2;
    logic [255:0] addr3;
    logic [255:0] in0;
    logic [255:0] in1;
    logic [255:0] in2;
    logic [255:0] in3;
    begin
      pub_seed = 128'h0011_2233_4455_6677_8899_aabb_ccdd_eeff;
      addr0 = 256'h0102_0304_0506_0708_1112_1314_1516_1718_2122_2324_2526_2728_3132_3334_3536_3738;
      addr1 = 256'h4142_4344_4546_4748_5152_5354_5556_5758_6162_6364_6566_6768_7172_7374_7576_7778;
      addr2 = 256'h8182_8384_8586_8788_9192_9394_9596_9798_a1a2_a3a4_a5a6_a7a8_b1b2_b3b4_b5b6_b7b8;
      addr3 = 256'hc1c2_c3c4_c5c6_c7c8_d1d2_d3d4_d5d6_d7d8_e1e2_e3e4_e5e6_e7e8_f1f2_f3f4_f5f6_f7f8;
      in0 = 256'h0010_2030_4050_6070_8090_a0b0_c0d0_e0f0_1020_3040_5060_7080_90a0_b0c0_d0e0_f001;
      in1 = 256'h1121_3141_5161_7181_91a1_b1c1_d1e1_f102_2131_4151_6171_8191_a1b1_c1d1_e1f1_0212;
      in2 = 256'h2232_4252_6272_8292_a2b2_c2d2_e2f2_0313_3242_5262_7282_92a2_b2c2_d2e2_f203_1323;
      in3 = 256'h3343_5363_7383_93a3_b3c3_d3e3_f304_1424_4353_6373_8393_a3b3_c3d3_e3f3_0414_2434;
      setup_memory_case(inblocks, 1'b0, pub_seed, addr0, addr1, addr2, addr3,
                        in0, in1, in2, in3);
    end
  endtask

  task automatic read_output_words(
      output logic [127:0] got0,
      output logic [127:0] got1,
      output logic [127:0] got2,
      output logic [127:0] got3
  );
    begin
      got0 = '0;
      got1 = '0;
      got2 = '0;
      got3 = '0;
      for (int word = 0; word < 4; word++) begin
        got0[32 * word +: 32] = read_mem_word(OUTPUT_BASE, word);
        got1[32 * word +: 32] = read_mem_word(OUTPUT_BASE, 4 + word);
        got2[32 * word +: 32] = read_mem_word(OUTPUT_BASE, 8 + word);
        got3[32 * word +: 32] = read_mem_word(OUTPUT_BASE, 12 + word);
      end
    end
  endtask

  task automatic load_first_vector_case(
      input int inblocks,
      input string input_path0,
      input string input_path1,
      input string expected_path,
      output logic [127:0] pub_seed,
      output logic [255:0] addr0,
      output logic [255:0] addr1,
      output logic [255:0] addr2,
      output logic [255:0] addr3,
      output logic [255:0] in0,
      output logic [255:0] in1,
      output logic [255:0] in2,
      output logic [255:0] in3,
      output logic [127:0] exp0,
      output logic [127:0] exp1,
      output logic [127:0] exp2,
      output logic [127:0] exp3
  );
    string selected_input_path;
    int input_fd;
    int expected_fd;
    int rc;
    int num_cases;
    int expected_total;
    int exp_inblocks;
    bit found_expected;
    begin
      selected_input_path = (inblocks == 1) ? input_path0 : input_path1;
      input_fd = $fopen(selected_input_path, "r");
      if (input_fd == 0) begin
        $fatal(1, "failed to open %s", selected_input_path);
      end
      rc = $fscanf(input_fd, "%d", num_cases);
      if (rc != 1) begin
        $fatal(1, "failed to read case count from %s", selected_input_path);
      end
      rc = $fscanf(input_fd, "%h %h %h %h %h %h %h %h %h",
                   pub_seed, addr0, addr1, addr2, addr3,
                   in0, in1, in2, in3);
      if (rc != 9) begin
        $fatal(1, "failed to read first descriptor input from %s",
               selected_input_path);
      end
      $fclose(input_fd);

      expected_fd = $fopen(expected_path, "r");
      if (expected_fd == 0) begin
        $fatal(1, "failed to open %s", expected_path);
      end
      rc = $fscanf(expected_fd, "%d", expected_total);
      if (rc != 1) begin
        $fatal(1, "failed to read expected count from %s", expected_path);
      end

      found_expected = 1'b0;
      for (int index = 0; index < expected_total; index++) begin
        rc = $fscanf(expected_fd, "%d %h %h %h %h",
                     exp_inblocks, exp0, exp1, exp2, exp3);
        if (rc != 5) begin
          $fatal(1, "failed to read expected case %0d from %s",
                 index, expected_path);
        end
        if (!found_expected && (exp_inblocks == inblocks)) begin
          found_expected = 1'b1;
          break;
        end
      end
      $fclose(expected_fd);

      if (!found_expected) begin
        $fatal(1, "no expected case found for inblocks=%0d", inblocks);
      end
    end
  endtask

  task automatic run_cvxif_descriptor_case(
      input string mode_name,
      input int expected_inblocks,
      input logic [127:0] pub_seed,
      input logic [255:0] addr0,
      input logic [255:0] addr1,
      input logic [255:0] addr2,
      input logic [255:0] addr3,
      input logic [255:0] in0,
      input logic [255:0] in1,
      input logic [255:0] in2,
      input logic [255:0] in3,
      output logic [127:0] got0,
      output logic [127:0] got1,
      output logic [127:0] got2,
      output logic [127:0] got3,
      output int instruction_count,
      output int status_poll_count,
      output int descriptor_total_cycles,
      output int load_cycles,
      output int core_cycles,
      output int store_cycles,
      output int total_cycles,
      output int shim_stall_cycles,
      output int bus_request_count,
      output int bus_response_count
  );
    int timeout_polls;
    int unsigned start_cycle;
    int unsigned done_cycle;
    int start_shim_stall_cycles;
    int start_bus_request_count;
    int start_bus_response_count;
    logic [31:0] resp;
    logic [31:0] observed_status;
    logic [31:0] descriptor_status_word;
    begin
      setup_memory_case(expected_inblocks, 1'b0, pub_seed, addr0, addr1, addr2,
                        addr3, in0, in1, in2, in3);

      instruction_count = 0;
      status_poll_count = 0;
      observed_status = 32'd0;

      expect_legal_instr(INSTR_SPX_SET_DESC, DESC_BASE[31:0], resp);
      instruction_count++;
      expect_legal_instr(INSTR_SPX_START, 32'd0, resp);
      instruction_count++;
      if (!resp[STATUS_BUSY_BIT]) begin
        $fatal(1, "%s START response did not report busy inblocks=%0d",
               mode_name, expected_inblocks);
      end

      start_cycle = cycle_q;
      start_shim_stall_cycles = shim_stall_cycles_q;
      start_bus_request_count = bus_request_count_q;
      start_bus_response_count = bus_response_count_q;

      timeout_polls = 0;
      while (!observed_status[STATUS_DONE_BIT] && timeout_polls < 4000) begin
        expect_legal_instr(INSTR_SPX_STATUS, 32'd0, observed_status);
        instruction_count++;
        status_poll_count++;
        timeout_polls++;
      end
      done_cycle = cycle_q;

      if (!observed_status[STATUS_DONE_BIT]) begin
        $fatal(1, "%s timeout inblocks=%0d", mode_name, expected_inblocks);
      end
      if (observed_status[STATUS_ERROR_BIT]) begin
        $fatal(1, "%s unexpected error inblocks=%0d status=0x%08x",
               mode_name, expected_inblocks, observed_status);
      end
      if (desc_error || desc_status[STATUS_ERROR_BIT]) begin
        $fatal(1, "%s descriptor error inblocks=%0d desc_status=0x%08x",
               mode_name, expected_inblocks, desc_status);
      end

      descriptor_status_word = read_mem_word(DESC_BASE, DESC_FLAGS_STATUS_WORD);
      if (!descriptor_status_word[STATUS_DONE_BIT] ||
          descriptor_status_word[STATUS_ERROR_BIT]) begin
        $fatal(1, "%s descriptor status mismatch inblocks=%0d desc_status=0x%08x",
               mode_name, expected_inblocks, descriptor_status_word);
      end

      read_output_words(got0, got1, got2, got3);

      descriptor_total_cycles = int'(perf_total_cycles);
      load_cycles = int'(perf_load_cycles);
      core_cycles = int'(perf_core_cycles);
      store_cycles = int'(perf_store_cycles);
      total_cycles = int'(done_cycle - start_cycle + 1);
      shim_stall_cycles = shim_stall_cycles_q - start_shim_stall_cycles;
      bus_request_count = bus_request_count_q - start_bus_request_count;
      bus_response_count = bus_response_count_q - start_bus_response_count;

      if (bus_request_count != bus_response_count) begin
        $fatal(1, "%s bus count mismatch inblocks=%0d req=%0d rsp=%0d",
               mode_name, expected_inblocks, bus_request_count,
               bus_response_count);
      end

      expect_legal_instr(INSTR_SPX_WAIT, 32'd0, resp);
      if (!resp[STATUS_DONE_BIT] || resp[STATUS_ERROR_BIT]) begin
        $fatal(1, "%s WAIT helper status mismatch inblocks=%0d status=0x%08x",
               mode_name, expected_inblocks, resp);
      end

      expect_legal_instr(INSTR_SPX_CLEAR, 32'd0, resp);
      instruction_count++;
    end
  endtask

  task automatic compare_outputs(
      input string mode_name,
      input int inblocks,
      input logic [127:0] exp0,
      input logic [127:0] exp1,
      input logic [127:0] exp2,
      input logic [127:0] exp3,
      input logic [127:0] got0,
      input logic [127:0] got1,
      input logic [127:0] got2,
      input logic [127:0] got3,
      inout int errors
  );
    begin
      if (got0 !== exp0) begin
        $display("FAIL %s inblocks=%0d lane=0 expected=%h got=%h",
                 mode_name, inblocks, exp0, got0);
        errors++;
      end
      if (got1 !== exp1) begin
        $display("FAIL %s inblocks=%0d lane=1 expected=%h got=%h",
                 mode_name, inblocks, exp1, got1);
        errors++;
      end
      if (got2 !== exp2) begin
        $display("FAIL %s inblocks=%0d lane=2 expected=%h got=%h",
                 mode_name, inblocks, exp2, got2);
        errors++;
      end
      if (got3 !== exp3) begin
        $display("FAIL %s inblocks=%0d lane=3 expected=%h got=%h",
                 mode_name, inblocks, exp3, got3);
        errors++;
      end
    end
  endtask

  task automatic run_success_mode(
      input string mode_name,
      input int read_latency_cycles,
      input int write_response_latency_cycles,
      input int request_wait_cycles,
      input int request_ready_pct,
      input logic [31:0] seed,
      input string input_path0,
      input string input_path1,
      input string expected_path
  );
    int errors;
    int instruction_count;
    int status_poll_count;
    int descriptor_total_cycles;
    int load_cycles;
    int core_cycles;
    int store_cycles;
    int total_cycles;
    int shim_stall_cycles;
    int bus_request_count;
    int bus_response_count;
    real active_share;
    logic [127:0] pub_seed;
    logic [255:0] addr0;
    logic [255:0] addr1;
    logic [255:0] addr2;
    logic [255:0] addr3;
    logic [255:0] in0;
    logic [255:0] in1;
    logic [255:0] in2;
    logic [255:0] in3;
    logic [127:0] exp0;
    logic [127:0] exp1;
    logic [127:0] exp2;
    logic [127:0] exp3;
    logic [127:0] got0;
    logic [127:0] got1;
    logic [127:0] got2;
    logic [127:0] got3;
    begin
      errors = 0;
      for (int phase = 0; phase < 2; phase++) begin
        int inblocks;
        inblocks = phase + 1;
        configure_bus_model(read_latency_cycles, write_response_latency_cycles,
                            request_wait_cycles, request_ready_pct,
                            BUS_ERR_NONE, 0, 0, seed + 32'(phase));
        reset_dut();
        load_first_vector_case(inblocks, input_path0, input_path1, expected_path,
                               pub_seed, addr0, addr1, addr2, addr3,
                               in0, in1, in2, in3,
                               exp0, exp1, exp2, exp3);
        run_cvxif_descriptor_case(mode_name, inblocks,
                                  pub_seed, addr0, addr1, addr2, addr3,
                                  in0, in1, in2, in3,
                                  got0, got1, got2, got3,
                                  instruction_count, status_poll_count,
                                  descriptor_total_cycles, load_cycles,
                                  core_cycles, store_cycles, total_cycles,
                                  shim_stall_cycles, bus_request_count,
                                  bus_response_count);
        compare_outputs(mode_name, inblocks, exp0, exp1, exp2, exp3,
                        got0, got1, got2, got3, errors);

        active_share = (100.0 * core_cycles) / total_cycles;
        $display("PHASE35C_SHIM_PERF mode=%s inblocks=%0d total_cycles=%0d descriptor_adapter_cycles=%0d memory_load_cycles=%0d core_cycles=%0d memory_store_cycles=%0d shim_stall_cycles=%0d bus_request_count=%0d bus_response_count=%0d active_share=%0.1f%% status_polls=%0d instruction_count=%0d",
                 mode_name, inblocks, total_cycles, descriptor_total_cycles,
                 load_cycles, core_cycles, store_cycles, shim_stall_cycles,
                 bus_request_count, bus_response_count, active_share,
                 status_poll_count, instruction_count);
      end

      if (errors != 0) begin
        $fatal(1, "FAIL %s mismatches=%0d", mode_name, errors);
      end
    end
  endtask

  task automatic expect_cvxif_descriptor_error(
      input string test_name,
      input logic [31:0] descriptor_start_addr,
      input logic [31:0] descriptor_status_addr,
      input logic [3:0] expected_error_code
  );
    int timeout_polls;
    int instruction_count;
    int status_poll_count;
    logic [31:0] resp;
    logic [31:0] observed_status;
    logic [31:0] descriptor_status_word;
    begin
      instruction_count = 0;
      status_poll_count = 0;
      observed_status = 32'd0;

      expect_legal_instr(INSTR_SPX_SET_DESC, descriptor_start_addr, resp);
      instruction_count++;
      expect_legal_instr(INSTR_SPX_START, 32'd0, resp);
      instruction_count++;
      if (!resp[STATUS_BUSY_BIT]) begin
        $fatal(1, "%s START response did not report busy", test_name);
      end

      timeout_polls = 0;
      while (!observed_status[STATUS_DONE_BIT] && timeout_polls < 4000) begin
        expect_legal_instr(INSTR_SPX_STATUS, 32'd0, observed_status);
        instruction_count++;
        status_poll_count++;
        timeout_polls++;
      end

      if (!observed_status[STATUS_DONE_BIT]) begin
        $fatal(1, "%s timed out", test_name);
      end
      if (!observed_status[STATUS_ERROR_BIT]) begin
        $fatal(1, "%s completed without error status=0x%08x",
               test_name, observed_status);
      end
      if (observed_status[STATUS_ERROR_CODE_LSB +: 4] != expected_error_code) begin
        $fatal(1, "%s status error_code mismatch expected=0x%0x got=0x%0x status=0x%08x",
               test_name, expected_error_code,
               observed_status[STATUS_ERROR_CODE_LSB +: 4], observed_status);
      end

      descriptor_status_word = read_mem_word(descriptor_status_addr, 0);
      if (!descriptor_status_word[STATUS_DONE_BIT] ||
          !descriptor_status_word[STATUS_ERROR_BIT] ||
          (descriptor_status_word[STATUS_ERROR_CODE_LSB +: 4] != expected_error_code)) begin
        $fatal(1, "%s descriptor status mismatch expected_code=0x%0x desc_status=0x%08x",
               test_name, expected_error_code, descriptor_status_word);
      end

      expect_legal_instr(INSTR_SPX_WAIT, 32'd0, resp);
      if (!resp[STATUS_DONE_BIT] || !resp[STATUS_ERROR_BIT] ||
          (resp[STATUS_ERROR_CODE_LSB +: 4] != expected_error_code)) begin
        $fatal(1, "%s WAIT helper status mismatch status=0x%08x",
               test_name, resp);
      end

      expect_legal_instr(INSTR_SPX_CLEAR, 32'd0, resp);
      instruction_count++;
      $display("PHASE35C_SHIM_ERROR_PASS %s error_code=0x%0x status_polls=%0d instruction_count=%0d desc_status=0x%08x bus_req=%0d bus_rsp=%0d shim_stalls=%0d",
               test_name, expected_error_code, status_poll_count,
               instruction_count, descriptor_status_word,
               bus_request_count_q, bus_response_count_q, shim_stall_cycles_q);
    end
  endtask

  task automatic run_error_suite;
    begin
      configure_bus_model(0, 0, 0, 100, BUS_ERR_READ, 0, 0, 32'h35c0_2000);
      reset_dut();
      setup_zero_valid_case(1);
      expect_cvxif_descriptor_error("read_bus_error", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_MEM_READ);

      configure_bus_model(0, 0, 0, 100, BUS_ERR_WRITE, 0, 0, 32'h35c0_2001);
      reset_dut();
      setup_zero_valid_case(1);
      expect_cvxif_descriptor_error("write_bus_error", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_MEM_WRITE);

      configure_bus_model(0, 0, 0, 100, BUS_ERR_NONE, 0, 0, 32'h35c0_2002);
      reset_dut();
      setup_zero_valid_case(1);
      expect_cvxif_descriptor_error("descriptor_addr_unaligned",
                                    DESC_BASE[31:0] + 32'd4,
                                    DESC_BASE[31:0] + 32'd4,
                                    ERR_BAD_ALIGN);

      configure_bus_model(1, 1, 1, 100, BUS_ERR_NONE, 0, 0, 32'h35c0_2003);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_PUB_SEED_PTR_WORD, PUB_SEED_BASE[31:0] + 32'd4);
      expect_cvxif_descriptor_error("pub_seed_ptr_unaligned", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_BAD_ALIGN);

      configure_bus_model(2, 1, 0, 100, BUS_ERR_NONE, 0, 0, 32'h35c0_2004);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_CONFIG_WORD, 32'h0000_0140);
      expect_cvxif_descriptor_error("bad_descriptor_config", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_BAD_CONFIG);
    end
  endtask

  initial begin
    string input_path [0:1];
    string expected_path;

    if (!$value$plusargs("VECTORS_IB1=%s", input_path[0])) begin
      input_path[0] = "sim/vectors/thashx4_inblocks1.hex";
    end
    if (!$value$plusargs("VECTORS_IB2=%s", input_path[1])) begin
      input_path[1] = "sim/vectors/thashx4_inblocks2.hex";
    end
    if (!$value$plusargs("EXPECTED=%s", expected_path)) begin
      expected_path = "sim/vectors/thashx4_expected.hex";
    end

    configure_bus_model(0, 0, 0, 100, BUS_ERR_NONE, 0, 0, 32'h35c0_0001);
    reset_dut();

    $display("PHASE35C_SHIM_PERF_TABLE");
    $display("mode inblocks total_cycles descriptor_adapter_cycles memory_load_cycles core_cycles memory_store_cycles shim_stall_cycles bus_request_count bus_response_count active_share status_polls instruction_count");

    run_success_mode("zero_latency", 0, 0, 0, 100, 32'h35c0_1000,
                     input_path[0], input_path[1], expected_path);
    run_success_mode("read_latency_1", 1, 0, 0, 100, 32'h35c0_1001,
                     input_path[0], input_path[1], expected_path);
    run_success_mode("read_latency_2", 2, 0, 0, 100, 32'h35c0_1002,
                     input_path[0], input_path[1], expected_path);
    run_success_mode("read_latency_4", 4, 0, 0, 100, 32'h35c0_1004,
                     input_path[0], input_path[1], expected_path);
    run_success_mode("write_latency_1", 0, 1, 0, 100, 32'h35c0_1101,
                     input_path[0], input_path[1], expected_path);
    run_success_mode("write_latency_2", 0, 2, 0, 100, 32'h35c0_1102,
                     input_path[0], input_path[1], expected_path);
    run_success_mode("write_latency_4", 0, 4, 0, 100, 32'h35c0_1104,
                     input_path[0], input_path[1], expected_path);
    run_success_mode("request_backpressure_2", 0, 0, 2, 100, 32'h35c0_1202,
                     input_path[0], input_path[1], expected_path);
    run_success_mode("random_req_ready_50", 0, 0, 0, 50, 32'h35c0_1250,
                     input_path[0], input_path[1], expected_path);
    run_success_mode("split_rsp_delay", 2, 4, 0, 100, 32'h35c0_1240,
                     input_path[0], input_path[1], expected_path);

    run_error_suite();

    $display("PASS spx_mem_master_shim_mock standalone memory-master tests");
    $finish;
  end
endmodule
