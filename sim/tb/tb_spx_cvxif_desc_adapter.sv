module tb_spx_cvxif_desc_adapter;
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

  localparam logic [3:0] ERR_NONE       = 4'h0;
  localparam logic [3:0] ERR_BAD_CONFIG = 4'h1;
  localparam logic [3:0] ERR_BAD_ALIGN  = 4'h2;
  localparam logic [3:0] ERR_MEM_READ   = 4'h3;
  localparam logic [3:0] ERR_MEM_WRITE  = 4'h4;

  localparam int MEM_ERR_NONE       = 0;
  localparam int MEM_ERR_READ_BUS   = 1;
  localparam int MEM_ERR_READ_DATA  = 2;
  localparam int MEM_ERR_WRITE_RESP = 3;

  localparam int METRIC_INSTR_COUNT       = 0;
  localparam int METRIC_STATUS_POLLS      = 1;
  localparam int METRIC_DESC_TOTAL_CYCLES = 2;
  localparam int METRIC_LOAD_CYCLES       = 3;
  localparam int METRIC_CORE_CYCLES       = 4;
  localparam int METRIC_STORE_CYCLES      = 5;
  localparam int METRIC_TOTAL_CYCLES      = 6;
  localparam int METRIC_COUNT             = 7;

  logic clk;
  logic rst_n;

  logic        instr_valid;
  logic        instr_ready;
  logic [7:0]  instr_op;
  logic [31:0] instr_rs1;
  logic        instr_resp_valid;
  logic [31:0] instr_resp_data;
  logic        instr_illegal;

  logic desc_start;
  logic [31:0] desc_addr;
  logic desc_busy;
  logic desc_done;
  logic desc_error;
  logic [31:0] desc_status;
  logic [3:0] desc_error_code;

  logic mem_valid;
  logic mem_ready;
  logic mem_we;
  logic [MEM_ADDR_WIDTH-1:0] mem_addr;
  logic [MEM_DATA_WIDTH-1:0] mem_wdata;
  logic [MEM_DATA_WIDTH-1:0] mem_rdata;
  logic mem_error;

  logic [31:0] perf_load_cycles;
  logic [31:0] perf_core_cycles;
  logic [31:0] perf_store_cycles;
  logic [31:0] perf_total_cycles;

  logic [31:0] mem [0:MEM_WORDS-1];

  int unsigned cycle_q;
  int metric_min [0:1][0:METRIC_COUNT-1];
  int metric_max [0:1][0:METRIC_COUNT-1];
  longint metric_sum [0:1][0:METRIC_COUNT-1];
  int metric_cases [0:1];

  int mem_model_read_wait_cycles = 0;
  int mem_model_write_wait_cycles = 0;
  int mem_model_random_ready_pct = 100;
  int mem_model_error_kind = MEM_ERR_NONE;
  int mem_model_error_read_index = 0;
  int mem_model_error_write_index = 0;
  logic [31:0] mem_model_seed = 32'h35a0_0001;
  logic [31:0] mem_rng_q;
  logic mem_pending_q;
  int mem_wait_remaining_q;
  int mem_read_accept_count_q;
  int mem_write_accept_count_q;

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

  assign desc_error_code = desc_status[19:16];

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

  task automatic configure_memory_model(
      input int read_wait_cycles,
      input int write_wait_cycles,
      input int random_ready_pct,
      input int error_kind,
      input int error_read_index,
      input int error_write_index,
      input logic [31:0] seed
  );
    begin
      mem_model_read_wait_cycles  = read_wait_cycles;
      mem_model_write_wait_cycles = write_wait_cycles;
      mem_model_random_ready_pct  = random_ready_pct;
      mem_model_error_kind        = error_kind;
      mem_model_error_read_index  = error_read_index;
      mem_model_error_write_index = error_write_index;
      mem_model_seed              = seed;
    end
  endtask

  always_comb begin
    int wait_cfg;
    bit wait_satisfied;
    bit random_satisfied;

    wait_cfg = mem_we ? mem_model_write_wait_cycles : mem_model_read_wait_cycles;
    wait_satisfied = mem_pending_q ? (mem_wait_remaining_q == 0) : (wait_cfg == 0);

    if (mem_model_random_ready_pct >= 100) begin
      random_satisfied = 1'b1;
    end else if (mem_model_random_ready_pct <= 0) begin
      random_satisfied = 1'b0;
    end else begin
      random_satisfied = (int'(mem_rng_q % 100) < mem_model_random_ready_pct);
    end

    mem_ready = mem_valid && wait_satisfied && random_satisfied;
  end

  always_comb begin
    mem_error = 1'b0;
    if (mem_valid && mem_ready) begin
      if (!mem_we &&
          ((mem_model_error_kind == MEM_ERR_READ_BUS) ||
           (mem_model_error_kind == MEM_ERR_READ_DATA)) &&
          (mem_read_accept_count_q == mem_model_error_read_index)) begin
        mem_error = 1'b1;
      end else if (mem_we &&
                   (mem_model_error_kind == MEM_ERR_WRITE_RESP) &&
                   (mem_write_accept_count_q == mem_model_error_write_index)) begin
        mem_error = 1'b1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_rng_q                <= mem_model_seed;
      mem_pending_q            <= 1'b0;
      mem_wait_remaining_q     <= 0;
      mem_read_accept_count_q  <= 0;
      mem_write_accept_count_q <= 0;
    end else begin
      int wait_cfg;
      wait_cfg = mem_we ? mem_model_write_wait_cycles : mem_model_read_wait_cycles;
      mem_rng_q <= xorshift32(mem_rng_q);

      if (!mem_valid) begin
        mem_pending_q        <= 1'b0;
        mem_wait_remaining_q <= 0;
      end else if (mem_ready) begin
        mem_pending_q        <= 1'b0;
        mem_wait_remaining_q <= 0;
        if (mem_we) begin
          mem_write_accept_count_q <= mem_write_accept_count_q + 1;
        end else begin
          mem_read_accept_count_q <= mem_read_accept_count_q + 1;
        end
      end else if (!mem_pending_q) begin
        mem_pending_q <= 1'b1;
        mem_wait_remaining_q <= (wait_cfg > 0) ? (wait_cfg - 1) : 0;
      end else if (mem_wait_remaining_q > 0) begin
        mem_wait_remaining_q <= mem_wait_remaining_q - 1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_q <= 0;
    end else begin
      cycle_q <= cycle_q + 1;
    end
  end

  always_comb begin
    mem_rdata = '0;
    for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
      int unsigned word_addr;
      logic [31:0] read_word;
      word_addr = int'(mem_addr[MEM_ADDR_WIDTH-1:2]) + lane;
      read_word = 32'd0;
      if (mem_valid && !mem_we && (word_addr < MEM_WORDS)) begin
        read_word = mem[word_addr];
        if ((mem_model_error_kind == MEM_ERR_READ_DATA) &&
            (mem_read_accept_count_q == mem_model_error_read_index) &&
            (lane == 0)) begin
          read_word ^= 32'hbad0_0bad;
        end
        mem_rdata[32 * lane +: 32] = read_word;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (mem_valid && mem_ready && mem_we && !mem_error) begin
      for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
        int unsigned word_addr;
        word_addr = int'(mem_addr[MEM_ADDR_WIDTH-1:2]) + lane;
        if (word_addr < MEM_WORDS) begin
          mem[word_addr] <= mem_wdata[32 * lane +: 32];
        end
      end
    end
  end

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

      resp_data = instr_resp_data;
      illegal   = instr_illegal;
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

  task automatic run_cvxif_descriptor_case(
      input int case_id,
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
      output int total_cycles
  );
    int timeout_polls;
    int unsigned start_cycle;
    int unsigned done_cycle;
    logic [31:0] resp;
    logic [31:0] observed_status;
    logic [31:0] descriptor_status_word;
    begin
      setup_memory_case(expected_inblocks, inline_pub_seed,
                        pub_seed, addr0, addr1, addr2, addr3,
                        in0, in1, in2, in3);

      instruction_count = 0;
      status_poll_count = 0;
      observed_status = 32'd0;

      expect_legal_instr(INSTR_SPX_SET_DESC, DESC_BASE[31:0], resp);
      instruction_count++;
      expect_legal_instr(INSTR_SPX_START, 32'd0, resp);
      instruction_count++;
      if (!resp[STATUS_BUSY_BIT]) begin
        $fatal(1, "START response did not report busy inblocks=%0d case=%0d",
               expected_inblocks, case_id);
      end
      start_cycle = cycle_q;

      timeout_polls = 0;
      while (!observed_status[STATUS_DONE_BIT] && timeout_polls < 2000) begin
        expect_legal_instr(INSTR_SPX_STATUS, 32'd0, observed_status);
        instruction_count++;
        status_poll_count++;
        timeout_polls++;
      end
      done_cycle = cycle_q;

      if (!observed_status[STATUS_DONE_BIT]) begin
        $fatal(1, "CV-X-IF descriptor adapter timeout inblocks=%0d case=%0d",
               expected_inblocks, case_id);
      end
      if (observed_status[STATUS_ERROR_BIT]) begin
        $fatal(1, "CV-X-IF status error inblocks=%0d case=%0d status=0x%08x",
               expected_inblocks, case_id, observed_status);
      end
      if (desc_error || desc_status[STATUS_ERROR_BIT]) begin
        $fatal(1, "descriptor adapter error inblocks=%0d case=%0d desc_status=0x%08x",
               expected_inblocks, case_id, desc_status);
      end

      descriptor_status_word = read_mem_word(DESC_BASE, DESC_FLAGS_STATUS_WORD);
      if (!descriptor_status_word[STATUS_DONE_BIT] ||
          descriptor_status_word[STATUS_ERROR_BIT]) begin
        $fatal(1, "descriptor status mismatch inblocks=%0d case=%0d desc_status=0x%08x",
               expected_inblocks, case_id, descriptor_status_word);
      end

      read_output_words(got0, got1, got2, got3);

      expect_legal_instr(INSTR_SPX_WAIT, 32'd0, resp);
      if (!resp[STATUS_DONE_BIT] || resp[STATUS_ERROR_BIT]) begin
        $fatal(1, "WAIT helper status mismatch inblocks=%0d case=%0d status=0x%08x",
               expected_inblocks, case_id, resp);
      end

      expect_legal_instr(INSTR_SPX_CLEAR, 32'd0, resp);
      instruction_count++;

      if (case_id == 0) begin
        expect_legal_instr(INSTR_SPX_STATUS, 32'd0, resp);
        if (resp[STATUS_DONE_BIT] || resp[STATUS_ERROR_BIT]) begin
          $fatal(1, "CLEAR did not drop sticky status inblocks=%0d status=0x%08x",
                 expected_inblocks, resp);
        end
      end

      descriptor_total_cycles = int'(perf_total_cycles);
      load_cycles = int'(perf_load_cycles);
      core_cycles = int'(perf_core_cycles);
      store_cycles = int'(perf_store_cycles);
      total_cycles = int'(done_cycle - start_cycle + 1);
    end
  endtask

  task automatic init_metric_stats;
    begin
      for (int phase = 0; phase < 2; phase++) begin
        metric_cases[phase] = 0;
        for (int metric = 0; metric < METRIC_COUNT; metric++) begin
          metric_min[phase][metric] = 32'h7fffffff;
          metric_max[phase][metric] = 0;
          metric_sum[phase][metric] = 0;
        end
      end
    end
  endtask

  task automatic update_metric(input int phase, input int metric, input int value);
    begin
      if (value < metric_min[phase][metric]) begin
        metric_min[phase][metric] = value;
      end
      if (value > metric_max[phase][metric]) begin
        metric_max[phase][metric] = value;
      end
      metric_sum[phase][metric] += longint'(value);
    end
  endtask

  task automatic update_metrics(
      input int phase,
      input int instruction_count,
      input int status_poll_count,
      input int descriptor_total_cycles,
      input int load_cycles,
      input int core_cycles,
      input int store_cycles,
      input int total_cycles
  );
    begin
      metric_cases[phase]++;
      update_metric(phase, METRIC_INSTR_COUNT, instruction_count);
      update_metric(phase, METRIC_STATUS_POLLS, status_poll_count);
      update_metric(phase, METRIC_DESC_TOTAL_CYCLES, descriptor_total_cycles);
      update_metric(phase, METRIC_LOAD_CYCLES, load_cycles);
      update_metric(phase, METRIC_CORE_CYCLES, core_cycles);
      update_metric(phase, METRIC_STORE_CYCLES, store_cycles);
      update_metric(phase, METRIC_TOTAL_CYCLES, total_cycles);
    end
  endtask

  task automatic print_metric(input int phase, input int metric, input string name);
    real avg;
    begin
      avg = metric_sum[phase][metric];
      avg = avg / metric_cases[phase];
      if (metric_min[phase][metric] == metric_max[phase][metric]) begin
        $display("  %s = %0d", name, metric_min[phase][metric]);
      end else begin
        $display("  %s min=%0d max=%0d avg=%0.2f",
                 name, metric_min[phase][metric], metric_max[phase][metric], avg);
      end
    end
  endtask

  task automatic print_stats(input int phase, input int inblocks);
    real active_share;
    begin
      active_share = (100.0 * metric_min[phase][METRIC_CORE_CYCLES]) /
                     metric_min[phase][METRIC_TOTAL_CYCLES];
      $display("CVXIF_DESC_ADAPTER_STATS width=4words_per_cycle inblocks=%0d:", inblocks);
      print_metric(phase, METRIC_INSTR_COUNT, "instruction_count");
      print_metric(phase, METRIC_STATUS_POLLS, "status_poll_count");
      print_metric(phase, METRIC_DESC_TOTAL_CYCLES, "descriptor_adapter_total_cycles");
      print_metric(phase, METRIC_LOAD_CYCLES, "memory_load_cycles");
      print_metric(phase, METRIC_CORE_CYCLES, "core_cycles");
      print_metric(phase, METRIC_STORE_CYCLES, "memory_store_cycles");
      print_metric(phase, METRIC_TOTAL_CYCLES, "total_cycles");
      $display("  active_share = %0.1f%%", active_share);
    end
  endtask

  task automatic print_comparison_table;
    real active_share;
    begin
      $display("CVXIF_DESC_ADAPTER_COMPARISON width=4words_per_cycle:");
      $display("inblocks  instr_count  status_polls  desc_total  load_cycles  core_cycles  store_cycles  total_cycles  active_share");
      $display("-----------------------------------------------------------------------------------------------------------------");
      for (int phase = 0; phase < 2; phase++) begin
        active_share = (100.0 * metric_min[phase][METRIC_CORE_CYCLES]) /
                       metric_min[phase][METRIC_TOTAL_CYCLES];
        $display("%8d %12d %13d %11d %12d %12d %13d %13d %11.1f%%",
                 phase + 1,
                 metric_min[phase][METRIC_INSTR_COUNT],
                 metric_min[phase][METRIC_STATUS_POLLS],
                 metric_min[phase][METRIC_DESC_TOTAL_CYCLES],
                 metric_min[phase][METRIC_LOAD_CYCLES],
                 metric_min[phase][METRIC_CORE_CYCLES],
                 metric_min[phase][METRIC_STORE_CYCLES],
                 metric_min[phase][METRIC_TOTAL_CYCLES],
                 active_share);
      end
    end
  endtask

  task automatic compare_outputs(
      input int inblocks,
      input int case_id,
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
        $display("FAIL cvxif_desc_adapter inblocks=%0d case=%0d lane=0", inblocks, case_id);
        $display("  expected %h", exp0);
        $display("  got      %h", got0);
        errors++;
      end
      if (got1 !== exp1) begin
        $display("FAIL cvxif_desc_adapter inblocks=%0d case=%0d lane=1", inblocks, case_id);
        $display("  expected %h", exp1);
        $display("  got      %h", got1);
        errors++;
      end
      if (got2 !== exp2) begin
        $display("FAIL cvxif_desc_adapter inblocks=%0d case=%0d lane=2", inblocks, case_id);
        $display("  expected %h", exp2);
        $display("  got      %h", got2);
        errors++;
      end
      if (got3 !== exp3) begin
        $display("FAIL cvxif_desc_adapter inblocks=%0d case=%0d lane=3", inblocks, case_id);
        $display("  expected %h", exp3);
        $display("  got      %h", got3);
        errors++;
      end
    end
  endtask

  task automatic test_illegal_instruction;
    logic [31:0] resp;
    bit illegal;
    begin
      issue_instr(8'hff, 32'd0, resp, illegal);
      if (!illegal) begin
        $fatal(1, "illegal opcode was accepted");
      end
    end
  endtask

  task automatic run_wait_success_mode(
      input string mode_name,
      input int read_wait_cycles,
      input int write_wait_cycles,
      input int random_ready_pct,
      input logic [31:0] seed,
      input string input_path0,
      input string input_path1,
      input string expected_path
  );
    int input_fd;
    int expected_fd;
    int rc;
    int num_cases;
    int expected_total;
    int expected_case_id;
    int exp_inblocks;
    int errors;
    int instruction_count;
    int status_poll_count;
    int descriptor_total_cycles;
    int load_cycles;
    int core_cycles;
    int store_cycles;
    int total_cycles;
    real active_share;
    string selected_input_path;
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
      configure_memory_model(read_wait_cycles, write_wait_cycles, random_ready_pct,
                             MEM_ERR_NONE, 0, 0, seed);
      reset_dut();

      expected_fd = $fopen(expected_path, "r");
      if (expected_fd == 0) begin
        $fatal(1, "failed to open %s", expected_path);
      end
      rc = $fscanf(expected_fd, "%d", expected_total);
      if (rc != 1) begin
        $fatal(1, "failed to read expected count from %s", expected_path);
      end

      errors = 0;
      expected_case_id = 0;
      $display("PHASE35B_PERF_TABLE mode=%s read_wait=%0d write_wait=%0d random_ready_pct=%0d",
               mode_name, read_wait_cycles, write_wait_cycles, random_ready_pct);
      $display("mode  inblocks  total_cycles  memory_load_cycles  core_cycles  memory_store_cycles  active_share  status_poll_count  instruction_count  error_count");

      for (int phase = 0; phase < 2; phase++) begin
        if (phase == 0) begin
          selected_input_path = input_path0;
        end else begin
          selected_input_path = input_path1;
        end

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
          $fatal(1, "failed to read descriptor input case 0 from %s",
                 selected_input_path);
        end
        $fclose(input_fd);

        rc = $fscanf(expected_fd, "%d %h %h %h %h",
                     exp_inblocks, exp0, exp1, exp2, exp3);
        if (rc != 5) begin
          $fatal(1, "failed to read descriptor expected case %0d from %s",
                 expected_case_id, expected_path);
        end
        if (exp_inblocks != (phase + 1)) begin
          $fatal(1, "expected file inblocks mismatch at case %0d: expected %0d got %0d",
                 expected_case_id, phase + 1, exp_inblocks);
        end

        run_cvxif_descriptor_case(expected_case_id, phase + 1, 1'b0,
                                  pub_seed, addr0, addr1, addr2, addr3,
                                  in0, in1, in2, in3,
                                  got0, got1, got2, got3,
                                  instruction_count, status_poll_count,
                                  descriptor_total_cycles, load_cycles,
                                  core_cycles, store_cycles, total_cycles);
        compare_outputs(phase + 1, 0, exp0, exp1, exp2, exp3,
                        got0, got1, got2, got3, errors);

        active_share = (100.0 * core_cycles) / total_cycles;
        $display("%s %9d %13d %19d %12d %20d %11.1f%% %18d %18d %12d",
                 mode_name, phase + 1, total_cycles, load_cycles, core_cycles,
                 store_cycles, active_share, status_poll_count,
                 instruction_count, errors);

        expected_case_id++;
        for (int skip_case = 1; skip_case < num_cases; skip_case++) begin
          rc = $fscanf(expected_fd, "%d %h %h %h %h",
                       exp_inblocks, exp0, exp1, exp2, exp3);
          if (rc != 5) begin
            $fatal(1, "failed to skip descriptor expected case %0d from %s",
                   expected_case_id, expected_path);
          end
          expected_case_id++;
        end
      end

      $fclose(expected_fd);
      if (errors != 0) begin
        $fatal(1, "FAIL wait mode %s mismatches=%0d", mode_name, errors);
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
      while (!observed_status[STATUS_DONE_BIT] && timeout_polls < 2000) begin
        expect_legal_instr(INSTR_SPX_STATUS, 32'd0, observed_status);
        instruction_count++;
        status_poll_count++;
        timeout_polls++;
      end

      if (!observed_status[STATUS_DONE_BIT]) begin
        $fatal(1, "%s timed out", test_name);
      end
      if (!observed_status[STATUS_ERROR_BIT]) begin
        $fatal(1, "%s completed without CV-X-IF error status=0x%08x",
               test_name, observed_status);
      end
      if (observed_status[STATUS_ERROR_CODE_LSB +: 4] != expected_error_code) begin
        $fatal(1, "%s CV-X-IF error_code mismatch expected=0x%0x got=0x%0x status=0x%08x",
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
        $fatal(1, "%s WAIT helper status mismatch status=0x%08x", test_name, resp);
      end

      expect_legal_instr(INSTR_SPX_CLEAR, 32'd0, resp);
      instruction_count++;
      $display("PHASE35B_ERROR_PASS %s error_code=0x%0x status_polls=%0d instruction_count=%0d desc_status=0x%08x",
               test_name, expected_error_code, status_poll_count, instruction_count,
               descriptor_status_word);
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

  task automatic run_phase35b_error_suite;
    logic [31:0] resp;
    begin
      configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35b0_0001);
      reset_dut();
      setup_zero_valid_case(1);
      expect_cvxif_descriptor_error("descriptor_addr_unaligned",
                                    DESC_BASE[31:0] + 32'd4,
                                    DESC_BASE[31:0] + 32'd4,
                                    ERR_BAD_ALIGN);

      configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35b0_0002);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_PUB_SEED_PTR_WORD, PUB_SEED_BASE[31:0] + 32'd4);
      expect_cvxif_descriptor_error("pub_seed_ptr_unaligned", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_BAD_ALIGN);

      configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35b0_0003);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_ADDR_BASE_WORD, ADDR_BASE[31:0] + 32'd4);
      expect_cvxif_descriptor_error("addr_base_ptr_unaligned", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_BAD_ALIGN);

      configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35b0_0004);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_INPUT_BASE_WORD, INPUT_BASE[31:0] + 32'd4);
      expect_cvxif_descriptor_error("input_base_ptr_unaligned", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_BAD_ALIGN);

      configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35b0_0005);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_OUTPUT_BASE_WORD, OUTPUT_BASE[31:0] + 32'd4);
      expect_cvxif_descriptor_error("output_base_ptr_unaligned", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_BAD_ALIGN);

      configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35b0_0010);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_CONFIG_WORD, 32'h0000_0140);
      expect_cvxif_descriptor_error("invalid_inblocks_0", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_BAD_CONFIG);

      configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35b0_0011);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_CONFIG_WORD, 32'h0000_0143);
      expect_cvxif_descriptor_error("invalid_inblocks_3", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_BAD_CONFIG);

      configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35b0_0012);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_CONFIG_WORD, 32'h0000_0121);
      expect_cvxif_descriptor_error("invalid_lanes", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_BAD_CONFIG);

      configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35b0_0013);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_CONFIG_WORD, 32'h0000_0241);
      expect_cvxif_descriptor_error("invalid_variant", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_BAD_CONFIG);

      configure_memory_model(0, 0, 100, MEM_ERR_READ_BUS, 0, 0, 32'h35b0_0020);
      reset_dut();
      setup_zero_valid_case(1);
      expect_cvxif_descriptor_error("read_bus_error", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_MEM_READ);

      configure_memory_model(0, 0, 100, MEM_ERR_READ_DATA, 0, 0, 32'h35b0_0021);
      reset_dut();
      setup_zero_valid_case(1);
      expect_cvxif_descriptor_error("read_data_error", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_MEM_READ);

      configure_memory_model(0, 0, 100, MEM_ERR_WRITE_RESP, 0, 0, 32'h35b0_0022);
      reset_dut();
      setup_zero_valid_case(1);
      expect_cvxif_descriptor_error("write_response_error", DESC_BASE[31:0],
                                    DESC_BASE[31:0], ERR_MEM_WRITE);

      configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35b0_0030);
      reset_dut();
      setup_zero_valid_case(1);
      write_mem_word(DESC_BASE, DESC_LENGTH_WORD, 32'd1);
      expect_legal_instr(INSTR_SPX_SET_DESC, DESC_BASE[31:0], resp);
      expect_legal_instr(INSTR_SPX_START, 32'd0, resp);
      do begin
        expect_legal_instr(INSTR_SPX_STATUS, 32'd0, resp);
      end while (!resp[STATUS_DONE_BIT]);
      if (resp[STATUS_ERROR_BIT]) begin
        $fatal(1, "descriptor_len_words is documented unchecked, but status errored: 0x%08x",
               resp);
      end
      expect_legal_instr(INSTR_SPX_CLEAR, 32'd0, resp);
      $display("PHASE35B_DESC_LEN_UNCHECKED descriptor_len_words=1 completed_without_error");
    end
  endtask

  task automatic run_phase35b_wait_suite(
      input string input_path0,
      input string input_path1,
      input string expected_path
  );
    begin
      run_wait_success_mode("zero_wait", 0, 0, 100, 32'h35b0_1000,
                            input_path0, input_path1, expected_path);
      run_wait_success_mode("fixed_wait_1", 1, 1, 100, 32'h35b0_1001,
                            input_path0, input_path1, expected_path);
      run_wait_success_mode("fixed_wait_2", 2, 2, 100, 32'h35b0_1002,
                            input_path0, input_path1, expected_path);
      run_wait_success_mode("random_ready_50", 0, 0, 50, 32'h35b0_1050,
                            input_path0, input_path1, expected_path);
      run_wait_success_mode("random_ready_75", 0, 0, 75, 32'h35b0_1075,
                            input_path0, input_path1, expected_path);
      run_wait_success_mode("fixed_wait_4_smoke", 4, 4, 100, 32'h35b0_1004,
                            input_path0, input_path1, expected_path);
      run_wait_success_mode("split_read2_write4_smoke", 2, 4, 100, 32'h35b0_1240,
                            input_path0, input_path1, expected_path);

      run_phase35b_error_suite();
      $display("PASS spx_cvxif_desc_adapter_wait memory wait/backpressure/error tests");
    end
  endtask

  initial begin
    string input_path [0:1];
    string expected_path;
    int expected_inblocks [0:1];
    int input_fd;
    int expected_fd;
    int rc;
    int num_cases;
    int expected_total;
    int expected_case_id;
    int exp_inblocks;
    int errors;
    int instruction_count;
    int status_poll_count;
    int descriptor_total_cycles;
    int load_cycles;
    int core_cycles;
    int store_cycles;
    int total_cycles;
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

    if (!$value$plusargs("VECTORS_IB1=%s", input_path[0])) begin
      input_path[0] = "sim/vectors/thashx4_inblocks1.hex";
    end
    if (!$value$plusargs("VECTORS_IB2=%s", input_path[1])) begin
      input_path[1] = "sim/vectors/thashx4_inblocks2.hex";
    end
    if (!$value$plusargs("EXPECTED=%s", expected_path)) begin
      expected_path = "sim/vectors/thashx4_expected.hex";
    end

    expected_inblocks[0] = 1;
    expected_inblocks[1] = 2;

    configure_memory_model(0, 0, 100, MEM_ERR_NONE, 0, 0, 32'h35a0_0001);
    reset_dut();
    init_metric_stats();
    test_illegal_instruction();

    if ($test$plusargs("PHASE35B_WAIT")) begin
      run_phase35b_wait_suite(input_path[0], input_path[1], expected_path);
      $finish;
    end

    expected_fd = $fopen(expected_path, "r");
    if (expected_fd == 0) begin
      $fatal(1, "failed to open %s", expected_path);
    end

    rc = $fscanf(expected_fd, "%d", expected_total);
    if (rc != 1) begin
      $fatal(1, "failed to read expected count from %s", expected_path);
    end

    errors = 0;
    expected_case_id = 0;

    for (int phase = 0; phase < 2; phase++) begin
      input_fd = $fopen(input_path[phase], "r");
      if (input_fd == 0) begin
        $fatal(1, "failed to open %s", input_path[phase]);
      end

      rc = $fscanf(input_fd, "%d", num_cases);
      if (rc != 1) begin
        $fatal(1, "failed to read case count from %s", input_path[phase]);
      end

      for (int case_id = 0; case_id < num_cases; case_id++) begin
        rc = $fscanf(input_fd, "%h %h %h %h %h %h %h %h %h",
                     pub_seed, addr0, addr1, addr2, addr3,
                     in0, in1, in2, in3);
        if (rc != 9) begin
          $fatal(1, "failed to read descriptor input case %0d from %s",
                 case_id, input_path[phase]);
        end

        rc = $fscanf(expected_fd, "%d %h %h %h %h",
                     exp_inblocks, exp0, exp1, exp2, exp3);
        if (rc != 5) begin
          $fatal(1, "failed to read descriptor expected case %0d from %s",
                 expected_case_id, expected_path);
        end
        if (exp_inblocks != expected_inblocks[phase]) begin
          $fatal(1, "expected file inblocks mismatch at case %0d: expected %0d got %0d",
                 expected_case_id, expected_inblocks[phase], exp_inblocks);
        end

        run_cvxif_descriptor_case(expected_case_id, expected_inblocks[phase], 1'b0,
                                  pub_seed, addr0, addr1, addr2, addr3,
                                  in0, in1, in2, in3,
                                  got0, got1, got2, got3,
                                  instruction_count, status_poll_count,
                                  descriptor_total_cycles, load_cycles,
                                  core_cycles, store_cycles, total_cycles);
        update_metrics(phase, instruction_count, status_poll_count,
                       descriptor_total_cycles, load_cycles, core_cycles,
                       store_cycles, total_cycles);
        compare_outputs(expected_inblocks[phase], case_id,
                        exp0, exp1, exp2, exp3, got0, got1, got2, got3, errors);

        if (case_id == 0) begin
          run_cvxif_descriptor_case(expected_case_id, expected_inblocks[phase], 1'b1,
                                    pub_seed, addr0, addr1, addr2, addr3,
                                    in0, in1, in2, in3,
                                    got0, got1, got2, got3,
                                    instruction_count, status_poll_count,
                                    descriptor_total_cycles, load_cycles,
                                    core_cycles, store_cycles, total_cycles);
          compare_outputs(expected_inblocks[phase], case_id,
                          exp0, exp1, exp2, exp3, got0, got1, got2, got3, errors);
        end

        expected_case_id++;
      end

      $fclose(input_fd);
    end

    $fclose(expected_fd);

    if (expected_case_id != expected_total) begin
      $fatal(1, "expected file count mismatch: header=%0d consumed=%0d",
             expected_total, expected_case_id);
    end

    if (errors != 0) begin
      $fatal(1, "FAIL spx_cvxif_desc_adapter mismatches=%0d", errors);
    end

    for (int phase = 0; phase < 2; phase++) begin
      print_stats(phase, expected_inblocks[phase]);
    end
    print_comparison_table();

    $display("PASS spx_cvxif_desc_adapter width=4words_per_cycle inblocks=1,2 (%0d cases)",
             expected_case_id);
    $finish;
  end
endmodule
