module tb_spx_cvxif_adapter_coarse;
  timeunit 1ns;
  timeprecision 1ps;

  localparam logic [7:0] SPX_SET_PTR       = 8'h10;
  localparam logic [7:0] SPX_WR_NEXT       = 8'h11;
  localparam logic [7:0] SPX_RD_NEXT       = 8'h12;
  localparam logic [7:0] SPX_START_THASHX4 = 8'h13;
  localparam logic [7:0] SPX_STATUS        = 8'h14;

  localparam logic [7:0] REG_PUB_SEED_BASE = 8'h00;
  localparam logic [7:0] REG_ADDR_BASE     = 8'h10;
  localparam logic [7:0] REG_INPUT_BASE    = 8'h30;
  localparam logic [7:0] REG_OUTPUT_BASE   = 8'h60;

  localparam int STATUS_DONE_BIT  = 1;
  localparam int STATUS_ERROR_BIT = 2;

  localparam int METRIC_SET_PTR      = 0;
  localparam int METRIC_WR_NEXT      = 1;
  localparam int METRIC_RD_NEXT      = 2;
  localparam int METRIC_START        = 3;
  localparam int METRIC_STATUS       = 4;
  localparam int METRIC_TOTAL_INSTR  = 5;
  localparam int METRIC_TOTAL_CYCLES = 6;
  localparam int METRIC_CORE_CYCLES  = 7;
  localparam int METRIC_OVERHEAD     = 8;
  localparam int METRIC_COUNT        = 9;

  localparam int BULK_METRIC_DESC         = 0;
  localparam int BULK_METRIC_STATUS       = 1;
  localparam int BULK_METRIC_TOTAL_INSTR  = 2;
  localparam int BULK_METRIC_TOTAL_CYCLES = 3;
  localparam int BULK_METRIC_CORE_CYCLES  = 4;
  localparam int BULK_METRIC_OVERHEAD     = 5;
  localparam int BULK_METRIC_LOAD_CYCLES  = 6;
  localparam int BULK_METRIC_STORE_CYCLES = 7;
  localparam int BULK_METRIC_COUNT        = 8;

  logic clk;
  logic rst_n;

  logic instr_valid;
  logic instr_ready;
  logic [7:0] instr_op;
  logic [7:0] instr_addr;
  logic [31:0] instr_rs1;
  logic [4:0] instr_rd;
  logic instr_resp_valid;
  logic [31:0] instr_resp_data;
  logic [4:0] instr_resp_rd;
  logic instr_illegal;
  logic instr_busy;
  logic instr_done;
  logic instr_error;

  logic bulk_start;
  logic [1:0] bulk_inblocks;
  logic bulk_done;
  logic [127:0] bulk_pub_seed;
  logic [255:0] bulk_addr0;
  logic [255:0] bulk_addr1;
  logic [255:0] bulk_addr2;
  logic [255:0] bulk_addr3;
  logic [255:0] bulk_in0;
  logic [255:0] bulk_in1;
  logic [255:0] bulk_in2;
  logic [255:0] bulk_in3;
  logic [127:0] bulk_out0;
  logic [127:0] bulk_out1;
  logic [127:0] bulk_out2;
  logic [127:0] bulk_out3;

  int cycle_count;
  bit measure_cycles;
  int first_accept_cycle;
  int last_resp_cycle;
  int op_active_cycles;
  int op_set_ptr_instr;
  int op_wr_next_instr;
  int op_rd_next_instr;
  int op_start_instr;
  int op_status_instr;

  int metric_min [0:1][0:METRIC_COUNT-1];
  int metric_max [0:1][0:METRIC_COUNT-1];
  longint metric_sum [0:1][0:METRIC_COUNT-1];
  int metric_cases [0:1];

  int bulk_metric_min [0:2][0:1][0:BULK_METRIC_COUNT-1];
  int bulk_metric_max [0:2][0:1][0:BULK_METRIC_COUNT-1];
  longint bulk_metric_sum [0:2][0:1][0:BULK_METRIC_COUNT-1];
  int bulk_metric_cases [0:2][0:1];

  spx_cvxif_adapter_coarse dut (
      .clk(clk),
      .rst_n(rst_n),
      .instr_valid(instr_valid),
      .instr_ready(instr_ready),
      .instr_op(instr_op),
      .instr_addr(instr_addr),
      .instr_rs1(instr_rs1),
      .instr_rd(instr_rd),
      .instr_resp_valid(instr_resp_valid),
      .instr_resp_data(instr_resp_data),
      .instr_resp_rd(instr_resp_rd),
      .instr_illegal(instr_illegal),
      .instr_busy(instr_busy),
      .instr_done(instr_done),
      .instr_error(instr_error)
  );

  spx_thashx4_core u_bulk_thashx4_core (
      .clk(clk),
      .rst_n(rst_n),
      .start(bulk_start),
      .inblocks(bulk_inblocks),
      .pub_seed(bulk_pub_seed),
      .addr0(bulk_addr0),
      .addr1(bulk_addr1),
      .addr2(bulk_addr2),
      .addr3(bulk_addr3),
      .in0(bulk_in0),
      .in1(bulk_in1),
      .in2(bulk_in2),
      .in3(bulk_in3),
      .done(bulk_done),
      .out0(bulk_out0),
      .out1(bulk_out1),
      .out2(bulk_out2),
      .out3(bulk_out3)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function automatic int ceil_div(input int value, input int divisor);
    begin
      ceil_div = (value + divisor - 1) / divisor;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
    end
  end

  always_ff @(posedge clk) begin
    if (measure_cycles && instr_busy) begin
      op_active_cycles <= op_active_cycles + 1;
    end
  end

  task automatic reset_dut;
    begin
      rst_n              = 1'b0;
      instr_valid        = 1'b0;
      instr_op           = 8'd0;
      instr_addr         = 8'd0;
      instr_rs1          = 32'd0;
      instr_rd           = 5'd0;
      bulk_start         = 1'b0;
      bulk_inblocks      = 2'd0;
      bulk_pub_seed      = '0;
      bulk_addr0         = '0;
      bulk_addr1         = '0;
      bulk_addr2         = '0;
      bulk_addr3         = '0;
      bulk_in0           = '0;
      bulk_in1           = '0;
      bulk_in2           = '0;
      bulk_in3           = '0;
      measure_cycles     = 1'b0;
      first_accept_cycle = -1;
      last_resp_cycle    = -1;
      op_active_cycles   = 0;
      op_set_ptr_instr   = 0;
      op_wr_next_instr   = 0;
      op_rd_next_instr   = 0;
      op_start_instr     = 0;
      op_status_instr    = 0;
      repeat (4) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic note_instr(input logic [7:0] op);
    begin
      unique case (op)
        SPX_SET_PTR: op_set_ptr_instr++;
        SPX_WR_NEXT: op_wr_next_instr++;
        SPX_RD_NEXT: op_rd_next_instr++;
        SPX_START_THASHX4: op_start_instr++;
        SPX_STATUS: op_status_instr++;
        default: begin
        end
      endcase
    end
  endtask

  task automatic send_instr(
      input  logic [7:0]  op,
      input  logic [7:0]  addr,
      input  logic [31:0] rs1,
      input  logic [4:0]  rd,
      output logic [31:0] rdata
  );
    begin
      @(negedge clk);
      instr_valid = 1'b1;
      instr_op    = op;
      instr_addr  = addr;
      instr_rs1   = rs1;
      instr_rd    = rd;

      while (!instr_ready) begin
        @(negedge clk);
      end

      @(posedge clk);
      #1ps;
      if (measure_cycles && (first_accept_cycle < 0)) begin
        first_accept_cycle = cycle_count;
      end
      note_instr(op);

      instr_valid = 1'b0;
      instr_op    = 8'd0;
      instr_addr  = 8'd0;
      instr_rs1   = 32'd0;
      instr_rd    = 5'd0;

      while (!instr_resp_valid) begin
        @(posedge clk);
        #1ps;
      end

      rdata = instr_resp_data;
      if (instr_illegal) begin
        $fatal(1, "coarse adapter illegal instruction op=0x%02x addr=0x%02x",
               op, addr);
      end
      if (instr_resp_rd !== rd) begin
        $fatal(1, "coarse adapter rd mismatch op=0x%02x expected=%0d got=%0d",
               op, rd, instr_resp_rd);
      end
      if (measure_cycles) begin
        last_resp_cycle = cycle_count;
      end
    end
  endtask

  task automatic spx_set_ptr(input logic [7:0] ptr);
    logic [31:0] unused_rdata;
    begin
      send_instr(SPX_SET_PTR, ptr, 32'd0, 5'd0, unused_rdata);
    end
  endtask

  task automatic spx_wr_next(input logic [31:0] data);
    logic [31:0] unused_rdata;
    begin
      send_instr(SPX_WR_NEXT, 8'd0, data, 5'd0, unused_rdata);
    end
  endtask

  task automatic spx_rd_next(output logic [31:0] data);
    begin
      send_instr(SPX_RD_NEXT, 8'd0, 32'd0, 5'd1, data);
    end
  endtask

  task automatic spx_start_thashx4(input int expected_inblocks);
    logic [31:0] unused_rdata;
    begin
      send_instr(SPX_START_THASHX4, 8'd0, {30'd0, expected_inblocks[1:0]}, 5'd0,
                 unused_rdata);
    end
  endtask

  task automatic spx_status(output logic [31:0] status);
    begin
      send_instr(SPX_STATUS, 8'd0, 32'd0, 5'd2, status);
    end
  endtask

  task automatic write_input_stream(
      input int expected_inblocks,
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
    int input_words;
    logic [7:0] lane_base;
    begin
      input_words = expected_inblocks * 4;
      spx_set_ptr(REG_PUB_SEED_BASE);

      for (int word = 0; word < 4; word++) begin
        spx_wr_next(pub_seed[32 * word +: 32]);
      end

      spx_set_ptr(REG_ADDR_BASE);
      for (int word = 0; word < 8; word++) begin
        spx_wr_next(addr0[32 * word +: 32]);
      end
      for (int word = 0; word < 8; word++) begin
        spx_wr_next(addr1[32 * word +: 32]);
      end
      for (int word = 0; word < 8; word++) begin
        spx_wr_next(addr2[32 * word +: 32]);
      end
      for (int word = 0; word < 8; word++) begin
        spx_wr_next(addr3[32 * word +: 32]);
      end

      if (expected_inblocks == 2) begin
        for (int word = 0; word < input_words; word++) begin
          spx_wr_next(in0[32 * word +: 32]);
        end
        for (int word = 0; word < input_words; word++) begin
          spx_wr_next(in1[32 * word +: 32]);
        end
        for (int word = 0; word < input_words; word++) begin
          spx_wr_next(in2[32 * word +: 32]);
        end
        for (int word = 0; word < input_words; word++) begin
          spx_wr_next(in3[32 * word +: 32]);
        end
      end else begin
        for (int word = 0; word < input_words; word++) begin
          spx_wr_next(in0[32 * word +: 32]);
        end

        lane_base = REG_INPUT_BASE + 8'h08;
        spx_set_ptr(lane_base);
        for (int word = 0; word < input_words; word++) begin
          spx_wr_next(in1[32 * word +: 32]);
        end

        lane_base = REG_INPUT_BASE + 8'h10;
        spx_set_ptr(lane_base);
        for (int word = 0; word < input_words; word++) begin
          spx_wr_next(in2[32 * word +: 32]);
        end

        lane_base = REG_INPUT_BASE + 8'h18;
        spx_set_ptr(lane_base);
        for (int word = 0; word < input_words; word++) begin
          spx_wr_next(in3[32 * word +: 32]);
        end
      end
    end
  endtask

  task automatic read_output_stream(
      output logic [127:0] got0,
      output logic [127:0] got1,
      output logic [127:0] got2,
      output logic [127:0] got3
  );
    logic [31:0] word_data;
    begin
      got0 = '0;
      got1 = '0;
      got2 = '0;
      got3 = '0;

      spx_set_ptr(REG_OUTPUT_BASE);
      for (int word = 0; word < 4; word++) begin
        spx_rd_next(word_data);
        got0[32 * word +: 32] = word_data;
      end
      for (int word = 0; word < 4; word++) begin
        spx_rd_next(word_data);
        got1[32 * word +: 32] = word_data;
      end
      for (int word = 0; word < 4; word++) begin
        spx_rd_next(word_data);
        got2[32 * word +: 32] = word_data;
      end
      for (int word = 0; word < 4; word++) begin
        spx_rd_next(word_data);
        got3[32 * word +: 32] = word_data;
      end
    end
  endtask

  task automatic poll_until_done(input int case_id);
    logic [31:0] status;
    int poll_count;
    begin
      poll_count = 0;
      do begin
        spx_status(status);
        poll_count++;
        if (status[STATUS_ERROR_BIT]) begin
          $fatal(1, "coarse adapter status error 0x%08x at case %0d",
                 status, case_id);
        end
        if (poll_count > 120) begin
          $fatal(1, "coarse adapter status timeout at case %0d last_status=0x%08x",
                 case_id, status);
        end
      end while (!status[STATUS_DONE_BIT]);

      if (instr_busy || !instr_done || instr_error) begin
        $fatal(1, "coarse adapter pins mismatch after done at case %0d busy=%0b done=%0b error=%0b",
               case_id, instr_busy, instr_done, instr_error);
      end
    end
  endtask

  task automatic begin_op_stats;
    begin
      op_set_ptr_instr   = 0;
      op_wr_next_instr   = 0;
      op_rd_next_instr   = 0;
      op_start_instr     = 0;
      op_status_instr    = 0;
      op_active_cycles   = 0;
      first_accept_cycle = -1;
      last_resp_cycle    = -1;
      measure_cycles     = 1'b1;
    end
  endtask

  task automatic finish_op_stats(
      output int set_ptr_instr,
      output int wr_next_instr,
      output int rd_next_instr,
      output int start_instr,
      output int status_instr,
      output int total_instr,
      output int total_cycles,
      output int core_cycles,
      output int overhead_cycles
  );
    begin
      measure_cycles = 1'b0;
      set_ptr_instr = op_set_ptr_instr;
      wr_next_instr = op_wr_next_instr;
      rd_next_instr = op_rd_next_instr;
      start_instr = op_start_instr;
      status_instr = op_status_instr;
      total_instr = op_set_ptr_instr + op_wr_next_instr + op_rd_next_instr +
                    op_start_instr + op_status_instr;
      if ((first_accept_cycle < 0) || (last_resp_cycle < first_accept_cycle)) begin
        $fatal(1, "invalid coarse operation cycle accounting first=%0d last=%0d",
               first_accept_cycle, last_resp_cycle);
      end
      total_cycles = last_resp_cycle - first_accept_cycle + 1;
      core_cycles = op_active_cycles;
      overhead_cycles = total_cycles - core_cycles;
    end
  endtask

  task automatic run_auto_inc_case(
      input int case_id,
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
      output int set_ptr_instr,
      output int wr_next_instr,
      output int rd_next_instr,
      output int start_instr,
      output int status_instr,
      output int total_instr,
      output int total_cycles,
      output int core_cycles,
      output int overhead_cycles
  );
    begin
      begin_op_stats();
      write_input_stream(expected_inblocks, pub_seed, addr0, addr1, addr2, addr3,
                         in0, in1, in2, in3);
      spx_start_thashx4(expected_inblocks);
      poll_until_done(case_id);
      read_output_stream(got0, got1, got2, got3);
      finish_op_stats(set_ptr_instr, wr_next_instr, rd_next_instr, start_instr,
                      status_instr, total_instr, total_cycles, core_cycles,
                      overhead_cycles);
    end
  endtask

  task automatic run_bulk_case(
      input int case_id,
      input int expected_inblocks,
      input int words_per_cycle,
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
      output int descriptor_instr,
      output int status_instr,
      output int total_instr,
      output int total_cycles,
      output int core_cycles,
      output int overhead_cycles,
      output int load_cycles,
      output int store_cycles
  );
    int load_words;
    int store_words;
    int operation_cycles;
    begin
      load_words = 4 + 32 + (4 * expected_inblocks * 4);
      store_words = 16;
      load_cycles = ceil_div(load_words, words_per_cycle);
      store_cycles = ceil_div(store_words, words_per_cycle);

      bulk_pub_seed = pub_seed;
      bulk_addr0 = addr0;
      bulk_addr1 = addr1;
      bulk_addr2 = addr2;
      bulk_addr3 = addr3;
      bulk_in0 = in0;
      bulk_in1 = in1;
      bulk_in2 = in2;
      bulk_in3 = in3;
      bulk_inblocks = expected_inblocks[1:0];

      repeat (load_cycles) @(posedge clk);

      @(negedge clk);
      bulk_start = 1'b1;
      @(negedge clk);
      bulk_start = 1'b0;

      core_cycles = 0;
      while (!bulk_done && core_cycles < 100) begin
        @(posedge clk);
        core_cycles++;
      end
      if (!bulk_done) begin
        $fatal(1, "bulk thashx4 timeout at case %0d width=%0d",
               case_id, words_per_cycle);
      end

      got0 = bulk_out0;
      got1 = bulk_out1;
      got2 = bulk_out2;
      got3 = bulk_out3;

      repeat (store_cycles) @(posedge clk);
      @(posedge clk);

      operation_cycles = load_cycles + core_cycles + store_cycles;
      descriptor_instr = 1;
      status_instr = ceil_div(operation_cycles, 2);
      total_instr = descriptor_instr + status_instr;
      total_cycles = descriptor_instr + (2 * status_instr);
      overhead_cycles = total_cycles - core_cycles;
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

      for (int width = 0; width < 3; width++) begin
        for (int phase = 0; phase < 2; phase++) begin
          bulk_metric_cases[width][phase] = 0;
          for (int metric = 0; metric < BULK_METRIC_COUNT; metric++) begin
            bulk_metric_min[width][phase][metric] = 32'h7fffffff;
            bulk_metric_max[width][phase][metric] = 0;
            bulk_metric_sum[width][phase][metric] = 0;
          end
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
      input int set_ptr_instr,
      input int wr_next_instr,
      input int rd_next_instr,
      input int start_instr,
      input int status_instr,
      input int total_instr,
      input int total_cycles,
      input int core_cycles,
      input int overhead_cycles
  );
    begin
      metric_cases[phase]++;
      update_metric(phase, METRIC_SET_PTR, set_ptr_instr);
      update_metric(phase, METRIC_WR_NEXT, wr_next_instr);
      update_metric(phase, METRIC_RD_NEXT, rd_next_instr);
      update_metric(phase, METRIC_START, start_instr);
      update_metric(phase, METRIC_STATUS, status_instr);
      update_metric(phase, METRIC_TOTAL_INSTR, total_instr);
      update_metric(phase, METRIC_TOTAL_CYCLES, total_cycles);
      update_metric(phase, METRIC_CORE_CYCLES, core_cycles);
      update_metric(phase, METRIC_OVERHEAD, overhead_cycles);
    end
  endtask

  task automatic update_bulk_metric(
      input int width_idx,
      input int phase,
      input int metric,
      input int value
  );
    begin
      if (value < bulk_metric_min[width_idx][phase][metric]) begin
        bulk_metric_min[width_idx][phase][metric] = value;
      end
      if (value > bulk_metric_max[width_idx][phase][metric]) begin
        bulk_metric_max[width_idx][phase][metric] = value;
      end
      bulk_metric_sum[width_idx][phase][metric] += longint'(value);
    end
  endtask

  task automatic update_bulk_metrics(
      input int width_idx,
      input int phase,
      input int descriptor_instr,
      input int status_instr,
      input int total_instr,
      input int total_cycles,
      input int core_cycles,
      input int overhead_cycles,
      input int load_cycles,
      input int store_cycles
  );
    begin
      bulk_metric_cases[width_idx][phase]++;
      update_bulk_metric(width_idx, phase, BULK_METRIC_DESC, descriptor_instr);
      update_bulk_metric(width_idx, phase, BULK_METRIC_STATUS, status_instr);
      update_bulk_metric(width_idx, phase, BULK_METRIC_TOTAL_INSTR, total_instr);
      update_bulk_metric(width_idx, phase, BULK_METRIC_TOTAL_CYCLES, total_cycles);
      update_bulk_metric(width_idx, phase, BULK_METRIC_CORE_CYCLES, core_cycles);
      update_bulk_metric(width_idx, phase, BULK_METRIC_OVERHEAD, overhead_cycles);
      update_bulk_metric(width_idx, phase, BULK_METRIC_LOAD_CYCLES, load_cycles);
      update_bulk_metric(width_idx, phase, BULK_METRIC_STORE_CYCLES, store_cycles);
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

  task automatic print_bulk_metric(
      input int width_idx,
      input int phase,
      input int metric,
      input string name
  );
    real avg;
    begin
      avg = bulk_metric_sum[width_idx][phase][metric];
      avg = avg / bulk_metric_cases[width_idx][phase];
      if (bulk_metric_min[width_idx][phase][metric] ==
          bulk_metric_max[width_idx][phase][metric]) begin
        $display("  %s = %0d", name, bulk_metric_min[width_idx][phase][metric]);
      end else begin
        $display("  %s min=%0d max=%0d avg=%0.2f",
                 name, bulk_metric_min[width_idx][phase][metric],
                 bulk_metric_max[width_idx][phase][metric], avg);
      end
    end
  endtask

  task automatic print_auto_stats(input int phase, input int inblocks);
    begin
      $display("COARSE_AUTO_INC_STATS inblocks=%0d:", inblocks);
      print_metric(phase, METRIC_SET_PTR, "set_ptr_instr");
      print_metric(phase, METRIC_WR_NEXT, "wr_next_instr");
      print_metric(phase, METRIC_RD_NEXT, "rd_next_instr");
      print_metric(phase, METRIC_START, "start_instr");
      print_metric(phase, METRIC_STATUS, "status_instr");
      print_metric(phase, METRIC_TOTAL_INSTR, "total_instr");
      print_metric(phase, METRIC_TOTAL_CYCLES, "total_cycles");
      print_metric(phase, METRIC_CORE_CYCLES, "core_cycles");
      print_metric(phase, METRIC_OVERHEAD, "overhead_cycles");
    end
  endtask

  task automatic print_bulk_stats(input int width_idx, input int words_per_cycle,
                                  input int phase, input int inblocks);
    begin
      $display("BULK_MODEL_STATS width=%0dwords_per_cycle inblocks=%0d:",
               words_per_cycle, inblocks);
      print_bulk_metric(width_idx, phase, BULK_METRIC_DESC, "descriptor_instr");
      print_bulk_metric(width_idx, phase, BULK_METRIC_STATUS, "status_instr");
      print_bulk_metric(width_idx, phase, BULK_METRIC_LOAD_CYCLES, "load_cycles");
      print_bulk_metric(width_idx, phase, BULK_METRIC_STORE_CYCLES, "store_cycles");
      print_bulk_metric(width_idx, phase, BULK_METRIC_TOTAL_INSTR, "total_instr");
      print_bulk_metric(width_idx, phase, BULK_METRIC_TOTAL_CYCLES, "total_cycles");
      print_bulk_metric(width_idx, phase, BULK_METRIC_CORE_CYCLES, "core_cycles");
      print_bulk_metric(width_idx, phase, BULK_METRIC_OVERHEAD, "overhead_cycles");
    end
  endtask

  task automatic print_table_row(
      input string protocol,
      input int inblocks,
      input int total_instr,
      input int total_cycles,
      input int core_cycles,
      input int overhead_cycles
  );
    real active_share;
    begin
      active_share = (100.0 * core_cycles) / total_cycles;
      $display("%-21s %8d %6d %13d %12d %9d %11.1f%%",
               protocol, inblocks, total_instr, total_cycles, core_cycles,
               overhead_cycles, active_share);
    end
  endtask

  task automatic print_comparison_table;
    begin
      $display("COARSE_PROTOCOL_COMPARISON:");
      $display("Protocol              inblocks  instr  total_cycles  core_cycles  overhead  active_share");
      $display("-----------------------------------------------------------------------------------------");
      print_table_row("scalar", 1, 84, 168, 27, 141);
      print_table_row("scalar", 2, 100, 200, 27, 173);
      for (int phase = 0; phase < 2; phase++) begin
        print_table_row("auto_inc", phase + 1,
                        metric_min[phase][METRIC_TOTAL_INSTR],
                        metric_min[phase][METRIC_TOTAL_CYCLES],
                        metric_min[phase][METRIC_CORE_CYCLES],
                        metric_min[phase][METRIC_OVERHEAD]);
      end
      for (int width_idx = 0; width_idx < 3; width_idx++) begin
        string protocol;
        int words_per_cycle;
        words_per_cycle = 1 << width_idx;
        protocol = $sformatf("bulk_%0dw", words_per_cycle);
        for (int phase = 0; phase < 2; phase++) begin
          print_table_row(protocol, phase + 1,
                          bulk_metric_min[width_idx][phase][BULK_METRIC_TOTAL_INSTR],
                          bulk_metric_min[width_idx][phase][BULK_METRIC_TOTAL_CYCLES],
                          bulk_metric_min[width_idx][phase][BULK_METRIC_CORE_CYCLES],
                          bulk_metric_min[width_idx][phase][BULK_METRIC_OVERHEAD]);
        end
      end
    end
  endtask

  task automatic compare_outputs(
      input string protocol,
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
        $display("FAIL %s inblocks=%0d case=%0d lane=0", protocol, inblocks, case_id);
        $display("  expected %h", exp0);
        $display("  got      %h", got0);
        errors++;
      end
      if (got1 !== exp1) begin
        $display("FAIL %s inblocks=%0d case=%0d lane=1", protocol, inblocks, case_id);
        $display("  expected %h", exp1);
        $display("  got      %h", got1);
        errors++;
      end
      if (got2 !== exp2) begin
        $display("FAIL %s inblocks=%0d case=%0d lane=2", protocol, inblocks, case_id);
        $display("  expected %h", exp2);
        $display("  got      %h", got2);
        errors++;
      end
      if (got3 !== exp3) begin
        $display("FAIL %s inblocks=%0d case=%0d lane=3", protocol, inblocks, case_id);
        $display("  expected %h", exp3);
        $display("  got      %h", got3);
        errors++;
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
    int errors;
    int exp_inblocks;
    int set_ptr_instr;
    int wr_next_instr;
    int rd_next_instr;
    int start_instr;
    int status_instr;
    int descriptor_instr;
    int total_instr;
    int total_cycles;
    int core_cycles;
    int overhead_cycles;
    int load_cycles;
    int store_cycles;
    int bulk_widths [0:2];
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
    bulk_widths[0] = 1;
    bulk_widths[1] = 2;
    bulk_widths[2] = 4;

    reset_dut();
    init_metric_stats();

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
          $fatal(1, "failed to read coarse input case %0d from %s",
                 case_id, input_path[phase]);
        end

        rc = $fscanf(expected_fd, "%d %h %h %h %h",
                     exp_inblocks, exp0, exp1, exp2, exp3);
        if (rc != 5) begin
          $fatal(1, "failed to read coarse expected case %0d from %s",
                 expected_case_id, expected_path);
        end
        if (exp_inblocks != expected_inblocks[phase]) begin
          $fatal(1, "expected file inblocks mismatch at case %0d: expected %0d got %0d",
                 expected_case_id, expected_inblocks[phase], exp_inblocks);
        end

        run_auto_inc_case(expected_case_id, expected_inblocks[phase],
                          pub_seed, addr0, addr1, addr2, addr3, in0, in1, in2, in3,
                          got0, got1, got2, got3,
                          set_ptr_instr, wr_next_instr, rd_next_instr, start_instr,
                          status_instr, total_instr, total_cycles, core_cycles,
                          overhead_cycles);

        update_metrics(phase, set_ptr_instr, wr_next_instr, rd_next_instr,
                       start_instr, status_instr, total_instr, total_cycles,
                       core_cycles, overhead_cycles);
        compare_outputs("auto_inc", expected_inblocks[phase], case_id,
                        exp0, exp1, exp2, exp3, got0, got1, got2, got3, errors);

        for (int width_idx = 0; width_idx < 3; width_idx++) begin
          run_bulk_case(expected_case_id, expected_inblocks[phase],
                        bulk_widths[width_idx],
                        pub_seed, addr0, addr1, addr2, addr3, in0, in1, in2, in3,
                        got0, got1, got2, got3,
                        descriptor_instr, status_instr, total_instr, total_cycles,
                        core_cycles, overhead_cycles, load_cycles, store_cycles);
          update_bulk_metrics(width_idx, phase, descriptor_instr, status_instr,
                              total_instr, total_cycles, core_cycles,
                              overhead_cycles, load_cycles, store_cycles);
          compare_outputs($sformatf("bulk_%0dw", bulk_widths[width_idx]),
                          expected_inblocks[phase], case_id,
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
      $fatal(1, "FAIL spx_cvxif_adapter_coarse mismatches=%0d", errors);
    end

    for (int phase = 0; phase < 2; phase++) begin
      print_auto_stats(phase, expected_inblocks[phase]);
    end

    for (int width_idx = 0; width_idx < 3; width_idx++) begin
      for (int phase = 0; phase < 2; phase++) begin
        print_bulk_stats(width_idx, bulk_widths[width_idx], phase,
                         expected_inblocks[phase]);
      end
    end

    print_comparison_table();
    $display("PASS spx_cvxif_adapter_coarse inblocks=1,2 (%0d cases)", expected_case_id);
    $finish;
  end
endmodule
