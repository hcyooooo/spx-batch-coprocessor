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

  assign mem_ready = 1'b1;

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
      word_addr = int'(mem_addr[MEM_ADDR_WIDTH-1:2]) + lane;
      if (mem_valid && !mem_we && (word_addr < MEM_WORDS)) begin
        mem_rdata[32 * lane +: 32] = mem[word_addr];
      end
    end
  end

  always_ff @(posedge clk) begin
    if (mem_valid && mem_ready && mem_we) begin
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
      while (!observed_status[STATUS_DONE_BIT] && timeout_polls < 300) begin
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

    reset_dut();
    init_metric_stats();
    test_illegal_instruction();

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
