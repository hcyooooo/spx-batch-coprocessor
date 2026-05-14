module tb_cv32e40x_spx_core_smoke import cv32e40x_pkg::*;
();
  timeunit 1ns;
  timeprecision 1ps;

  localparam int X_NUM_RS             = 2;
  localparam int X_ID_WIDTH           = 4;
  localparam int X_MEM_WIDTH          = 32;
  localparam int X_RFR_WIDTH          = 32;
  localparam int X_RFW_WIDTH          = 32;
  localparam int MEM_WORDS_PER_CYCLE  = 4;
  localparam int MEM_ADDR_WIDTH       = 32;
  localparam int MEM_DATA_WIDTH       = 32 * MEM_WORDS_PER_CYCLE;
  localparam int MEM_BYTES            = 128 * 1024;
  localparam int TIMEOUT_CYCLES       = 300000;
  localparam logic [31:0] BOOT_ADDR   = 32'h0000_0000;
  localparam logic [31:0] MTVEC_ADDR  = 32'h0000_0000;
  localparam logic [31:0] MAGIC_ADDR  = 32'h0000_fffc;
  localparam logic [31:0] MAGIC_PASS  = 32'h0000_0001;
  localparam logic [31:0] MAGIC_FAIL  = 32'h0000_dead;
  localparam logic [31:0] MAGIC_ERROR_PASS = 32'h0000_e55e;
  localparam logic [31:0] STATS_ADDR       = 32'h0000_ffe0;
  localparam logic [31:0] CTRL_ADDR        = 32'h0000_ffd0;
  localparam logic [31:0] VECTOR_TABLE_ADDR = 32'h0000_8000;
  localparam logic [31:0] VECTOR_TABLE_MAGIC = 32'h5350_5856;
  localparam int VECTOR_HEADER_WORDS = 4;
  localparam int VECTOR_CASE_WORDS   = 85;
  localparam int CASE_PUB_SEED_WORD  = 1;
  localparam int CASE_ADDR_WORD      = 5;
  localparam int CASE_INPUT_WORD     = 37;
  localparam int CASE_EXPECTED_WORD  = 69;
  localparam int DEFAULT_CASES_PER_INBLOCKS = 8;
  localparam int BUS_ERR_NONE       = 0;
  localparam int BUS_ERR_READ_ONCE  = 1;
  localparam int BUS_ERR_WRITE_ONCE = 2;

  logic clk;
  logic rst_n;
  logic fetch_enable;

  logic        instr_req;
  logic        instr_gnt;
  logic        instr_rvalid;
  logic [31:0] instr_addr;
  logic [1:0]  instr_memtype;
  logic [2:0]  instr_prot;
  logic        instr_dbg;
  logic [31:0] instr_rdata;
  logic        instr_err;

  logic        data_req;
  logic        data_gnt;
  logic        data_rvalid;
  logic [31:0] data_addr;
  logic [3:0]  data_be;
  logic        data_we;
  logic [31:0] data_wdata;
  logic [1:0]  data_memtype;
  logic [2:0]  data_prot;
  logic        data_dbg;
  logic [5:0]  data_atop;
  logic [31:0] data_rdata;
  logic        data_err;
  logic        data_exokay;

  logic [63:0] mcycle;
  logic [63:0] time_q;

  logic        fencei_flush_req;
  logic        fencei_flush_ack;
  logic        debug_havereset;
  logic        debug_running;
  logic        debug_halted;
  logic        debug_pc_valid;
  logic [31:0] debug_pc;
  logic        core_sleep;

  cv32e40x_if_xif #(
      .X_NUM_RS(X_NUM_RS),
      .X_ID_WIDTH(X_ID_WIDTH),
      .X_MEM_WIDTH(X_MEM_WIDTH),
      .X_RFR_WIDTH(X_RFR_WIDTH),
      .X_RFW_WIDTH(X_RFW_WIDTH),
      .X_MISA(32'h0000_0000),
      .X_ECS_XS(2'b00)
  ) xif ();

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

  logic                      mem_valid;
  logic                      mem_ready;
  logic                      mem_we;
  logic [MEM_ADDR_WIDTH-1:0] mem_addr;
  logic [MEM_DATA_WIDTH-1:0] mem_wdata;
  logic [MEM_DATA_WIDTH-1:0] mem_rdata;
  logic                      mem_error;

  logic                      bus_req_valid;
  logic                      bus_req_ready;
  logic                      bus_req_we;
  logic [MEM_ADDR_WIDTH-1:0] bus_req_addr;
  logic [MEM_DATA_WIDTH-1:0] bus_req_wdata;
  logic                      bus_rsp_valid;
  logic [MEM_DATA_WIDTH-1:0] bus_rsp_rdata;
  logic                      bus_rsp_error;

  logic [31:0] perf_load_cycles;
  logic [31:0] perf_core_cycles;
  logic [31:0] perf_store_cycles;
  logic [31:0] perf_total_cycles;

  logic [7:0] memory [0:MEM_BYTES-1];

  int unsigned cycle_q;
  int unsigned instr_fetch_count_q;
  int unsigned data_read_count_q;
  int unsigned data_write_count_q;
  int unsigned xif_issue_count_q;
  int unsigned xif_accept_count_q;
  int unsigned xif_result_count_q;
  int unsigned xif_mem_valid_count_q;
  int unsigned desc_control_count_q;
  int unsigned bus_read_count_q;
  int unsigned bus_write_count_q;
  int unsigned bus_read_latency_cfg;
  int unsigned bus_write_latency_cfg;
  int unsigned bus_req_ready_pct_cfg;
  int unsigned smoke_cases_per_inblocks_cfg;
  int unsigned bus_read_accept_count_q;
  int unsigned bus_write_accept_count_q;
  int unsigned bus_error_kind_q;
  int unsigned bus_rsp_wait_q;
  logic [31:0] bus_rng_q;
  logic        bus_rsp_pending_q;
  logic [MEM_DATA_WIDTH-1:0] bus_rsp_rdata_q;
  logic        bus_rsp_error_q;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    bus_read_latency_cfg      = 0;
    bus_write_latency_cfg     = 0;
    bus_req_ready_pct_cfg     = 100;
    smoke_cases_per_inblocks_cfg = DEFAULT_CASES_PER_INBLOCKS;

    void'($value$plusargs("SMOKE_READ_LATENCY=%d", bus_read_latency_cfg));
    void'($value$plusargs("SMOKE_WRITE_LATENCY=%d", bus_write_latency_cfg));
    void'($value$plusargs("SMOKE_REQ_READY_PCT=%d", bus_req_ready_pct_cfg));
    if (bus_req_ready_pct_cfg > 100) begin
      bus_req_ready_pct_cfg = 100;
    end
  end

  initial begin
    string smoke_hex;
    string vectors_ib1;
    string vectors_ib2;
    string expected_vectors;

    for (int i = 0; i < MEM_BYTES; i++) begin
      memory[i] = 8'h00;
    end

    if (!$value$plusargs("SMOKE_HEX=%s", smoke_hex)) begin
      smoke_hex = "build/spx_cvxif_smoke.hex";
    end
    $display("Loading CV32E40X smoke image: %s", smoke_hex);
    $readmemh(smoke_hex, memory);

    if (!$value$plusargs("VECTORS_IB1=%s", vectors_ib1)) begin
      vectors_ib1 = "vectors/thashx4_inblocks1.hex";
    end
    if (!$value$plusargs("VECTORS_IB2=%s", vectors_ib2)) begin
      vectors_ib2 = "vectors/thashx4_inblocks2.hex";
    end
    if (!$value$plusargs("EXPECTED=%s", expected_vectors)) begin
      expected_vectors = "vectors/thashx4_expected.hex";
    end
    if (!$value$plusargs("SMOKE_CASES_PER_INBLOCKS=%d", smoke_cases_per_inblocks_cfg)) begin
      smoke_cases_per_inblocks_cfg = DEFAULT_CASES_PER_INBLOCKS;
    end
    load_smoke_vector_table(vectors_ib1, vectors_ib2, expected_vectors,
                            smoke_cases_per_inblocks_cfg);
  end

  initial begin
    rst_n        = 1'b0;
    fetch_enable = 1'b0;
    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);
    fetch_enable = 1'b1;
  end

  function automatic logic [31:0] read_word(input logic [31:0] byte_addr);
    int unsigned addr;
    begin
      addr = int'(byte_addr);
      if ((addr + 3) >= MEM_BYTES) begin
        $fatal(1, "memory read out of range addr=0x%08x", byte_addr);
      end
      read_word = 32'(memory[addr]) |
                  (32'(memory[addr + 1]) << 8) |
                  (32'(memory[addr + 2]) << 16) |
                  (32'(memory[addr + 3]) << 24);
    end
  endfunction

  task automatic write_word(
      input logic [31:0] byte_addr,
      input logic [31:0] wdata,
      input logic [3:0]  be
  );
    int unsigned addr;
    begin
      addr = int'(byte_addr);
      if ((addr + 3) >= MEM_BYTES) begin
        $fatal(1, "memory write out of range addr=0x%08x data=0x%08x",
               byte_addr, wdata);
      end
      if (be[0]) begin
        memory[addr] = wdata[7:0];
      end
      if (be[1]) begin
        memory[addr + 1] = wdata[15:8];
      end
      if (be[2]) begin
        memory[addr + 2] = wdata[23:16];
      end
      if (be[3]) begin
        memory[addr + 3] = wdata[31:24];
      end
    end
  endtask

  function automatic logic [MEM_DATA_WIDTH-1:0] read_bus_beat(
      input logic [MEM_ADDR_WIDTH-1:0] byte_addr
  );
    logic [MEM_DATA_WIDTH-1:0] data;
    begin
      data = '0;
      for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
        data[32 * lane +: 32] = read_word(byte_addr + 32'(lane * 4));
      end
      read_bus_beat = data;
    end
  endfunction

  task automatic write_bus_beat(
      input logic [MEM_ADDR_WIDTH-1:0] byte_addr,
      input logic [MEM_DATA_WIDTH-1:0] wdata
  );
    begin
      for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
        write_word(byte_addr + 32'(lane * 4), wdata[32 * lane +: 32], 4'hf);
      end
    end
  endtask

  function automatic logic [31:0] xorshift32(input logic [31:0] value);
    logic [31:0] next_value;
    begin
      next_value = value;
      next_value ^= (next_value << 13);
      next_value ^= (next_value >> 17);
      next_value ^= (next_value << 5);
      xorshift32 = (next_value == 32'd0) ? 32'hc032_3e8a : next_value;
    end
  endfunction

  function automatic bit bus_random_ready_ok;
    begin
      if (bus_req_ready_pct_cfg >= 100) begin
        bus_random_ready_ok = 1'b1;
      end else if (bus_req_ready_pct_cfg == 0) begin
        bus_random_ready_ok = 1'b0;
      end else begin
        bus_random_ready_ok = (int'(bus_rng_q % 100) < bus_req_ready_pct_cfg);
      end
    end
  endfunction

  function automatic bit bus_inject_error(input logic is_write);
    begin
      bus_inject_error =
          (!is_write && (bus_error_kind_q == BUS_ERR_READ_ONCE)) ||
          (is_write && (bus_error_kind_q == BUS_ERR_WRITE_ONCE));
    end
  endfunction

  task automatic write_table_word(input int word_offset, input logic [31:0] data);
    begin
      write_word(VECTOR_TABLE_ADDR + 32'(word_offset * 4), data, 4'hf);
    end
  endtask

  task automatic write_vector_case(
      input int case_index,
      input int inblocks,
      input logic [127:0] pub_seed,
      input logic [255:0] addr0,
      input logic [255:0] addr1,
      input logic [255:0] addr2,
      input logic [255:0] addr3,
      input logic [255:0] in0,
      input logic [255:0] in1,
      input logic [255:0] in2,
      input logic [255:0] in3,
      input logic [127:0] exp0,
      input logic [127:0] exp1,
      input logic [127:0] exp2,
      input logic [127:0] exp3
  );
    int base_word;
    begin
      base_word = VECTOR_HEADER_WORDS + case_index * VECTOR_CASE_WORDS;
      write_table_word(base_word, 32'(inblocks));

      for (int word = 0; word < 4; word++) begin
        write_table_word(base_word + CASE_PUB_SEED_WORD + word,
                         pub_seed[32 * word +: 32]);
      end

      for (int word = 0; word < 8; word++) begin
        write_table_word(base_word + CASE_ADDR_WORD + word,
                         addr0[32 * word +: 32]);
        write_table_word(base_word + CASE_ADDR_WORD + 8 + word,
                         addr1[32 * word +: 32]);
        write_table_word(base_word + CASE_ADDR_WORD + 16 + word,
                         addr2[32 * word +: 32]);
        write_table_word(base_word + CASE_ADDR_WORD + 24 + word,
                         addr3[32 * word +: 32]);
        write_table_word(base_word + CASE_INPUT_WORD + word,
                         in0[32 * word +: 32]);
        write_table_word(base_word + CASE_INPUT_WORD + 8 + word,
                         in1[32 * word +: 32]);
        write_table_word(base_word + CASE_INPUT_WORD + 16 + word,
                         in2[32 * word +: 32]);
        write_table_word(base_word + CASE_INPUT_WORD + 24 + word,
                         in3[32 * word +: 32]);
      end

      for (int word = 0; word < 4; word++) begin
        write_table_word(base_word + CASE_EXPECTED_WORD + word,
                         exp0[32 * word +: 32]);
        write_table_word(base_word + CASE_EXPECTED_WORD + 4 + word,
                         exp1[32 * word +: 32]);
        write_table_word(base_word + CASE_EXPECTED_WORD + 8 + word,
                         exp2[32 * word +: 32]);
        write_table_word(base_word + CASE_EXPECTED_WORD + 12 + word,
                         exp3[32 * word +: 32]);
      end
    end
  endtask

  task automatic load_smoke_vector_table(
      input string input_path0,
      input string input_path1,
      input string expected_path,
      input int cases_per_inblocks
  );
    int input_fd;
    int expected_fd;
    int rc;
    int num_cases;
    int expected_total;
    int exp_inblocks;
    int loaded_cases;
    int global_case_index;
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
    begin
      if (cases_per_inblocks < DEFAULT_CASES_PER_INBLOCKS) begin
        $fatal(1, "SMOKE_CASES_PER_INBLOCKS=%0d below required minimum %0d",
               cases_per_inblocks, DEFAULT_CASES_PER_INBLOCKS);
      end

      expected_fd = $fopen(expected_path, "r");
      if (expected_fd == 0) begin
        $fatal(1, "failed to open %s", expected_path);
      end
      rc = $fscanf(expected_fd, "%d", expected_total);
      if (rc != 1) begin
        $fatal(1, "failed to read expected count from %s", expected_path);
      end
      if (expected_total < (2 * cases_per_inblocks)) begin
        $fatal(1, "%s only has %0d expected cases, need %0d",
               expected_path, expected_total, 2 * cases_per_inblocks);
      end

      write_table_word(0, VECTOR_TABLE_MAGIC);
      write_table_word(1, 32'(cases_per_inblocks));
      write_table_word(2, 32'(cases_per_inblocks));
      write_table_word(3, 32'(VECTOR_CASE_WORDS));

      global_case_index = 0;
      for (int phase = 0; phase < 2; phase++) begin
        selected_input_path = (phase == 0) ? input_path0 : input_path1;
        input_fd = $fopen(selected_input_path, "r");
        if (input_fd == 0) begin
          $fatal(1, "failed to open %s", selected_input_path);
        end

        rc = $fscanf(input_fd, "%d", num_cases);
        if (rc != 1) begin
          $fatal(1, "failed to read case count from %s", selected_input_path);
        end
        if (num_cases < cases_per_inblocks) begin
          $fatal(1, "%s only has %0d cases, need %0d",
                 selected_input_path, num_cases, cases_per_inblocks);
        end

        loaded_cases = 0;
        for (int case_id = 0; case_id < num_cases; case_id++) begin
          rc = $fscanf(input_fd, "%h %h %h %h %h %h %h %h %h",
                       pub_seed, addr0, addr1, addr2, addr3,
                       in0, in1, in2, in3);
          if (rc != 9) begin
            $fatal(1, "failed to read input case %0d from %s",
                   case_id, selected_input_path);
          end

          rc = $fscanf(expected_fd, "%d %h %h %h %h",
                       exp_inblocks, exp0, exp1, exp2, exp3);
          if (rc != 5) begin
            $fatal(1, "failed to read expected case phase=%0d case=%0d from %s",
                   phase, case_id, expected_path);
          end
          if (exp_inblocks != (phase + 1)) begin
            $fatal(1, "expected inblocks mismatch phase=%0d case=%0d expected=%0d got=%0d",
                   phase, case_id, phase + 1, exp_inblocks);
          end

          if (case_id < cases_per_inblocks) begin
            write_vector_case(global_case_index, phase + 1,
                              pub_seed, addr0, addr1, addr2, addr3,
                              in0, in1, in2, in3, exp0, exp1, exp2, exp3);
            global_case_index++;
            loaded_cases++;
          end
        end
        $fclose(input_fd);
        if (loaded_cases != cases_per_inblocks) begin
          $fatal(1, "loaded %0d cases for inblocks=%0d, expected %0d",
                 loaded_cases, phase + 1, cases_per_inblocks);
        end
      end
      $fclose(expected_fd);
      $display("Loaded CV32E40X smoke vector table: inblocks1=%0d inblocks2=%0d case_words=%0d",
               cases_per_inblocks, cases_per_inblocks, VECTOR_CASE_WORDS);
    end
  endtask

  cv32e40x_core #(
      .LIB(0),
      .RV32(RV32I),
      .A_EXT(A_NONE),
      .B_EXT(B_NONE),
      .M_EXT(M),
      .DEBUG(1'b0),
      .DBG_NUM_TRIGGERS(1),
      .CLIC(1'b0),
      .X_EXT(1'b1),
      .X_NUM_RS(X_NUM_RS),
      .X_ID_WIDTH(X_ID_WIDTH),
      .X_MEM_WIDTH(X_MEM_WIDTH),
      .X_RFR_WIDTH(X_RFR_WIDTH),
      .X_RFW_WIDTH(X_RFW_WIDTH),
      .X_MISA(32'h0000_0000),
      .X_ECS_XS(2'b00),
      .NUM_MHPMCOUNTERS(1)
  ) u_core (
      .clk_i(clk),
      .rst_ni(rst_n),
      .scan_cg_en_i(1'b0),
      .boot_addr_i(BOOT_ADDR),
      .dm_exception_addr_i(32'hf000_0000),
      .dm_halt_addr_i(32'hf000_0800),
      .mhartid_i(32'd0),
      .mimpid_patch_i(4'd0),
      .mtvec_addr_i(MTVEC_ADDR),
      .instr_req_o(instr_req),
      .instr_gnt_i(instr_gnt),
      .instr_rvalid_i(instr_rvalid),
      .instr_addr_o(instr_addr),
      .instr_memtype_o(instr_memtype),
      .instr_prot_o(instr_prot),
      .instr_dbg_o(instr_dbg),
      .instr_rdata_i(instr_rdata),
      .instr_err_i(instr_err),
      .data_req_o(data_req),
      .data_gnt_i(data_gnt),
      .data_rvalid_i(data_rvalid),
      .data_addr_o(data_addr),
      .data_be_o(data_be),
      .data_we_o(data_we),
      .data_wdata_o(data_wdata),
      .data_memtype_o(data_memtype),
      .data_prot_o(data_prot),
      .data_dbg_o(data_dbg),
      .data_atop_o(data_atop),
      .data_rdata_i(data_rdata),
      .data_err_i(data_err),
      .data_exokay_i(data_exokay),
      .mcycle_o(mcycle),
      .time_i(time_q),
      .xif_compressed_if(xif),
      .xif_issue_if(xif),
      .xif_commit_if(xif),
      .xif_mem_if(xif),
      .xif_mem_result_if(xif),
      .xif_result_if(xif),
      .irq_i(32'd0),
      .wu_wfe_i(1'b0),
      .clic_irq_i(1'b0),
      .clic_irq_id_i('0),
      .clic_irq_level_i(8'd0),
      .clic_irq_priv_i(2'd0),
      .clic_irq_shv_i(1'b0),
      .fencei_flush_req_o(fencei_flush_req),
      .fencei_flush_ack_i(fencei_flush_ack),
      .debug_req_i(1'b0),
      .debug_havereset_o(debug_havereset),
      .debug_running_o(debug_running),
      .debug_halted_o(debug_halted),
      .debug_pc_valid_o(debug_pc_valid),
      .debug_pc_o(debug_pc),
      .fetch_enable_i(fetch_enable),
      .core_sleep_o(core_sleep)
  );

  spx_cvxif_real_adapter u_cvxif_real_adapter (
      .clk(clk),
      .rst_n(rst_n),
      .xif_compressed_if(xif),
      .xif_issue_if(xif),
      .xif_commit_if(xif),
      .xif_mem_if(xif),
      .xif_mem_result_if(xif),
      .xif_result_if(xif),
      .instr_valid(instr_valid),
      .instr_ready(instr_ready),
      .instr_op(instr_op),
      .instr_rs1(instr_rs1),
      .instr_resp_valid(instr_resp_valid),
      .instr_resp_data(instr_resp_data),
      .instr_illegal(instr_illegal)
  );

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

  assign instr_gnt = instr_req;
  assign data_gnt = data_req;
  assign data_exokay = 1'b0;
  assign fencei_flush_ack = fencei_flush_req;

  always_comb begin
    int unsigned latency_cfg;

    latency_cfg = bus_req_we ? bus_write_latency_cfg : bus_read_latency_cfg;
    bus_req_ready = bus_req_valid && !bus_rsp_pending_q && bus_random_ready_ok();

    if (bus_rsp_pending_q) begin
      bus_rsp_valid = (bus_rsp_wait_q == 0);
      bus_rsp_rdata = bus_rsp_rdata_q;
      bus_rsp_error = bus_rsp_error_q;
    end else begin
      bus_rsp_valid = bus_req_valid && bus_req_ready && (latency_cfg == 0);
      bus_rsp_rdata = (bus_req_valid && bus_req_ready && !bus_req_we) ?
                      read_bus_beat(bus_req_addr) : '0;
      bus_rsp_error = (bus_req_valid && bus_req_ready) ?
                      bus_inject_error(bus_req_we) : 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_rvalid <= 1'b0;
      instr_rdata  <= 32'd0;
      instr_err    <= 1'b0;
    end else begin
      instr_rvalid <= instr_req && instr_gnt;
      instr_err    <= 1'b0;
      if (instr_req && instr_gnt) begin
        instr_rdata <= read_word(instr_addr);
      end else begin
        instr_rdata <= 32'd0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_rvalid <= 1'b0;
      data_rdata  <= 32'd0;
      data_err    <= 1'b0;
    end else begin
      data_rvalid <= data_req && data_gnt;
      data_err    <= 1'b0;
      if (data_req && data_gnt) begin
        data_rdata <= read_word(data_addr);
        if (data_we) begin
          write_word(data_addr, data_wdata, data_be);
        end
      end else begin
        data_rdata <= 32'd0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bus_rng_q                <= 32'hc032_0001;
      bus_rsp_pending_q        <= 1'b0;
      bus_rsp_wait_q           <= 0;
      bus_rsp_rdata_q          <= '0;
      bus_rsp_error_q          <= 1'b0;
      bus_read_accept_count_q  <= 0;
      bus_write_accept_count_q <= 0;
      bus_error_kind_q         <= BUS_ERR_NONE;
    end else begin
      int unsigned latency_cfg;
      bit inject_error;

      bus_rng_q <= xorshift32(bus_rng_q);

      if (data_req && data_gnt && data_we &&
          (data_addr == CTRL_ADDR) && (data_be == 4'hf)) begin
        bus_error_kind_q <= int'(data_wdata);
      end

      if (bus_rsp_pending_q) begin
        if (bus_rsp_wait_q != 0) begin
          bus_rsp_wait_q <= bus_rsp_wait_q - 1;
        end else if (bus_rsp_valid) begin
          bus_rsp_pending_q <= 1'b0;
          bus_rsp_error_q   <= 1'b0;
        end
      end

      if (bus_req_valid && bus_req_ready) begin
        latency_cfg = bus_req_we ? bus_write_latency_cfg : bus_read_latency_cfg;
        inject_error = bus_inject_error(bus_req_we);

        if (bus_req_we) begin
          bus_write_accept_count_q <= bus_write_accept_count_q + 1;
          if (!inject_error) begin
            write_bus_beat(bus_req_addr, bus_req_wdata);
          end
        end else begin
          bus_read_accept_count_q <= bus_read_accept_count_q + 1;
        end

        if (inject_error) begin
          bus_error_kind_q <= BUS_ERR_NONE;
        end

        if (latency_cfg != 0) begin
          bus_rsp_pending_q <= 1'b1;
          bus_rsp_wait_q    <= latency_cfg - 1;
          bus_rsp_rdata_q   <= bus_req_we ? '0 : read_bus_beat(bus_req_addr);
          bus_rsp_error_q   <= inject_error;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_q              <= 0;
      instr_fetch_count_q  <= 0;
      data_read_count_q    <= 0;
      data_write_count_q   <= 0;
      xif_issue_count_q    <= 0;
      xif_accept_count_q   <= 0;
      xif_result_count_q   <= 0;
      xif_mem_valid_count_q <= 0;
      desc_control_count_q <= 0;
      bus_read_count_q     <= 0;
      bus_write_count_q    <= 0;
      time_q               <= 64'd0;
    end else begin
      logic [31:0] magic_word;

      cycle_q <= cycle_q + 1;
      time_q  <= time_q + 64'd1;

      if (instr_req && instr_gnt) begin
        instr_fetch_count_q <= instr_fetch_count_q + 1;
      end
      if (data_req && data_gnt) begin
        if (data_we) begin
          data_write_count_q <= data_write_count_q + 1;
        end else begin
          data_read_count_q <= data_read_count_q + 1;
        end
      end
      if (xif.issue_valid && xif.issue_ready) begin
        xif_issue_count_q <= xif_issue_count_q + 1;
        if (xif.issue_resp.accept) begin
          xif_accept_count_q <= xif_accept_count_q + 1;
        end
      end
      if (xif.result_valid && xif.result_ready) begin
        xif_result_count_q <= xif_result_count_q + 1;
      end
      if (instr_valid && instr_ready) begin
        desc_control_count_q <= desc_control_count_q + 1;
      end
      if (bus_req_valid && bus_req_ready) begin
        if (bus_req_we) begin
          bus_write_count_q <= bus_write_count_q + 1;
        end else begin
          bus_read_count_q <= bus_read_count_q + 1;
        end
      end
      if (xif.mem_valid) begin
        xif_mem_valid_count_q <= xif_mem_valid_count_q + 1;
        $fatal(1, "CV-X-IF memory interface was used; descriptor bulk data must stay on memory-side path");
      end

      magic_word = read_word(MAGIC_ADDR);
      if ((magic_word == MAGIC_PASS) || (magic_word == MAGIC_ERROR_PASS)) begin
        logic [31:0] cases_passed;
        logic [31:0] cases_failed;
        logic [31:0] status_poll_count;
        logic [31:0] error_cases_passed;

        cases_passed       = read_word(STATS_ADDR);
        cases_failed       = read_word(STATS_ADDR + 32'd4);
        status_poll_count  = read_word(STATS_ADDR + 32'd8);
        error_cases_passed = read_word(STATS_ADDR + 32'd12);

        if ((magic_word == MAGIC_PASS) &&
            (cases_passed < 32'(2 * smoke_cases_per_inblocks_cfg))) begin
          $fatal(1, "PASS magic observed before expected case count cases_passed=%0d expected=%0d",
                 cases_passed, 2 * smoke_cases_per_inblocks_cfg);
        end
        if (xif_accept_count_q < 8) begin
          $fatal(1, "PASS magic observed before expected XIF traffic count=%0d",
                 xif_accept_count_q);
        end
        if (desc_control_count_q < 8) begin
          $fatal(1, "PASS magic observed before descriptor controls count=%0d",
                 desc_control_count_q);
        end
        if (magic_word == MAGIC_PASS) begin
          $display("PASS cv32e40x_spx_core_smoke read_latency=%0d write_latency=%0d req_ready_pct=%0d cycles=%0d instr_fetch=%0d data_rd=%0d data_wr=%0d xif_issue=%0d xif_accept=%0d xif_result=%0d desc_ctrl=%0d bus_rd=%0d bus_wr=%0d perf_load=%0d perf_core=%0d perf_store=%0d perf_total=%0d cases_passed=%0d cases_failed=%0d status_poll_count=%0d error_cases_passed=%0d",
                   bus_read_latency_cfg, bus_write_latency_cfg, bus_req_ready_pct_cfg,
                   cycle_q, instr_fetch_count_q, data_read_count_q, data_write_count_q,
                   xif_issue_count_q, xif_accept_count_q, xif_result_count_q,
                   desc_control_count_q, bus_read_count_q, bus_write_count_q,
                   perf_load_cycles, perf_core_cycles, perf_store_cycles,
                   perf_total_cycles, cases_passed, cases_failed, status_poll_count,
                   error_cases_passed);
        end else begin
          $display("PASS cv32e40x_spx_core_smoke_error read_latency=%0d write_latency=%0d req_ready_pct=%0d cycles=%0d instr_fetch=%0d data_rd=%0d data_wr=%0d xif_issue=%0d xif_accept=%0d xif_result=%0d desc_ctrl=%0d bus_rd=%0d bus_wr=%0d perf_load=%0d perf_core=%0d perf_store=%0d perf_total=%0d cases_passed=%0d cases_failed=%0d status_poll_count=%0d error_cases_passed=%0d",
                   bus_read_latency_cfg, bus_write_latency_cfg, bus_req_ready_pct_cfg,
                   cycle_q, instr_fetch_count_q, data_read_count_q, data_write_count_q,
                   xif_issue_count_q, xif_accept_count_q, xif_result_count_q,
                   desc_control_count_q, bus_read_count_q, bus_write_count_q,
                   perf_load_cycles, perf_core_cycles, perf_store_cycles,
                   perf_total_cycles, cases_passed, cases_failed, status_poll_count,
                   error_cases_passed);
        end
        $finish;
      end
      if (magic_word == MAGIC_FAIL) begin
        $fatal(1, "FAIL magic observed at 0x%08x cases_passed=%0d cases_failed=%0d status_poll_count=%0d error_cases_passed=%0d",
               MAGIC_ADDR, read_word(STATS_ADDR), read_word(STATS_ADDR + 32'd4),
               read_word(STATS_ADDR + 32'd8), read_word(STATS_ADDR + 32'd12));
      end
      if (cycle_q > TIMEOUT_CYCLES) begin
        $fatal(1, "timeout waiting for PASS magic pc_valid=%0b pc=0x%08x magic=0x%08x xif_accept=%0d desc_status=0x%08x",
               debug_pc_valid, debug_pc, magic_word, xif_accept_count_q, desc_status);
      end
    end
  end

  logic unused_signals;
  assign unused_signals =
      (|instr_memtype) | (|instr_prot) | instr_dbg |
      (|data_memtype) | (|data_prot) | data_dbg | (|data_atop) |
      (|mcycle) | debug_havereset | debug_running | debug_halted |
      debug_pc_valid | (|debug_pc) | core_sleep | desc_busy | desc_done |
      desc_error | mem_valid | mem_we | mem_error | (|mem_addr) |
      (|mem_wdata) | (|mem_rdata) | xif_mem_valid_count_q |
      (|bus_read_accept_count_q) | (|bus_write_accept_count_q);

endmodule
