module tb_thashx4_core;
  timeunit 1ns;
  timeprecision 1ps;

  logic clk;
  logic rst_n;
  logic start;
  logic [1:0] inblocks;
  logic done;

  logic [127:0] pub_seed;
  logic [255:0] addr0;
  logic [255:0] addr1;
  logic [255:0] addr2;
  logic [255:0] addr3;
  logic [255:0] in0;
  logic [255:0] in1;
  logic [255:0] in2;
  logic [255:0] in3;
  logic [127:0] out0;
  logic [127:0] out1;
  logic [127:0] out2;
  logic [127:0] out3;

  spx_thashx4_core dut (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .inblocks(inblocks),
      .pub_seed(pub_seed),
      .addr0(addr0),
      .addr1(addr1),
      .addr2(addr2),
      .addr3(addr3),
      .in0(in0),
      .in1(in1),
      .in2(in2),
      .in3(in3),
      .done(done),
      .out0(out0),
      .out1(out1),
      .out2(out2),
      .out3(out3)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic reset_dut;
    begin
      rst_n    = 1'b0;
      start    = 1'b0;
      inblocks = 2'd0;
      pub_seed = '0;
      addr0    = '0;
      addr1    = '0;
      addr2    = '0;
      addr3    = '0;
      in0      = '0;
      in1      = '0;
      in2      = '0;
      in3      = '0;
      repeat (4) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic run_case(input int case_id, output int latency_cycles);
    int cycles;
    begin
      @(negedge clk);
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;

      cycles = 0;
      while (!done && cycles < 100) begin
        @(posedge clk);
        cycles++;
      end

      if (!done) begin
        $fatal(1, "thashx4 timeout at expected case %0d", case_id);
      end

      latency_cycles = cycles;
      @(posedge clk);
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
    int latency;
    int latency_min [0:1];
    int latency_max [0:1];
    int latency_count [0:1];
    longint latency_sum [0:1];
    real latency_avg;
    logic [127:0] exp0;
    logic [127:0] exp1;
    logic [127:0] exp2;
    logic [127:0] exp3;

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
      latency_min[phase] = 32'h7fffffff;
      latency_max[phase] = 0;
      latency_count[phase] = 0;
      latency_sum[phase] = 0;
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
          $fatal(1, "failed to read thashx4 input case %0d from %s",
                 case_id, input_path[phase]);
        end

        rc = $fscanf(expected_fd, "%d %h %h %h %h",
                     exp_inblocks, exp0, exp1, exp2, exp3);
        if (rc != 5) begin
          $fatal(1, "failed to read thashx4 expected case %0d from %s",
                 expected_case_id, expected_path);
        end
        if (exp_inblocks != expected_inblocks[phase]) begin
          $fatal(1, "expected file inblocks mismatch at case %0d: expected %0d got %0d",
                 expected_case_id, expected_inblocks[phase], exp_inblocks);
        end

        inblocks = expected_inblocks[phase][1:0];
        run_case(expected_case_id, latency);
        if (latency < latency_min[phase]) begin
          latency_min[phase] = latency;
        end
        if (latency > latency_max[phase]) begin
          latency_max[phase] = latency;
        end
        latency_count[phase]++;
        latency_sum[phase] += longint'(latency);

        if (out0 !== exp0) begin
          $display("FAIL thashx4 inblocks=%0d case=%0d lane=0",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp0);
          $display("  got      %h", out0);
          errors++;
        end
        if (out1 !== exp1) begin
          $display("FAIL thashx4 inblocks=%0d case=%0d lane=1",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp1);
          $display("  got      %h", out1);
          errors++;
        end
        if (out2 !== exp2) begin
          $display("FAIL thashx4 inblocks=%0d case=%0d lane=2",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp2);
          $display("  got      %h", out2);
          errors++;
        end
        if (out3 !== exp3) begin
          $display("FAIL thashx4 inblocks=%0d case=%0d lane=3",
                   expected_inblocks[phase], case_id);
          $display("  expected %h", exp3);
          $display("  got      %h", out3);
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
      $fatal(1, "FAIL thashx4_core mismatches=%0d", errors);
    end

    for (int phase = 0; phase < 2; phase++) begin
      latency_avg = latency_sum[phase];
      latency_avg = latency_avg / latency_count[phase];
      $display("LATENCY thashx4_core inblocks=%0d min=%0d max=%0d avg=%0.2f cycles",
               expected_inblocks[phase],
               latency_min[phase],
               latency_max[phase],
               latency_avg);
    end
    $display("PASS thashx4_core inblocks=1,2 (%0d cases)", expected_case_id);
    $finish;
  end
endmodule
