module tb_keccakx4_core;
  timeunit 1ns;
  timeprecision 1ps;

  logic clk;
  logic rst_n;
  logic start;
  logic done;

  logic [1599:0] state0_i;
  logic [1599:0] state1_i;
  logic [1599:0] state2_i;
  logic [1599:0] state3_i;
  logic [1599:0] state0_o;
  logic [1599:0] state1_o;
  logic [1599:0] state2_o;
  logic [1599:0] state3_o;

  spx_keccakx4_core dut (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .state0_i(state0_i),
      .state1_i(state1_i),
      .state2_i(state2_i),
      .state3_i(state3_i),
      .done(done),
      .state0_o(state0_o),
      .state1_o(state1_o),
      .state2_o(state2_o),
      .state3_o(state3_o)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic reset_dut;
    begin
      rst_n    = 1'b0;
      start    = 1'b0;
      state0_i = '0;
      state1_i = '0;
      state2_i = '0;
      state3_i = '0;
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
      while (!done && cycles < 80) begin
        @(posedge clk);
        cycles++;
      end

      if (!done) begin
        $fatal(1, "keccakx4 timeout at case %0d", case_id);
      end

      latency_cycles = cycles;
      @(posedge clk);
    end
  endtask

  initial begin
    string vector_path;
    int fd;
    int rc;
    int num_cases;
    int errors;
    int latency;
    int latency_min;
    int latency_max;
    longint latency_sum;
    real latency_avg;
    logic [1599:0] exp0;
    logic [1599:0] exp1;
    logic [1599:0] exp2;
    logic [1599:0] exp3;

    if (!$value$plusargs("VECTORS=%s", vector_path)) begin
      vector_path = "sim/vectors/keccakx4_vectors.hex";
    end

    reset_dut();

    fd = $fopen(vector_path, "r");
    if (fd == 0) begin
      $fatal(1, "failed to open %s", vector_path);
    end

    rc = $fscanf(fd, "%d", num_cases);
    if (rc != 1) begin
      $fatal(1, "failed to read case count from %s", vector_path);
    end

    errors = 0;
    latency_min = 32'h7fffffff;
    latency_max = 0;
    latency_sum = 0;

    for (int case_id = 0; case_id < num_cases; case_id++) begin
      rc = $fscanf(fd, "%h %h %h %h %h %h %h %h",
                   state0_i, state1_i, state2_i, state3_i,
                   exp0, exp1, exp2, exp3);
      if (rc != 8) begin
        $fatal(1, "failed to read keccakx4 vector case %0d from %s",
               case_id, vector_path);
      end

      run_case(case_id, latency);
      if (latency < latency_min) begin
        latency_min = latency;
      end
      if (latency > latency_max) begin
        latency_max = latency;
      end
      latency_sum += longint'(latency);

      if (state0_o !== exp0) begin
        $display("FAIL keccakx4 case=%0d lane=0", case_id);
        $display("  expected %h", exp0);
        $display("  got      %h", state0_o);
        errors++;
      end
      if (state1_o !== exp1) begin
        $display("FAIL keccakx4 case=%0d lane=1", case_id);
        $display("  expected %h", exp1);
        $display("  got      %h", state1_o);
        errors++;
      end
      if (state2_o !== exp2) begin
        $display("FAIL keccakx4 case=%0d lane=2", case_id);
        $display("  expected %h", exp2);
        $display("  got      %h", state2_o);
        errors++;
      end
      if (state3_o !== exp3) begin
        $display("FAIL keccakx4 case=%0d lane=3", case_id);
        $display("  expected %h", exp3);
        $display("  got      %h", state3_o);
        errors++;
      end
    end

    $fclose(fd);

    if (errors != 0) begin
      $fatal(1, "FAIL keccakx4_core mismatches=%0d", errors);
    end

    latency_avg = latency_sum;
    latency_avg = latency_avg / num_cases;
    $display("LATENCY keccakx4_core min=%0d max=%0d avg=%0.2f cycles",
             latency_min, latency_max, latency_avg);
    $display("PASS keccakx4_core (%0d cases)", num_cases);
    $finish;
  end
endmodule
