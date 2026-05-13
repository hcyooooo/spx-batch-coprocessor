module tb_spx_cvxif_adapter;
  timeunit 1ns;
  timeprecision 1ps;

  localparam logic [7:0] SPX_WR     = 8'h01;
  localparam logic [7:0] SPX_RD     = 8'h02;
  localparam logic [7:0] SPX_START  = 8'h03;
  localparam logic [7:0] SPX_STATUS = 8'h04;
  localparam logic [7:0] SPX_CLR    = 8'h05;

  localparam logic [7:0] REG_PUB_SEED_BASE = 8'h00;
  localparam logic [7:0] REG_ADDR_BASE     = 8'h10;
  localparam logic [7:0] REG_INPUT_BASE    = 8'h30;
  localparam logic [7:0] REG_CONFIG        = 8'h50;
  localparam logic [7:0] REG_OUTPUT_BASE   = 8'h60;

  localparam int STATUS_BUSY_BIT  = 0;
  localparam int STATUS_DONE_BIT  = 1;
  localparam int STATUS_ERROR_BIT = 2;

  localparam int METRIC_WRITE        = 0;
  localparam int METRIC_READ         = 1;
  localparam int METRIC_START        = 2;
  localparam int METRIC_STATUS       = 3;
  localparam int METRIC_TOTAL_INSTR  = 4;
  localparam int METRIC_TOTAL_CYCLES = 5;
  localparam int METRIC_CORE_CYCLES  = 6;
  localparam int METRIC_OVERHEAD     = 7;
  localparam int METRIC_COUNT        = 8;

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

  int cycle_count;
  bit measure_cycles;
  int first_accept_cycle;
  int last_resp_cycle;
  int op_active_cycles;
  int op_write_instr;
  int op_read_instr;
  int op_start_instr;
  int op_status_instr;
  int op_clear_instr;

  int metric_min [0:1][0:METRIC_COUNT-1];
  int metric_max [0:1][0:METRIC_COUNT-1];
  longint metric_sum [0:1][0:METRIC_COUNT-1];
  int metric_cases [0:1];

  spx_cvxif_adapter dut (
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

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

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
      measure_cycles     = 1'b0;
      first_accept_cycle = -1;
      last_resp_cycle    = -1;
      op_active_cycles   = 0;
      op_write_instr     = 0;
      op_read_instr      = 0;
      op_start_instr     = 0;
      op_status_instr    = 0;
      op_clear_instr     = 0;
      repeat (4) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic note_instr(input logic [7:0] op);
    begin
      unique case (op)
        SPX_WR: op_write_instr++;
        SPX_RD: op_read_instr++;
        SPX_START: op_start_instr++;
        SPX_STATUS: op_status_instr++;
        SPX_CLR: op_clear_instr++;
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

      @(negedge clk);
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
        $fatal(1, "adapter reported illegal instruction op=0x%02x addr=0x%02x",
               op, addr);
      end
      if (instr_resp_rd !== rd) begin
        $fatal(1, "adapter rd mismatch op=0x%02x expected=%0d got=%0d",
               op, rd, instr_resp_rd);
      end
      if (measure_cycles) begin
        last_resp_cycle = cycle_count;
      end
    end
  endtask

  task automatic spx_write(input logic [7:0] addr, input logic [31:0] data);
    logic [31:0] unused_rdata;
    begin
      send_instr(SPX_WR, addr, data, 5'd0, unused_rdata);
    end
  endtask

  task automatic spx_read(input logic [7:0] addr, output logic [31:0] data);
    begin
      send_instr(SPX_RD, addr, 32'd0, 5'd1, data);
    end
  endtask

  task automatic spx_start;
    logic [31:0] unused_rdata;
    begin
      send_instr(SPX_START, 8'd0, 32'd0, 5'd0, unused_rdata);
    end
  endtask

  task automatic spx_status(output logic [31:0] status);
    begin
      send_instr(SPX_STATUS, 8'd0, 32'd0, 5'd2, status);
    end
  endtask

  task automatic write_pub_seed(input logic [127:0] pub_seed);
    logic [7:0] reg_addr;
    begin
      for (int word = 0; word < 4; word++) begin
        reg_addr = REG_PUB_SEED_BASE + word[7:0];
        spx_write(reg_addr, pub_seed[32 * word +: 32]);
      end
    end
  endtask

  task automatic write_addr_lane(input int lane, input logic [255:0] addr_value);
    logic [7:0] reg_addr;
    logic [7:0] lane_base;
    begin
      lane_base = {3'd0, lane[1:0], 3'd0};
      for (int word = 0; word < 8; word++) begin
        reg_addr = REG_ADDR_BASE + lane_base + word[7:0];
        spx_write(reg_addr, addr_value[32 * word +: 32]);
      end
    end
  endtask

  task automatic write_input_lane(
      input int lane,
      input int input_words,
      input logic [255:0] input_value
  );
    logic [7:0] reg_addr;
    logic [7:0] lane_base;
    begin
      lane_base = {3'd0, lane[1:0], 3'd0};
      for (int word = 0; word < input_words; word++) begin
        reg_addr = REG_INPUT_BASE + lane_base + word[7:0];
        spx_write(reg_addr, input_value[32 * word +: 32]);
      end
    end
  endtask

  task automatic read_output_lane(input int lane, output logic [127:0] output_value);
    logic [7:0] reg_addr;
    logic [7:0] lane_base;
    logic [31:0] word_data;
    begin
      output_value = '0;
      lane_base = {4'd0, lane[1:0], 2'd0};
      for (int word = 0; word < 4; word++) begin
        reg_addr = REG_OUTPUT_BASE + lane_base + word[7:0];
        spx_read(reg_addr, word_data);
        output_value[32 * word +: 32] = word_data;
      end
    end
  endtask

  task automatic poll_until_done(input int case_id, output int poll_count);
    logic [31:0] status;
    begin
      poll_count = 0;
      do begin
        spx_status(status);
        poll_count++;
        if (status[STATUS_ERROR_BIT]) begin
          $fatal(1, "adapter status error 0x%08x at case %0d",
                 status, case_id);
        end
        if (poll_count > 80) begin
          $fatal(1, "adapter status timeout at case %0d last_status=0x%08x",
                 case_id, status);
        end
      end while (!status[STATUS_DONE_BIT]);

      if (instr_busy || !instr_done || instr_error) begin
        $fatal(1, "adapter pins mismatch after done at case %0d busy=%0b done=%0b error=%0b",
               case_id, instr_busy, instr_done, instr_error);
      end
    end
  endtask

  task automatic begin_op_stats;
    begin
      op_write_instr     = 0;
      op_read_instr      = 0;
      op_start_instr     = 0;
      op_status_instr    = 0;
      op_clear_instr     = 0;
      op_active_cycles   = 0;
      first_accept_cycle = -1;
      last_resp_cycle    = -1;
      measure_cycles     = 1'b1;
    end
  endtask

  task automatic finish_op_stats(
      output int write_instr,
      output int read_instr,
      output int start_instr,
      output int status_instr,
      output int total_instr,
      output int total_cycles,
      output int core_cycles,
      output int overhead_cycles
  );
    begin
      measure_cycles = 1'b0;
      write_instr = op_write_instr;
      read_instr = op_read_instr;
      start_instr = op_start_instr;
      status_instr = op_status_instr;
      total_instr = op_write_instr + op_read_instr + op_start_instr +
                    op_status_instr + op_clear_instr;
      if ((first_accept_cycle < 0) || (last_resp_cycle < first_accept_cycle)) begin
        $fatal(1, "invalid operation cycle accounting first=%0d last=%0d",
               first_accept_cycle, last_resp_cycle);
      end
      total_cycles = last_resp_cycle - first_accept_cycle + 1;
      core_cycles = op_active_cycles;
      overhead_cycles = total_cycles - core_cycles;
    end
  endtask

  task automatic run_case(
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
      output int write_instr,
      output int read_instr,
      output int start_instr,
      output int status_instr,
      output int total_instr,
      output int total_cycles,
      output int core_cycles,
      output int overhead_cycles
  );
    int input_words;
    int poll_count;
    begin
      input_words = expected_inblocks * 4;

      begin_op_stats();
      write_pub_seed(pub_seed);
      write_addr_lane(0, addr0);
      write_addr_lane(1, addr1);
      write_addr_lane(2, addr2);
      write_addr_lane(3, addr3);
      write_input_lane(0, input_words, in0);
      write_input_lane(1, input_words, in1);
      write_input_lane(2, input_words, in2);
      write_input_lane(3, input_words, in3);
      spx_write(REG_CONFIG, {30'd0, expected_inblocks[1:0]});
      spx_start();
      poll_until_done(case_id, poll_count);
      read_output_lane(0, got0);
      read_output_lane(1, got1);
      read_output_lane(2, got2);
      read_output_lane(3, got3);
      finish_op_stats(write_instr, read_instr, start_instr, status_instr,
                      total_instr, total_cycles, core_cycles, overhead_cycles);
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
      input int write_instr,
      input int read_instr,
      input int start_instr,
      input int status_instr,
      input int total_instr,
      input int total_cycles,
      input int core_cycles,
      input int overhead_cycles
  );
    begin
      metric_cases[phase]++;
      update_metric(phase, METRIC_WRITE, write_instr);
      update_metric(phase, METRIC_READ, read_instr);
      update_metric(phase, METRIC_START, start_instr);
      update_metric(phase, METRIC_STATUS, status_instr);
      update_metric(phase, METRIC_TOTAL_INSTR, total_instr);
      update_metric(phase, METRIC_TOTAL_CYCLES, total_cycles);
      update_metric(phase, METRIC_CORE_CYCLES, core_cycles);
      update_metric(phase, METRIC_OVERHEAD, overhead_cycles);
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

  task automatic print_phase_stats(input int phase, input int inblocks);
    begin
      $display("CVXIF_ADAPTER_STATS inblocks=%0d:", inblocks);
      print_metric(phase, METRIC_WRITE, "write_instr");
      print_metric(phase, METRIC_READ, "read_instr");
      print_metric(phase, METRIC_START, "start_instr");
      print_metric(phase, METRIC_STATUS, "status_instr");
      print_metric(phase, METRIC_TOTAL_INSTR, "total_instr");
      print_metric(phase, METRIC_TOTAL_CYCLES, "total_cycles");
      print_metric(phase, METRIC_CORE_CYCLES, "core_cycles");
      print_metric(phase, METRIC_OVERHEAD, "overhead_cycles");
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
    int write_instr;
    int read_instr;
    int start_instr;
    int status_instr;
    int total_instr;
    int total_cycles;
    int core_cycles;
    int overhead_cycles;
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
          $fatal(1, "failed to read adapter input case %0d from %s",
                 case_id, input_path[phase]);
        end

        rc = $fscanf(expected_fd, "%d %h %h %h %h",
                     exp_inblocks, exp0, exp1, exp2, exp3);
        if (rc != 5) begin
          $fatal(1, "failed to read adapter expected case %0d from %s",
                 expected_case_id, expected_path);
        end
        if (exp_inblocks != expected_inblocks[phase]) begin
          $fatal(1, "expected file inblocks mismatch at case %0d: expected %0d got %0d",
                 expected_case_id, expected_inblocks[phase], exp_inblocks);
        end

        run_case(expected_case_id, expected_inblocks[phase],
                 pub_seed, addr0, addr1, addr2, addr3, in0, in1, in2, in3,
                 got0, got1, got2, got3,
                 write_instr, read_instr, start_instr, status_instr,
                 total_instr, total_cycles, core_cycles, overhead_cycles);

        update_metrics(phase, write_instr, read_instr, start_instr, status_instr,
                       total_instr, total_cycles, core_cycles, overhead_cycles);

        if (got0 !== exp0) begin
          $display("FAIL spx_cvxif_adapter inblocks=%0d case=%0d lane=0",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp0);
          $display("  got      %h", got0);
          errors++;
        end
        if (got1 !== exp1) begin
          $display("FAIL spx_cvxif_adapter inblocks=%0d case=%0d lane=1",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp1);
          $display("  got      %h", got1);
          errors++;
        end
        if (got2 !== exp2) begin
          $display("FAIL spx_cvxif_adapter inblocks=%0d case=%0d lane=2",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp2);
          $display("  got      %h", got2);
          errors++;
        end
        if (got3 !== exp3) begin
          $display("FAIL spx_cvxif_adapter inblocks=%0d case=%0d lane=3",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp3);
          $display("  got      %h", got3);
          errors++;
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
      $fatal(1, "FAIL spx_cvxif_adapter mismatches=%0d", errors);
    end

    for (int phase = 0; phase < 2; phase++) begin
      print_phase_stats(phase, expected_inblocks[phase]);
    end
    $display("PASS spx_cvxif_adapter inblocks=1,2 (%0d cases)", expected_case_id);
    $finish;
  end
endmodule
