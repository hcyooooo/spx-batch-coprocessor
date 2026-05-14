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
  localparam logic [31:0] WOTS_VECTOR_TABLE_MAGIC = 32'h5350_5857;
  localparam int WOTS_VECTOR_HEADER_WORDS = 4;
  localparam int WOTS_VECTOR_CASE_WORDS   = 70;
  localparam int WOTS_CASE_START_STEP_WORD = 0;
  localparam int WOTS_CASE_NUM_STEPS_WORD  = 1;
  localparam int WOTS_CASE_PUB_SEED_WORD   = 2;
  localparam int WOTS_CASE_ADDR_WORD       = 6;
  localparam int WOTS_CASE_INPUT_WORD      = 38;
  localparam int WOTS_CASE_EXPECTED_WORD   = 54;
  localparam int DESC_CONFIG_OFFSET        = 4;
  localparam int DESC_CHAIN_CTRL_OFFSET    = 28;
  localparam int DESC_CONFIG_OP_TYPE_LSB   = 16;
  localparam int DESC_CHAIN_NUM_STEPS_LSB  = 8;
  localparam int BUS_ERR_NONE       = 0;
  localparam int BUS_ERR_READ_ONCE  = 1;
  localparam int BUS_ERR_WRITE_ONCE = 2;
  localparam int DESC_DONE_TIMEOUT_CYCLES = 20000;
  localparam int XIF_RESULT_TIMEOUT_CYCLES = 2000;

  localparam logic [6:0] SPX_OPCODE_CUSTOM0 = 7'b0001011;
  localparam logic [6:0] SPX_FUNCT7         = 7'h5a;
  localparam logic [2:0] SPX_F3_SET_DESC    = 3'h0;
  localparam logic [2:0] SPX_F3_START       = 3'h1;
  localparam logic [2:0] SPX_F3_STATUS      = 3'h2;
  localparam logic [2:0] SPX_F3_CLEAR       = 3'h3;

  localparam int XIF_OP_SET_DESC = 0;
  localparam int XIF_OP_START    = 1;
  localparam int XIF_OP_STATUS   = 2;
  localparam int XIF_OP_CLEAR    = 3;
  localparam int XIF_OP_COUNT    = 4;
  localparam int XIF_OP_UNKNOWN  = 4;
  localparam int XIF_IDS         = 1 << X_ID_WIDTH;

  localparam int STATUS_DONE_BIT  = 1;
  localparam int STATUS_ERROR_BIT = 2;

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
  int unsigned expected_case_count_cfg;
  logic [31:0] bus_rng_q;
  logic        bus_rsp_pending_q;
  logic [MEM_DATA_WIDTH-1:0] bus_rsp_rdata_q;
  logic        bus_rsp_error_q;
  bit          wots_chain_smoke_cfg;
  string       smoke_mode_cfg;

  logic        xif_outstanding_q [0:XIF_IDS-1];
  logic        xif_committed_q [0:XIF_IDS-1];
  int unsigned xif_outstanding_op_q [0:XIF_IDS-1];
  int unsigned xif_issue_cycle_q [0:XIF_IDS-1];
  int unsigned xif_commit_cycle_q [0:XIF_IDS-1];

  int unsigned xif_latency_count_q [0:XIF_OP_COUNT-1];
  int unsigned xif_issue_commit_min_q [0:XIF_OP_COUNT-1];
  int unsigned xif_issue_commit_max_q [0:XIF_OP_COUNT-1];
  longint unsigned xif_issue_commit_sum_q [0:XIF_OP_COUNT-1];
  int unsigned xif_commit_result_min_q [0:XIF_OP_COUNT-1];
  int unsigned xif_commit_result_max_q [0:XIF_OP_COUNT-1];
  longint unsigned xif_commit_result_sum_q [0:XIF_OP_COUNT-1];
  int unsigned xif_issue_result_min_q [0:XIF_OP_COUNT-1];
  int unsigned xif_issue_result_max_q [0:XIF_OP_COUNT-1];
  longint unsigned xif_issue_result_sum_q [0:XIF_OP_COUNT-1];

  logic        case_active_q;
  logic        case_done_seen_q;
  logic        case_pass_q;
  int unsigned case_next_id_q;
  int unsigned case_active_id_q;
  int unsigned case_inblocks_q;
  int unsigned case_op_type_q;
  int unsigned case_num_steps_q;
  int unsigned case_start_cycle_q;
  int unsigned case_done_cycle_q;
  int unsigned case_xif_count_q;
  int unsigned case_status_polls_q;
  int unsigned case_bus_rd_q;
  int unsigned case_bus_wr_q;

  int unsigned case_perf_count_q;
  int unsigned case_fail_count_q;
  longint unsigned case_cycles_sum_q;
  longint unsigned case_status_polls_sum_q;
  longint unsigned case_xif_sum_q;
  longint unsigned case_bus_rd_sum_q;
  longint unsigned case_bus_wr_sum_q;
  longint unsigned case_perf_total_sum_q;
  longint unsigned case_wait_saved_sum_q;
  longint unsigned case_irq_saved_sum_q;

  int unsigned wots_perf_count_q [0:15];
  longint unsigned wots_cycles_sum_q [0:15];
  longint unsigned wots_status_polls_sum_q [0:15];
  longint unsigned wots_xif_sum_q [0:15];
  longint unsigned wots_bus_rd_sum_q [0:15];
  longint unsigned wots_bus_wr_sum_q [0:15];
  longint unsigned wots_perf_total_sum_q [0:15];

  logic        desc_watch_active_q;
  logic        desc_done_prev_q;
  int unsigned desc_watch_case_id_q;
  int unsigned desc_watch_start_cycle_q;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    bus_read_latency_cfg      = 0;
    bus_write_latency_cfg     = 0;
    bus_req_ready_pct_cfg     = 100;
    smoke_cases_per_inblocks_cfg = DEFAULT_CASES_PER_INBLOCKS;
    expected_case_count_cfg   = 2 * DEFAULT_CASES_PER_INBLOCKS;
    wots_chain_smoke_cfg      = $test$plusargs("WOTS_CHAIN_SMOKE");

    void'($value$plusargs("SMOKE_READ_LATENCY=%d", bus_read_latency_cfg));
    void'($value$plusargs("SMOKE_WRITE_LATENCY=%d", bus_write_latency_cfg));
    void'($value$plusargs("SMOKE_REQ_READY_PCT=%d", bus_req_ready_pct_cfg));
    if (bus_req_ready_pct_cfg > 100) begin
      bus_req_ready_pct_cfg = 100;
    end
    if (!$value$plusargs("SMOKE_MODE=%s", smoke_mode_cfg)) begin
      if ((bus_read_latency_cfg == 0) && (bus_write_latency_cfg == 0) &&
          (bus_req_ready_pct_cfg == 100)) begin
        smoke_mode_cfg = "zero_wait";
      end else if ((bus_read_latency_cfg == 1) && (bus_write_latency_cfg == 1) &&
                   (bus_req_ready_pct_cfg == 100)) begin
        smoke_mode_cfg = "wait1";
      end else if ((bus_read_latency_cfg == 2) && (bus_write_latency_cfg == 2) &&
                   (bus_req_ready_pct_cfg == 100)) begin
        smoke_mode_cfg = "wait2";
      end else if ((bus_read_latency_cfg == 2) && (bus_write_latency_cfg == 4) &&
                   (bus_req_ready_pct_cfg == 100)) begin
        smoke_mode_cfg = "split";
      end else if ((bus_read_latency_cfg == 0) && (bus_write_latency_cfg == 0) &&
                   (bus_req_ready_pct_cfg == 50)) begin
        smoke_mode_cfg = "random50";
      end else if ((bus_read_latency_cfg == 0) && (bus_write_latency_cfg == 0) &&
                   (bus_req_ready_pct_cfg == 75)) begin
        smoke_mode_cfg = "random75";
      end else begin
        smoke_mode_cfg = "custom";
      end
    end
  end

  initial begin
    string smoke_hex;
    string vectors_ib1;
    string vectors_ib2;
    string expected_vectors;
    string wots_vectors;

    for (int i = 0; i < MEM_BYTES; i++) begin
      memory[i] = 8'h00;
    end

    if (!$value$plusargs("SMOKE_HEX=%s", smoke_hex)) begin
      smoke_hex = "build/spx_cvxif_smoke.hex";
    end
    $display("Loading CV32E40X smoke image: %s", smoke_hex);
    $readmemh(smoke_hex, memory);

    if (wots_chain_smoke_cfg) begin
      if (!$value$plusargs("WOTS_VECTORS=%s", wots_vectors)) begin
        wots_vectors = "vectors/wots_chainx4_vectors.hex";
      end
      load_wots_vector_table(wots_vectors);
    end else begin
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
      expected_case_count_cfg = 2 * smoke_cases_per_inblocks_cfg;
      load_smoke_vector_table(vectors_ib1, vectors_ib2, expected_vectors,
                              smoke_cases_per_inblocks_cfg);
    end
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

  function automatic int unsigned decode_xif_op(input logic [31:0] instr);
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [6:0] funct7;
    begin
      opcode = instr[6:0];
      funct3 = instr[14:12];
      rs1    = instr[19:15];
      rs2    = instr[24:20];
      funct7 = instr[31:25];

      decode_xif_op = XIF_OP_UNKNOWN;
      if ((opcode == SPX_OPCODE_CUSTOM0) && (funct7 == SPX_FUNCT7) &&
          (rs2 == 5'd0)) begin
        unique case (funct3)
          SPX_F3_SET_DESC: begin
            decode_xif_op = XIF_OP_SET_DESC;
          end
          SPX_F3_START: begin
            if (rs1 == 5'd0) begin
              decode_xif_op = XIF_OP_START;
            end
          end
          SPX_F3_STATUS: begin
            if (rs1 == 5'd0) begin
              decode_xif_op = XIF_OP_STATUS;
            end
          end
          SPX_F3_CLEAR: begin
            if (rs1 == 5'd0) begin
              decode_xif_op = XIF_OP_CLEAR;
            end
          end
          default: begin
            decode_xif_op = XIF_OP_UNKNOWN;
          end
        endcase
      end
    end
  endfunction

  function automatic string xif_op_name(input int unsigned op);
    begin
      unique case (op)
        XIF_OP_SET_DESC: xif_op_name = "SPX_SET_DESC";
        XIF_OP_START:    xif_op_name = "SPX_START";
        XIF_OP_STATUS:   xif_op_name = "SPX_STATUS";
        XIF_OP_CLEAR:    xif_op_name = "SPX_CLEAR";
        default:         xif_op_name = "UNKNOWN";
      endcase
    end
  endfunction

  task automatic print_xif_latency_summary;
    real issue_commit_avg;
    real commit_result_avg;
    real issue_result_avg;
    begin
      for (int op = 0; op < XIF_OP_COUNT; op++) begin
        if (xif_latency_count_q[op] == 0) begin
          $display("XIF_LATENCY type=%s count=0 issue_commit_min=0 issue_commit_max=0 issue_commit_avg=0.00 commit_result_min=0 commit_result_max=0 commit_result_avg=0.00 issue_result_min=0 issue_result_max=0 issue_result_avg=0.00",
                   xif_op_name(op));
        end else begin
          issue_commit_avg = real'(xif_issue_commit_sum_q[op]) /
                             real'(xif_latency_count_q[op]);
          commit_result_avg = real'(xif_commit_result_sum_q[op]) /
                              real'(xif_latency_count_q[op]);
          issue_result_avg = real'(xif_issue_result_sum_q[op]) /
                             real'(xif_latency_count_q[op]);
          $display("XIF_LATENCY type=%s count=%0d issue_commit_min=%0d issue_commit_max=%0d issue_commit_avg=%0.2f commit_result_min=%0d commit_result_max=%0d commit_result_avg=%0.2f issue_result_min=%0d issue_result_max=%0d issue_result_avg=%0.2f",
                   xif_op_name(op), xif_latency_count_q[op],
                   xif_issue_commit_min_q[op], xif_issue_commit_max_q[op],
                   issue_commit_avg,
                   xif_commit_result_min_q[op], xif_commit_result_max_q[op],
                   commit_result_avg,
                   xif_issue_result_min_q[op], xif_issue_result_max_q[op],
                   issue_result_avg);
        end
      end
    end
  endtask

  task automatic print_core_smoke_perf_summary;
    real avg_cycles;
    real avg_status_polls;
    real avg_xif_instr;
    real avg_bus_rd;
    real avg_bus_wr;
    real avg_perf_total;
    real cycles_per_thash_equiv;
    real avg_wait_saved;
    real avg_irq_saved;
    begin
      if (case_perf_count_q == 0) begin
        $display("CORE_SMOKE_PERF_SUMMARY mode=%s cases=0 avg_cycles_per_case=0.00 avg_status_polls=0.00 avg_xif_instr=0.00 avg_bus_rd=0.00 avg_bus_wr=0.00 avg_perf_total=0.00 effective_thash_per_case=4 cycles_per_thash_equiv=0.00 estimated_speedup_basis=polling_status_to_wait avg_wait_saved_instr=0.00 avg_irq_saved_instr=0.00",
                 smoke_mode_cfg);
      end else begin
        avg_cycles = real'(case_cycles_sum_q) / real'(case_perf_count_q);
        avg_status_polls = real'(case_status_polls_sum_q) / real'(case_perf_count_q);
        avg_xif_instr = real'(case_xif_sum_q) / real'(case_perf_count_q);
        avg_bus_rd = real'(case_bus_rd_sum_q) / real'(case_perf_count_q);
        avg_bus_wr = real'(case_bus_wr_sum_q) / real'(case_perf_count_q);
        avg_perf_total = real'(case_perf_total_sum_q) / real'(case_perf_count_q);
        cycles_per_thash_equiv = avg_cycles / 4.0;
        avg_wait_saved = real'(case_wait_saved_sum_q) / real'(case_perf_count_q);
        avg_irq_saved = real'(case_irq_saved_sum_q) / real'(case_perf_count_q);

        $display("CORE_SMOKE_PERF_SUMMARY mode=%s cases=%0d avg_cycles_per_case=%0.2f avg_status_polls=%0.2f avg_xif_instr=%0.2f avg_bus_rd=%0.2f avg_bus_wr=%0.2f avg_perf_total=%0.2f effective_thash_per_case=4 cycles_per_thash_equiv=%0.2f estimated_speedup_basis=polling_status_to_wait avg_wait_saved_instr=%0.2f avg_irq_saved_instr=%0.2f",
                 smoke_mode_cfg, case_perf_count_q, avg_cycles,
                 avg_status_polls, avg_xif_instr, avg_bus_rd, avg_bus_wr,
                 avg_perf_total, cycles_per_thash_equiv, avg_wait_saved,
                 avg_irq_saved);
      end
    end
  endtask

  task automatic print_wots_chain_perf_summary;
    real avg_cycles;
    real avg_xif;
    real avg_polls;
    real avg_bus_rd;
    real avg_bus_wr;
    real avg_perf_total;
    real speedup;
    int baseline_cycles;
    begin
      if (!wots_chain_smoke_cfg) begin
        return;
      end

      $display("WOTS_CHAIN_CORE_PERF_TABLE mode=%s", smoke_mode_cfg);
      $display("num_steps  baseline_descriptor_thashx4_cycles  wots_chain_core_cycles  speedup  xif_instr  status_polls  bus_rd  bus_wr  desc_perf_total");
      $display("--------------------------------------------------------------------------------------------------------------------------------");

      for (int steps = 1; steps < 16; steps++) begin
        if (wots_perf_count_q[steps] != 0) begin
          baseline_cycles = 57 * steps;
          avg_cycles = real'(wots_cycles_sum_q[steps]) /
                       real'(wots_perf_count_q[steps]);
          avg_xif = real'(wots_xif_sum_q[steps]) /
                    real'(wots_perf_count_q[steps]);
          avg_polls = real'(wots_status_polls_sum_q[steps]) /
                      real'(wots_perf_count_q[steps]);
          avg_bus_rd = real'(wots_bus_rd_sum_q[steps]) /
                       real'(wots_perf_count_q[steps]);
          avg_bus_wr = real'(wots_bus_wr_sum_q[steps]) /
                       real'(wots_perf_count_q[steps]);
          avg_perf_total = real'(wots_perf_total_sum_q[steps]) /
                           real'(wots_perf_count_q[steps]);
          speedup = real'(baseline_cycles) / avg_cycles;

          $display("%9d %34d %23.2f %8.2fx %10.2f %13.2f %7.2f %7.2f %15.2f",
                   steps, baseline_cycles, avg_cycles, speedup, avg_xif,
                   avg_polls, avg_bus_rd, avg_bus_wr, avg_perf_total);
        end
      end
    end
  endtask

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

  task automatic write_wots_vector_case(
      input int case_index,
      input int start_step,
      input int num_steps,
      input logic [127:0] pub_seed,
      input logic [255:0] addr0,
      input logic [255:0] addr1,
      input logic [255:0] addr2,
      input logic [255:0] addr3,
      input logic [127:0] in0,
      input logic [127:0] in1,
      input logic [127:0] in2,
      input logic [127:0] in3,
      input logic [127:0] exp0,
      input logic [127:0] exp1,
      input logic [127:0] exp2,
      input logic [127:0] exp3
  );
    int base_word;
    begin
      base_word = WOTS_VECTOR_HEADER_WORDS + case_index * WOTS_VECTOR_CASE_WORDS;
      write_table_word(base_word + WOTS_CASE_START_STEP_WORD, 32'(start_step));
      write_table_word(base_word + WOTS_CASE_NUM_STEPS_WORD, 32'(num_steps));

      for (int word = 0; word < 4; word++) begin
        write_table_word(base_word + WOTS_CASE_PUB_SEED_WORD + word,
                         pub_seed[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_INPUT_WORD + word,
                         in0[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_INPUT_WORD + 4 + word,
                         in1[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_INPUT_WORD + 8 + word,
                         in2[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_INPUT_WORD + 12 + word,
                         in3[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_EXPECTED_WORD + word,
                         exp0[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_EXPECTED_WORD + 4 + word,
                         exp1[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_EXPECTED_WORD + 8 + word,
                         exp2[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_EXPECTED_WORD + 12 + word,
                         exp3[32 * word +: 32]);
      end

      for (int word = 0; word < 8; word++) begin
        write_table_word(base_word + WOTS_CASE_ADDR_WORD + word,
                         addr0[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_ADDR_WORD + 8 + word,
                         addr1[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_ADDR_WORD + 16 + word,
                         addr2[32 * word +: 32]);
        write_table_word(base_word + WOTS_CASE_ADDR_WORD + 24 + word,
                         addr3[32 * word +: 32]);
      end
    end
  endtask

  task automatic load_wots_vector_table(input string vectors_path);
    int fd;
    int rc;
    int num_cases;
    int case_id_file;
    int start_step_i;
    int num_steps_i;
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
    begin
      fd = $fopen(vectors_path, "r");
      if (fd == 0) begin
        $fatal(1, "failed to open %s", vectors_path);
      end

      rc = $fscanf(fd, "%d", num_cases);
      if (rc != 1) begin
        $fatal(1, "failed to read WOTS vector count from %s", vectors_path);
      end

      write_table_word(0, WOTS_VECTOR_TABLE_MAGIC);
      write_table_word(1, 32'(num_cases));
      write_table_word(2, 32'(WOTS_VECTOR_CASE_WORDS));
      write_table_word(3, 32'd0);
      expected_case_count_cfg = num_cases;

      for (int case_id = 0; case_id < num_cases; case_id++) begin
        rc = $fscanf(fd, "%d %d %d %h %h %h %h %h %h %h %h %h %h %h %h %h",
                     case_id_file, start_step_i, num_steps_i, pub_seed,
                     addr0, addr1, addr2, addr3,
                     in0, in1, in2, in3,
                     exp0, exp1, exp2, exp3);
        if (rc != 16) begin
          $fatal(1, "failed to read WOTS case %0d from %s",
                 case_id, vectors_path);
        end
        if (case_id_file != case_id) begin
          $fatal(1, "WOTS case id mismatch expected=%0d got=%0d",
                 case_id, case_id_file);
        end
        write_wots_vector_case(case_id, start_step_i, num_steps_i,
                               pub_seed, addr0, addr1, addr2, addr3,
                               in0, in1, in2, in3,
                               exp0, exp1, exp2, exp3);
      end

      $fclose(fd);
      $display("Loaded CV32E40X WOTS chain vector table: cases=%0d case_words=%0d",
               num_cases, WOTS_VECTOR_CASE_WORDS);
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
      cycle_q               <= 0;
      instr_fetch_count_q   <= 0;
      data_read_count_q     <= 0;
      data_write_count_q    <= 0;
      xif_issue_count_q     <= 0;
      xif_accept_count_q    <= 0;
      xif_result_count_q    <= 0;
      xif_mem_valid_count_q <= 0;
      desc_control_count_q  <= 0;
      bus_read_count_q      <= 0;
      bus_write_count_q     <= 0;
      time_q                <= 64'd0;

      for (int id = 0; id < XIF_IDS; id++) begin
        xif_outstanding_q[id]       <= 1'b0;
        xif_committed_q[id]         <= 1'b0;
        xif_outstanding_op_q[id]    <= XIF_OP_UNKNOWN;
        xif_issue_cycle_q[id]       <= 0;
        xif_commit_cycle_q[id]      <= 0;
      end

      for (int op = 0; op < XIF_OP_COUNT; op++) begin
        xif_latency_count_q[op]        <= 0;
        xif_issue_commit_min_q[op]     <= 32'hffff_ffff;
        xif_issue_commit_max_q[op]     <= 0;
        xif_issue_commit_sum_q[op]     <= 0;
        xif_commit_result_min_q[op]    <= 32'hffff_ffff;
        xif_commit_result_max_q[op]    <= 0;
        xif_commit_result_sum_q[op]    <= 0;
        xif_issue_result_min_q[op]     <= 32'hffff_ffff;
        xif_issue_result_max_q[op]     <= 0;
        xif_issue_result_sum_q[op]     <= 0;
      end

	      case_active_q             <= 1'b0;
	      case_done_seen_q          <= 1'b0;
	      case_pass_q               <= 1'b0;
	      case_next_id_q            <= 0;
	      case_active_id_q          <= 0;
	      case_inblocks_q           <= 0;
	      case_op_type_q            <= 0;
	      case_num_steps_q          <= 0;
	      case_start_cycle_q        <= 0;
      case_done_cycle_q         <= 0;
      case_xif_count_q          <= 0;
      case_status_polls_q       <= 0;
      case_bus_rd_q             <= 0;
      case_bus_wr_q             <= 0;
      case_perf_count_q         <= 0;
      case_fail_count_q         <= 0;
      case_cycles_sum_q         <= 0;
      case_status_polls_sum_q   <= 0;
      case_xif_sum_q            <= 0;
      case_bus_rd_sum_q         <= 0;
      case_bus_wr_sum_q         <= 0;
      case_perf_total_sum_q     <= 0;
      case_wait_saved_sum_q     <= 0;
      case_irq_saved_sum_q      <= 0;

	      desc_watch_active_q       <= 1'b0;
	      desc_done_prev_q          <= 1'b0;
	      desc_watch_case_id_q      <= 0;
	      desc_watch_start_cycle_q  <= 0;

	      for (int steps = 0; steps < 16; steps++) begin
	        wots_perf_count_q[steps]        <= 0;
	        wots_cycles_sum_q[steps]        <= 0;
	        wots_status_polls_sum_q[steps]  <= 0;
	        wots_xif_sum_q[steps]           <= 0;
	        wots_bus_rd_sum_q[steps]        <= 0;
	        wots_bus_wr_sum_q[steps]        <= 0;
	        wots_perf_total_sum_q[steps]    <= 0;
	      end
	    end else begin
	      logic [31:0] magic_word;
	      logic [31:0] desc_config_word;
	      logic [31:0] desc_chain_ctrl_word;
	      logic        xif_issue_fire;
      logic        xif_accept_fire;
      logic        xif_commit_fire;
      logic        xif_result_fire;
      int unsigned issue_id;
      int unsigned issue_op;
      int unsigned commit_id;
      int unsigned result_id;
      int unsigned result_op;
      int unsigned issue_commit_latency;
      int unsigned commit_result_latency;
      int unsigned issue_result_latency;
      int unsigned case_total_cycles;
      int unsigned case_wait_saved_instr;
      int unsigned case_irq_saved_instr;
      real         case_poll_instr_pct;

      xif_issue_fire  = xif.issue_valid && xif.issue_ready;
      xif_accept_fire = xif_issue_fire && xif.issue_resp.accept;
      xif_commit_fire = xif.commit_valid;
      xif_result_fire = xif.result_valid && xif.result_ready;
      issue_id        = int'(xif.issue_req.id);
      issue_op        = XIF_OP_UNKNOWN;
      commit_id       = int'(xif.commit.id);
      result_id       = int'(xif.result.id);
      result_op       = XIF_OP_UNKNOWN;

      if (xif.issue_valid) begin
        issue_op = decode_xif_op(xif.issue_req.instr);
      end

      cycle_q <= cycle_q + 1;
      time_q  <= time_q + 64'd1;
      desc_done_prev_q <= desc_done;

      if ($isunknown({desc_busy, desc_done, desc_error, desc_status,
                      instr_valid, instr_ready, instr_resp_valid,
                      instr_illegal})) begin
        $fatal(1, "unknown X/Z on descriptor status/result monitor signals cycle=%0d",
               cycle_q);
      end
      if (instr_resp_valid && $isunknown(instr_resp_data)) begin
        $fatal(1, "unknown X/Z on descriptor response data cycle=%0d", cycle_q);
      end
      if ($isunknown({xif.issue_valid, xif.issue_ready, xif.result_valid,
                      xif.result_ready, xif.commit_valid, xif.mem_valid})) begin
        $fatal(1, "unknown X/Z on CV-X-IF handshake signals cycle=%0d", cycle_q);
      end
      if (xif.issue_valid &&
          $isunknown({xif.issue_req.instr, xif.issue_req.id,
                      xif.issue_resp.accept, xif.issue_resp.writeback,
                      xif.issue_resp.exc})) begin
        $fatal(1, "unknown X/Z on CV-X-IF issue signals cycle=%0d", cycle_q);
      end
      if (xif.commit_valid &&
          $isunknown({xif.commit.id, xif.commit.commit_kill})) begin
        $fatal(1, "unknown X/Z on CV-X-IF commit signals cycle=%0d", cycle_q);
      end
      if (xif.result_valid &&
          $isunknown({xif.result.id, xif.result.data, xif.result.rd,
                      xif.result.we, xif.result.exc, xif.result.err,
                      xif.result.dbg})) begin
        $fatal(1, "unknown X/Z on CV-X-IF result signals cycle=%0d", cycle_q);
      end

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
          if (case_active_q) begin
            case_bus_wr_q <= case_bus_wr_q + 1;
          end
        end else begin
          bus_read_count_q <= bus_read_count_q + 1;
          if (case_active_q) begin
            case_bus_rd_q <= case_bus_rd_q + 1;
          end
        end
      end
      if (xif.mem_valid) begin
        xif_mem_valid_count_q <= xif_mem_valid_count_q + 1;
        $fatal(1, "CV-X-IF memory interface was used; descriptor bulk data must stay on memory-side path");
      end

      if (xif_accept_fire) begin
        if (issue_op == XIF_OP_UNKNOWN) begin
          $fatal(1, "accepted unknown CV-X-IF instruction instr=0x%08x cycle=%0d",
                 xif.issue_req.instr, cycle_q);
        end
        if (xif_outstanding_q[issue_id]) begin
          $fatal(1, "accepted CV-X-IF id reused before result id=%0d cycle=%0d",
                 issue_id, cycle_q);
        end
        xif_outstanding_q[issue_id]    <= 1'b1;
        xif_committed_q[issue_id]      <= 1'b0;
        xif_outstanding_op_q[issue_id] <= issue_op;
        xif_issue_cycle_q[issue_id]    <= cycle_q;
        xif_commit_cycle_q[issue_id]   <= 0;

        if (!case_active_q) begin
          case_active_q       <= 1'b1;
          case_done_seen_q    <= 1'b0;
          case_pass_q         <= 1'b0;
	          case_active_id_q    <= case_next_id_q;
	          case_next_id_q      <= case_next_id_q + 1;
	          case_inblocks_q     <= 0;
	          case_op_type_q      <= 0;
	          case_num_steps_q    <= 0;
	          case_start_cycle_q  <= 0;
          case_done_cycle_q   <= 0;
          case_xif_count_q    <= 1;
          case_status_polls_q <= (issue_op == XIF_OP_STATUS) ? 1 : 0;
          case_bus_rd_q       <= 0;
          case_bus_wr_q       <= 0;
        end else begin
          case_xif_count_q <= case_xif_count_q + 1;
          if (issue_op == XIF_OP_STATUS) begin
            case_status_polls_q <= case_status_polls_q + 1;
          end
        end
      end

      if (xif_commit_fire) begin
        if (!xif_outstanding_q[commit_id]) begin
          $fatal(1, "CV-X-IF commit without accepted issue id=%0d cycle=%0d",
                 commit_id, cycle_q);
        end
        if (xif_committed_q[commit_id]) begin
          $fatal(1, "duplicate CV-X-IF commit id=%0d cycle=%0d",
                 commit_id, cycle_q);
        end
        if (xif.commit.commit_kill) begin
          $fatal(1, "accepted CV-X-IF instruction was commit-killed id=%0d cycle=%0d",
                 commit_id, cycle_q);
        end
        xif_committed_q[commit_id]    <= 1'b1;
        xif_commit_cycle_q[commit_id] <= cycle_q;
      end

      if (xif_result_fire) begin
        if (!xif_outstanding_q[result_id]) begin
          $fatal(1, "CV-X-IF result without accepted issue id=%0d cycle=%0d",
                 result_id, cycle_q);
        end
        if (!xif_committed_q[result_id]) begin
          $fatal(1, "CV-X-IF result before commit id=%0d cycle=%0d",
                 result_id, cycle_q);
        end

        result_op = xif_outstanding_op_q[result_id];
        issue_commit_latency = xif_commit_cycle_q[result_id] -
                               xif_issue_cycle_q[result_id];
        commit_result_latency = cycle_q - xif_commit_cycle_q[result_id];
        issue_result_latency = cycle_q - xif_issue_cycle_q[result_id];

        if (result_op < XIF_OP_COUNT) begin
          xif_latency_count_q[result_op] <= xif_latency_count_q[result_op] + 1;
          xif_issue_commit_sum_q[result_op] <=
              xif_issue_commit_sum_q[result_op] + issue_commit_latency;
          xif_commit_result_sum_q[result_op] <=
              xif_commit_result_sum_q[result_op] + commit_result_latency;
          xif_issue_result_sum_q[result_op] <=
              xif_issue_result_sum_q[result_op] + issue_result_latency;

          if (issue_commit_latency < xif_issue_commit_min_q[result_op]) begin
            xif_issue_commit_min_q[result_op] <= issue_commit_latency;
          end
          if (issue_commit_latency > xif_issue_commit_max_q[result_op]) begin
            xif_issue_commit_max_q[result_op] <= issue_commit_latency;
          end
          if (commit_result_latency < xif_commit_result_min_q[result_op]) begin
            xif_commit_result_min_q[result_op] <= commit_result_latency;
          end
          if (commit_result_latency > xif_commit_result_max_q[result_op]) begin
            xif_commit_result_max_q[result_op] <= commit_result_latency;
          end
          if (issue_result_latency < xif_issue_result_min_q[result_op]) begin
            xif_issue_result_min_q[result_op] <= issue_result_latency;
          end
          if (issue_result_latency > xif_issue_result_max_q[result_op]) begin
            xif_issue_result_max_q[result_op] <= issue_result_latency;
          end
        end

        if ((result_op == XIF_OP_STATUS) && case_active_q &&
            !case_done_seen_q && xif.result.data[STATUS_DONE_BIT]) begin
          case_done_seen_q  <= 1'b1;
          case_done_cycle_q <= cycle_q;
          case_pass_q       <= !xif.result.data[STATUS_ERROR_BIT];
        end

        if ((result_op == XIF_OP_CLEAR) && case_active_q && case_done_seen_q) begin
          case_total_cycles = (case_done_cycle_q >= case_start_cycle_q) ?
                              (case_done_cycle_q - case_start_cycle_q) : 0;
          case_wait_saved_instr = (case_status_polls_q > 0) ?
                                  (case_status_polls_q - 1) : 0;
          case_irq_saved_instr = case_status_polls_q;
          case_poll_instr_pct = (case_xif_count_q == 0) ? 0.0 :
                                (100.0 * real'(case_status_polls_q) /
                                 real'(case_xif_count_q));

	          $display("CASE_PERF id=%0d op_type=%0d inblocks=%0d num_steps=%0d start_cycle=%0d done_cycle=%0d cycles=%0d polls=%0d xif=%0d bus_rd=%0d bus_wr=%0d load=%0d core=%0d store=%0d total=%0d pass=%0d",
	                   case_active_id_q, case_op_type_q, case_inblocks_q,
	                   case_num_steps_q, case_start_cycle_q, case_done_cycle_q,
	                   case_total_cycles, case_status_polls_q, case_xif_count_q,
	                   case_bus_rd_q, case_bus_wr_q, perf_load_cycles,
	                   perf_core_cycles, perf_store_cycles, perf_total_cycles,
	                   case_pass_q);
	          $display("POLL_PERF id=%0d status=%0d start_to_done_cycles=%0d poll_instr_pct=%0.1f wait_saved_instr=%0d irq_saved_instr=%0d",
	                   case_active_id_q, case_status_polls_q, case_total_cycles,
	                   case_poll_instr_pct, case_wait_saved_instr,
	                   case_irq_saved_instr);

	          if (wots_chain_smoke_cfg && (case_num_steps_q < 16)) begin
	            wots_perf_count_q[case_num_steps_q] <=
	                wots_perf_count_q[case_num_steps_q] + 1;
	            wots_cycles_sum_q[case_num_steps_q] <=
	                wots_cycles_sum_q[case_num_steps_q] + case_total_cycles;
	            wots_status_polls_sum_q[case_num_steps_q] <=
	                wots_status_polls_sum_q[case_num_steps_q] + case_status_polls_q;
	            wots_xif_sum_q[case_num_steps_q] <=
	                wots_xif_sum_q[case_num_steps_q] + case_xif_count_q;
	            wots_bus_rd_sum_q[case_num_steps_q] <=
	                wots_bus_rd_sum_q[case_num_steps_q] + case_bus_rd_q;
	            wots_bus_wr_sum_q[case_num_steps_q] <=
	                wots_bus_wr_sum_q[case_num_steps_q] + case_bus_wr_q;
	            wots_perf_total_sum_q[case_num_steps_q] <=
	                wots_perf_total_sum_q[case_num_steps_q] + perf_total_cycles;
	            $display("WOTS_CHAIN_CORE_PERF num_steps=%0d cycles=%0d xif=%0d status_polls=%0d bus_rd=%0d bus_wr=%0d desc_perf_total=%0d",
	                     case_num_steps_q, case_total_cycles, case_xif_count_q,
	                     case_status_polls_q, case_bus_rd_q, case_bus_wr_q,
	                     perf_total_cycles);
	          end

          case_perf_count_q       <= case_perf_count_q + 1;
          if (!case_pass_q) begin
            case_fail_count_q <= case_fail_count_q + 1;
          end
          case_cycles_sum_q       <= case_cycles_sum_q + case_total_cycles;
          case_status_polls_sum_q <= case_status_polls_sum_q + case_status_polls_q;
          case_xif_sum_q          <= case_xif_sum_q + case_xif_count_q;
          case_bus_rd_sum_q       <= case_bus_rd_sum_q + case_bus_rd_q;
          case_bus_wr_sum_q       <= case_bus_wr_sum_q + case_bus_wr_q;
          case_perf_total_sum_q   <= case_perf_total_sum_q + perf_total_cycles;
          case_wait_saved_sum_q   <= case_wait_saved_sum_q + case_wait_saved_instr;
          case_irq_saved_sum_q    <= case_irq_saved_sum_q + case_irq_saved_instr;

          case_active_q           <= 1'b0;
          case_done_seen_q        <= 1'b0;
	          case_pass_q             <= 1'b0;
	          case_op_type_q          <= 0;
	          case_num_steps_q        <= 0;
	          case_xif_count_q        <= 0;
          case_status_polls_q     <= 0;
          case_bus_rd_q           <= 0;
          case_bus_wr_q           <= 0;
        end

        xif_outstanding_q[result_id]    <= 1'b0;
        xif_committed_q[result_id]      <= 1'b0;
        xif_outstanding_op_q[result_id] <= XIF_OP_UNKNOWN;
        xif_issue_cycle_q[result_id]    <= 0;
        xif_commit_cycle_q[result_id]   <= 0;
      end

	      if (desc_start) begin
	        if (desc_watch_active_q) begin
	          $fatal(1, "descriptor start observed while prior descriptor still active case_id=%0d cycle=%0d",
	                 desc_watch_case_id_q, cycle_q);
	        end
	        desc_config_word = read_word(desc_addr + 32'(DESC_CONFIG_OFFSET));
	        desc_chain_ctrl_word = read_word(desc_addr + 32'(DESC_CHAIN_CTRL_OFFSET));
	        desc_watch_active_q      <= 1'b1;
	        desc_watch_start_cycle_q <= cycle_q;
	        desc_watch_case_id_q     <= case_active_id_q;
	        case_start_cycle_q       <= cycle_q;
	        case_inblocks_q          <= int'(desc_config_word & 32'h3);
	        case_op_type_q           <= int'((desc_config_word >> DESC_CONFIG_OP_TYPE_LSB) &
	                                         32'hff);
	        case_num_steps_q         <= int'((desc_chain_ctrl_word >>
	                                         DESC_CHAIN_NUM_STEPS_LSB) & 32'hff);
	      end

      if (desc_done && !desc_done_prev_q) begin
        desc_watch_active_q <= 1'b0;
      end

      if (desc_watch_active_q &&
          ((cycle_q - desc_watch_start_cycle_q) > DESC_DONE_TIMEOUT_CYCLES)) begin
        $fatal(1, "descriptor timeout case_id=%0d start_cycle=%0d cycle=%0d status=0x%08x",
               desc_watch_case_id_q, desc_watch_start_cycle_q, cycle_q,
               desc_status);
      end

      for (int id = 0; id < XIF_IDS; id++) begin
        if (xif_outstanding_q[id] &&
            ((cycle_q - xif_issue_cycle_q[id]) > XIF_RESULT_TIMEOUT_CYCLES)) begin
          $fatal(1, "CV-X-IF accepted instruction timeout id=%0d type=%s issue_cycle=%0d cycle=%0d",
                 id, xif_op_name(xif_outstanding_op_q[id]),
                 xif_issue_cycle_q[id], cycle_q);
        end
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
	            (cases_passed < 32'(expected_case_count_cfg))) begin
	          $fatal(1, "PASS magic observed before expected case count cases_passed=%0d expected=%0d",
	                 cases_passed, expected_case_count_cfg);
	        end
        if (xif_accept_count_q < 8) begin
          $fatal(1, "PASS magic observed before expected XIF traffic count=%0d",
                 xif_accept_count_q);
        end
        if (desc_control_count_q < 8) begin
          $fatal(1, "PASS magic observed before descriptor controls count=%0d",
                 desc_control_count_q);
        end
        if (xif_issue_count_q != xif_result_count_q) begin
          $fatal(1, "PASS magic observed with mismatched XIF issue/result counts issue=%0d result=%0d",
                 xif_issue_count_q, xif_result_count_q);
        end
        if (xif_accept_count_q != xif_result_count_q) begin
          $fatal(1, "PASS magic observed with mismatched XIF accept/result counts accept=%0d result=%0d",
                 xif_accept_count_q, xif_result_count_q);
        end
        for (int id = 0; id < XIF_IDS; id++) begin
          if (xif_outstanding_q[id]) begin
            $fatal(1, "PASS magic observed with outstanding XIF id=%0d type=%s issue_cycle=%0d",
                   id, xif_op_name(xif_outstanding_op_q[id]),
                   xif_issue_cycle_q[id]);
          end
        end
        if (magic_word == MAGIC_PASS) begin
          if (case_active_q) begin
            $fatal(1, "PASS magic observed while case window is still active id=%0d",
                   case_active_id_q);
          end
          if (case_perf_count_q != cases_passed) begin
            $fatal(1, "PASS magic observed with mismatched CASE_PERF count=%0d cases_passed=%0d",
                   case_perf_count_q, cases_passed);
          end
          if (case_fail_count_q != 0) begin
            $fatal(1, "PASS magic observed with failed CASE_PERF entries=%0d",
                   case_fail_count_q);
          end
	          print_xif_latency_summary();
	          print_core_smoke_perf_summary();
	          print_wots_chain_perf_summary();
	        end else begin
          print_xif_latency_summary();
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
