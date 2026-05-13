module tb_spx_cop_wrapper;
  timeunit 1ns;
  timeprecision 1ps;

  localparam logic [7:0] CMD_WRITE = 8'h01;
  localparam logic [7:0] CMD_READ  = 8'h02;
  localparam logic [7:0] CMD_START = 8'h03;

  localparam logic [7:0] REG_PUB_SEED_BASE = 8'h00;
  localparam logic [7:0] REG_ADDR_BASE     = 8'h10;
  localparam logic [7:0] REG_INPUT_BASE    = 8'h30;
  localparam logic [7:0] REG_CONFIG        = 8'h50;
  localparam logic [7:0] REG_STATUS        = 8'h51;
  localparam logic [7:0] REG_OUTPUT_BASE   = 8'h60;

  localparam int STATUS_BUSY_BIT  = 0;
  localparam int STATUS_DONE_BIT  = 1;
  localparam int STATUS_ERROR_BIT = 2;

  logic clk;
  logic rst_n;
  logic cmd_valid;
  logic cmd_ready;
  logic [7:0] cmd_op;
  logic [7:0] cmd_addr;
  logic [31:0] cmd_wdata;
  logic [31:0] rsp_rdata;
  logic rsp_valid;
  logic busy;
  logic done;
  logic error;

  spx_cop_wrapper dut (
      .clk(clk),
      .rst_n(rst_n),
      .cmd_valid(cmd_valid),
      .cmd_ready(cmd_ready),
      .cmd_op(cmd_op),
      .cmd_addr(cmd_addr),
      .cmd_wdata(cmd_wdata),
      .rsp_rdata(rsp_rdata),
      .rsp_valid(rsp_valid),
      .busy(busy),
      .done(done),
      .error(error)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic reset_dut;
    begin
      rst_n     = 1'b0;
      cmd_valid = 1'b0;
      cmd_op    = 8'd0;
      cmd_addr  = 8'd0;
      cmd_wdata = 32'd0;
      repeat (4) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic send_cmd(
      input  logic [7:0]  op,
      input  logic [7:0]  addr,
      input  logic [31:0] wdata,
      output logic [31:0] rdata
  );
    begin
      @(negedge clk);
      cmd_valid = 1'b1;
      cmd_op    = op;
      cmd_addr  = addr;
      cmd_wdata = wdata;

      while (!cmd_ready) begin
        @(negedge clk);
      end

      @(posedge clk);
      @(negedge clk);
      cmd_valid = 1'b0;
      cmd_op    = 8'd0;
      cmd_addr  = 8'd0;
      cmd_wdata = 32'd0;

      while (!rsp_valid) begin
        @(posedge clk);
      end
      rdata = rsp_rdata;
    end
  endtask

  task automatic write_reg(input logic [7:0] addr, input logic [31:0] data);
    logic [31:0] unused_rdata;
    begin
      send_cmd(CMD_WRITE, addr, data, unused_rdata);
    end
  endtask

  task automatic read_reg(input logic [7:0] addr, output logic [31:0] data);
    begin
      send_cmd(CMD_READ, addr, 32'd0, data);
    end
  endtask

  task automatic start_core;
    logic [31:0] unused_rdata;
    begin
      send_cmd(CMD_START, 8'd0, 32'd0, unused_rdata);
    end
  endtask

  task automatic write_pub_seed(input logic [127:0] pub_seed);
    logic [7:0] reg_addr;
    begin
      for (int word = 0; word < 4; word++) begin
        reg_addr = REG_PUB_SEED_BASE + word[7:0];
        write_reg(reg_addr, pub_seed[32 * word +: 32]);
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
        write_reg(reg_addr, addr_value[32 * word +: 32]);
      end
    end
  endtask

  task automatic write_input_lane(input int lane, input logic [255:0] input_value);
    logic [7:0] reg_addr;
    logic [7:0] lane_base;
    begin
      lane_base = {3'd0, lane[1:0], 3'd0};
      for (int word = 0; word < 8; word++) begin
        reg_addr = REG_INPUT_BASE + lane_base + word[7:0];
        write_reg(reg_addr, input_value[32 * word +: 32]);
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
        read_reg(reg_addr, word_data);
        output_value[32 * word +: 32] = word_data;
      end
    end
  endtask

  task automatic poll_until_done(input int case_id, output int poll_count);
    logic [31:0] status;
    begin
      poll_count = 0;
      do begin
        read_reg(REG_STATUS, status);
        poll_count++;
        if (status[STATUS_ERROR_BIT]) begin
          $fatal(1, "wrapper reported error status 0x%08x at case %0d",
                 status, case_id);
        end
        if (poll_count > 80) begin
          $fatal(1, "wrapper status timeout at case %0d last_status=0x%08x",
                 case_id, status);
        end
      end while (!status[STATUS_DONE_BIT]);

      if (busy || !done || error) begin
        $fatal(1, "wrapper pins mismatch after done at case %0d busy=%0b done=%0b error=%0b",
               case_id, busy, done, error);
      end
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
      output int poll_count
  );
    begin
      write_pub_seed(pub_seed);
      write_addr_lane(0, addr0);
      write_addr_lane(1, addr1);
      write_addr_lane(2, addr2);
      write_addr_lane(3, addr3);
      write_input_lane(0, in0);
      write_input_lane(1, in1);
      write_input_lane(2, in2);
      write_input_lane(3, in3);
      write_reg(REG_CONFIG, {30'd0, expected_inblocks[1:0]});
      start_core();
      poll_until_done(case_id, poll_count);
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
    int poll_count;
    int poll_min [0:1];
    int poll_max [0:1];
    int poll_cases [0:1];
    longint poll_sum [0:1];
    real poll_avg;
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
      poll_min[phase] = 32'h7fffffff;
      poll_max[phase] = 0;
      poll_cases[phase] = 0;
      poll_sum[phase] = 0;
    end

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
          $fatal(1, "failed to read wrapper input case %0d from %s",
                 case_id, input_path[phase]);
        end

        rc = $fscanf(expected_fd, "%d %h %h %h %h",
                     exp_inblocks, exp0, exp1, exp2, exp3);
        if (rc != 5) begin
          $fatal(1, "failed to read wrapper expected case %0d from %s",
                 expected_case_id, expected_path);
        end
        if (exp_inblocks != expected_inblocks[phase]) begin
          $fatal(1, "expected file inblocks mismatch at case %0d: expected %0d got %0d",
                 expected_case_id, expected_inblocks[phase], exp_inblocks);
        end

        run_case(expected_case_id, expected_inblocks[phase],
                 pub_seed, addr0, addr1, addr2, addr3, in0, in1, in2, in3,
                 poll_count);

        if (poll_count < poll_min[phase]) begin
          poll_min[phase] = poll_count;
        end
        if (poll_count > poll_max[phase]) begin
          poll_max[phase] = poll_count;
        end
        poll_cases[phase]++;
        poll_sum[phase] += longint'(poll_count);

        read_output_lane(0, got0);
        read_output_lane(1, got1);
        read_output_lane(2, got2);
        read_output_lane(3, got3);

        if (got0 !== exp0) begin
          $display("FAIL spx_cop_wrapper inblocks=%0d case=%0d lane=0",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp0);
          $display("  got      %h", got0);
          errors++;
        end
        if (got1 !== exp1) begin
          $display("FAIL spx_cop_wrapper inblocks=%0d case=%0d lane=1",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp1);
          $display("  got      %h", got1);
          errors++;
        end
        if (got2 !== exp2) begin
          $display("FAIL spx_cop_wrapper inblocks=%0d case=%0d lane=2",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp2);
          $display("  got      %h", got2);
          errors++;
        end
        if (got3 !== exp3) begin
          $display("FAIL spx_cop_wrapper inblocks=%0d case=%0d lane=3",
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
      $fatal(1, "FAIL spx_cop_wrapper mismatches=%0d", errors);
    end

    for (int phase = 0; phase < 2; phase++) begin
      poll_avg = poll_sum[phase];
      poll_avg = poll_avg / poll_cases[phase];
      $display("STATUS_POLLS spx_cop_wrapper inblocks=%0d min=%0d max=%0d avg=%0.2f",
               expected_inblocks[phase], poll_min[phase], poll_max[phase], poll_avg);
    end
    $display("PASS spx_cop_wrapper inblocks=1,2 (%0d cases)", expected_case_id);
    $finish;
  end
endmodule
