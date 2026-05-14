module tb_wots_chain_descriptor;
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

  localparam int DESC_FLAGS_STATUS_WORD = 0;
  localparam int DESC_CONFIG_WORD       = 1;
  localparam int DESC_PUB_SEED_PTR_WORD = 2;
  localparam int DESC_ADDR_BASE_WORD    = 3;
  localparam int DESC_INPUT_BASE_WORD   = 4;
  localparam int DESC_OUTPUT_BASE_WORD  = 5;
  localparam int DESC_LENGTH_WORD       = 6;
  localparam int DESC_CHAIN_CTRL_WORD   = 7;

  localparam int STATUS_DONE_BIT       = 1;
  localparam int STATUS_ERROR_BIT      = 2;
  localparam int STATUS_ERROR_CODE_LSB = 4;

  localparam logic [31:0] CONFIG_VARIANT_SHAKE_128F_SIMPLE = 32'h0000_0100;
  localparam logic [31:0] CONFIG_LANES_X4                  = 32'h0000_0040;
  localparam logic [31:0] CONFIG_OP_TYPE_WOTS_CHAINX4      = 32'h0001_0000;

  localparam logic [3:0] ERR_BAD_OP_TYPE = 4'h5;
  localparam logic [3:0] ERR_BAD_CHAIN   = 4'h6;

  logic clk;
  logic rst_n;

  logic start;
  logic [MEM_ADDR_WIDTH-1:0] descriptor_addr;
  logic busy;
  logic done;
  logic error;
  logic [31:0] status;

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

  spx_descriptor_adapter #(
      .MEM_WORDS_PER_CYCLE(MEM_WORDS_PER_CYCLE),
      .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .descriptor_addr(descriptor_addr),
      .busy(busy),
      .done(done),
      .error(error),
      .status(status),
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

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  assign mem_ready = 1'b1;
  assign mem_error = 1'b0;

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
      rst_n           = 1'b0;
      start           = 1'b0;
      descriptor_addr = '0;
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

  task automatic setup_wots_descriptor_case(
      input int start_step_i,
      input int num_steps_i,
      input logic [127:0] pub_seed,
      input logic [255:0] addr0,
      input logic [255:0] addr1,
      input logic [255:0] addr2,
      input logic [255:0] addr3,
      input logic [127:0] in0,
      input logic [127:0] in1,
      input logic [127:0] in2,
      input logic [127:0] in3
  );
    begin
      clear_memory();

      write_mem_word(DESC_BASE, DESC_FLAGS_STATUS_WORD, 32'd0);
      write_mem_word(DESC_BASE, DESC_CONFIG_WORD,
                     CONFIG_OP_TYPE_WOTS_CHAINX4 |
                     CONFIG_VARIANT_SHAKE_128F_SIMPLE |
                     CONFIG_LANES_X4);
      write_mem_word(DESC_BASE, DESC_PUB_SEED_PTR_WORD, PUB_SEED_BASE[31:0]);
      write_mem_word(DESC_BASE, DESC_ADDR_BASE_WORD, ADDR_BASE[31:0]);
      write_mem_word(DESC_BASE, DESC_INPUT_BASE_WORD, INPUT_BASE[31:0]);
      write_mem_word(DESC_BASE, DESC_OUTPUT_BASE_WORD, OUTPUT_BASE[31:0]);
      write_mem_word(DESC_BASE, DESC_LENGTH_WORD, 32'd8);
      write_mem_word(DESC_BASE, DESC_CHAIN_CTRL_WORD,
                     (32'(num_steps_i & 32'hff) << 8) |
                     32'(start_step_i & 32'hff));

      for (int word = 0; word < 4; word++) begin
        write_mem_word(PUB_SEED_BASE, word, pub_seed[32 * word +: 32]);
        write_mem_word(INPUT_BASE, word, in0[32 * word +: 32]);
        write_mem_word(INPUT_BASE, 4 + word, in1[32 * word +: 32]);
        write_mem_word(INPUT_BASE, 8 + word, in2[32 * word +: 32]);
        write_mem_word(INPUT_BASE, 12 + word, in3[32 * word +: 32]);
      end

      for (int word = 0; word < 8; word++) begin
        write_mem_word(ADDR_BASE, word, addr0[32 * word +: 32]);
        write_mem_word(ADDR_BASE, 8 + word, addr1[32 * word +: 32]);
        write_mem_word(ADDR_BASE, 16 + word, addr2[32 * word +: 32]);
        write_mem_word(ADDR_BASE, 24 + word, addr3[32 * word +: 32]);
      end

      for (int word = 0; word < 16; word++) begin
        write_mem_word(OUTPUT_BASE, word, 32'hdeadc0de);
      end
    end
  endtask

  task automatic run_descriptor(output int timeout_cycles);
    begin
      @(negedge clk);
      descriptor_addr = DESC_BASE[MEM_ADDR_WIDTH-1:0];
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;

      timeout_cycles = 0;
      while (!done && timeout_cycles < 2000) begin
        @(posedge clk);
        timeout_cycles++;
      end

      if (!done) begin
        $fatal(1, "WOTS chain descriptor timeout");
      end

      @(posedge clk);
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

  task automatic compare_lane(input int case_id,
                              input int lane,
                              input logic [127:0] expected,
                              input logic [127:0] got,
                              inout int errors);
    begin
      if (got !== expected) begin
        $display("FAIL wots_chain_descriptor case=%0d lane=%0d", case_id, lane);
        $display("  expected %h", expected);
        $display("  got      %h", got);
        errors++;
      end
    end
  endtask

  task automatic expect_descriptor_error(input string test_name,
                                         input logic [3:0] expected_error_code);
    int timeout_cycles;
    logic [31:0] descriptor_status;
    begin
      run_descriptor(timeout_cycles);

      if (!error || !status[STATUS_ERROR_BIT]) begin
        $fatal(1, "%s completed without adapter error status=0x%08x",
               test_name, status);
      end
      if (status[19:16] != expected_error_code) begin
        $fatal(1, "%s status error code mismatch expected=0x%0x got=0x%0x status=0x%08x",
               test_name, expected_error_code, status[19:16], status);
      end

      descriptor_status = read_mem_word(DESC_BASE, DESC_FLAGS_STATUS_WORD);
      if (!descriptor_status[STATUS_DONE_BIT] ||
          !descriptor_status[STATUS_ERROR_BIT] ||
          (descriptor_status[STATUS_ERROR_CODE_LSB +: 4] != expected_error_code)) begin
        $fatal(1, "%s descriptor status mismatch expected_code=0x%0x desc_status=0x%08x",
               test_name, expected_error_code, descriptor_status);
      end

      $display("WOTS_CHAIN_DESCRIPTOR_ERROR_PASS %s error_code=0x%0x timeout_cycles=%0d",
               test_name, expected_error_code, timeout_cycles);
    end
  endtask

  initial begin
    string vectors_path;
    int fd;
    int rc;
    int num_cases;
    int case_id_file;
    int start_step_i;
    int num_steps_i;
    int errors;
    int timeout_cycles;
    int baseline_cycles;
    real speedup;
    real cycles_per_thash_equiv;
    logic [127:0] pub_seed;
    logic [255:0] addr0;
    logic [255:0] addr1;
    logic [255:0] addr2;
    logic [255:0] addr3;
    logic [127:0] in0;
    logic [127:0] in1;
    logic [127:0] in2;
    logic [127:0] in3;
    logic [127:0] exp0;
    logic [127:0] exp1;
    logic [127:0] exp2;
    logic [127:0] exp3;
    logic [127:0] got0;
    logic [127:0] got1;
    logic [127:0] got2;
    logic [127:0] got3;
    logic [31:0] descriptor_status;

    if (!$value$plusargs("VECTORS=%s", vectors_path)) begin
      vectors_path = "sim/vectors/wots_chainx4_vectors.hex";
    end

    reset_dut();

    fd = $fopen(vectors_path, "r");
    if (fd == 0) begin
      $fatal(1, "failed to open %s", vectors_path);
    end

    rc = $fscanf(fd, "%d", num_cases);
    if (rc != 1) begin
      $fatal(1, "failed to read case count from %s", vectors_path);
    end

    errors = 0;

    $display("WOTS_CHAIN_DESCRIPTOR_COMPARISON width=4words_per_cycle");
    $display("num_steps  baseline_descriptor_thashx4_cycles  wots_descriptor_cycles  speedup  load  core  store  bus_rd  bus_wr");
    $display("---------------------------------------------------------------------------------------------------------------");

    for (int case_id = 0; case_id < num_cases; case_id++) begin
      rc = $fscanf(fd, "%d %d %d %h %h %h %h %h %h %h %h %h %h %h %h %h",
                   case_id_file, start_step_i, num_steps_i, pub_seed,
                   addr0, addr1, addr2, addr3,
                   in0, in1, in2, in3,
                   exp0, exp1, exp2, exp3);
      if (rc != 16) begin
        $fatal(1, "failed to read WOTS chain descriptor case %0d from %s",
               case_id, vectors_path);
      end
      if (case_id_file != case_id) begin
        $fatal(1, "case id mismatch: expected %0d got %0d",
               case_id, case_id_file);
      end

      setup_wots_descriptor_case(start_step_i, num_steps_i,
                                 pub_seed, addr0, addr1, addr2, addr3,
                                 in0, in1, in2, in3);
      run_descriptor(timeout_cycles);

      if (error || status[STATUS_ERROR_BIT]) begin
        $fatal(1, "WOTS chain descriptor error case=%0d status=0x%08x",
               case_id, status);
      end

      descriptor_status = read_mem_word(DESC_BASE, DESC_FLAGS_STATUS_WORD);
      if (!descriptor_status[STATUS_DONE_BIT] ||
          descriptor_status[STATUS_ERROR_BIT]) begin
        $fatal(1, "WOTS descriptor status mismatch case=%0d desc_status=0x%08x",
               case_id, descriptor_status);
      end

      read_output_words(got0, got1, got2, got3);
      compare_lane(case_id, 0, exp0, got0, errors);
      compare_lane(case_id, 1, exp1, got1, errors);
      compare_lane(case_id, 2, exp2, got2, errors);
      compare_lane(case_id, 3, exp3, got3, errors);

      baseline_cycles = 57 * num_steps_i;
      speedup = real'(baseline_cycles) / real'(perf_total_cycles);
      cycles_per_thash_equiv = real'(perf_total_cycles) / real'(4 * num_steps_i);
      $display("%9d %34d %22d %8.2fx %5d %5d %6d %7d %7d",
               num_steps_i, baseline_cycles, int'(perf_total_cycles), speedup,
               int'(perf_load_cycles), int'(perf_core_cycles),
               int'(perf_store_cycles), 15, 5);
      $display("WOTS_CHAIN_DESCRIPTOR_PERF case=%0d start_step=%0d num_steps=%0d total=%0d cycles_per_thash_equiv=%0.2f",
               case_id, start_step_i, num_steps_i, int'(perf_total_cycles),
               cycles_per_thash_equiv);
    end

    $fclose(fd);

    if (errors != 0) begin
      $fatal(1, "FAIL wots_chain_descriptor mismatches=%0d", errors);
    end

    setup_wots_descriptor_case(0, 0, pub_seed, addr0, addr1, addr2, addr3,
                               in0, in1, in2, in3);
    expect_descriptor_error("bad_num_steps_zero", ERR_BAD_CHAIN);

    setup_wots_descriptor_case(0, 16, pub_seed, addr0, addr1, addr2, addr3,
                               in0, in1, in2, in3);
    expect_descriptor_error("bad_num_steps_16", ERR_BAD_CHAIN);

    setup_wots_descriptor_case(15, 2, pub_seed, addr0, addr1, addr2, addr3,
                               in0, in1, in2, in3);
    expect_descriptor_error("bad_start_plus_num_steps", ERR_BAD_CHAIN);

    setup_wots_descriptor_case(0, 1, pub_seed, addr0, addr1, addr2, addr3,
                               in0, in1, in2, in3);
    write_mem_word(DESC_BASE, DESC_CONFIG_WORD,
                   32'h007f_0000 |
                   CONFIG_VARIANT_SHAKE_128F_SIMPLE |
                   CONFIG_LANES_X4);
    expect_descriptor_error("bad_op_type", ERR_BAD_OP_TYPE);

    $display("PASS wots_chain_descriptor (%0d WOTS cases)", num_cases);
    $finish;
  end
endmodule
