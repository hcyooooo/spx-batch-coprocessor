module tb_wots_chainx4_core;
  timeunit 1ns;
  timeprecision 1ps;

  logic clk;
  logic rst_n;
  logic start;
  logic done;
  logic busy;
  logic error;

  logic [127:0] pub_seed;
  logic [255:0] addr0;
  logic [255:0] addr1;
  logic [255:0] addr2;
  logic [255:0] addr3;
  logic [127:0] in0;
  logic [127:0] in1;
  logic [127:0] in2;
  logic [127:0] in3;
  logic [7:0] start_step;
  logic [7:0] num_steps;
  logic [127:0] out0;
  logic [127:0] out1;
  logic [127:0] out2;
  logic [127:0] out3;

  logic         wots_req_valid;
  logic         wots_req_ready;
  logic [127:0] wots_req_pub_seed;
  logic [255:0] wots_req_addr0;
  logic [255:0] wots_req_addr1;
  logic [255:0] wots_req_addr2;
  logic [255:0] wots_req_addr3;
  logic [255:0] wots_req_in0;
  logic [255:0] wots_req_in1;
  logic [255:0] wots_req_in2;
  logic [255:0] wots_req_in3;
  logic         wots_rsp_valid;
  logic [127:0] wots_rsp_out0;
  logic [127:0] wots_rsp_out1;
  logic [127:0] wots_rsp_out2;
  logic [127:0] wots_rsp_out3;
  logic         thash_core_start;
  logic         thash_busy_q;

  spx_wots_chainx4_core dut (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .pub_seed(pub_seed),
      .addr0(addr0),
      .addr1(addr1),
      .addr2(addr2),
      .addr3(addr3),
      .in0(in0),
      .in1(in1),
      .in2(in2),
      .in3(in3),
      .start_step(start_step),
      .num_steps(num_steps),
      .done(done),
      .busy(busy),
      .error(error),
      .out0(out0),
      .out1(out1),
      .out2(out2),
      .out3(out3),
      .wots_req_valid(wots_req_valid),
      .wots_req_ready(wots_req_ready),
      .wots_req_pub_seed(wots_req_pub_seed),
      .wots_req_addr0(wots_req_addr0),
      .wots_req_addr1(wots_req_addr1),
      .wots_req_addr2(wots_req_addr2),
      .wots_req_addr3(wots_req_addr3),
      .wots_req_in0(wots_req_in0),
      .wots_req_in1(wots_req_in1),
      .wots_req_in2(wots_req_in2),
      .wots_req_in3(wots_req_in3),
      .wots_rsp_valid(wots_rsp_valid),
      .wots_rsp_out0(wots_rsp_out0),
      .wots_rsp_out1(wots_rsp_out1),
      .wots_rsp_out2(wots_rsp_out2),
      .wots_rsp_out3(wots_rsp_out3)
  );

  assign wots_req_ready = !thash_busy_q;
  assign thash_core_start = wots_req_valid && wots_req_ready;

  spx_thashx4_core u_shared_thashx4_core (
      .clk(clk),
      .rst_n(rst_n),
      .start(thash_core_start),
      .inblocks(2'd1),
      .pub_seed(wots_req_pub_seed),
      .addr0(wots_req_addr0),
      .addr1(wots_req_addr1),
      .addr2(wots_req_addr2),
      .addr3(wots_req_addr3),
      .in0(wots_req_in0),
      .in1(wots_req_in1),
      .in2(wots_req_in2),
      .in3(wots_req_in3),
      .done(wots_rsp_valid),
      .out0(wots_rsp_out0),
      .out1(wots_rsp_out1),
      .out2(wots_rsp_out2),
      .out3(wots_rsp_out3)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      thash_busy_q <= 1'b0;
    end else if (thash_core_start) begin
      thash_busy_q <= 1'b1;
    end else if (wots_rsp_valid) begin
      thash_busy_q <= 1'b0;
    end
  end

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic reset_dut;
    begin
      rst_n      = 1'b0;
      start      = 1'b0;
      pub_seed   = '0;
      addr0      = '0;
      addr1      = '0;
      addr2      = '0;
      addr3      = '0;
      in0        = '0;
      in1        = '0;
      in2        = '0;
      in3        = '0;
      start_step = '0;
      num_steps  = '0;
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
      while (!done && cycles < 1000) begin
        @(posedge clk);
        cycles++;
      end

      if (!done) begin
        $fatal(1, "wots_chainx4 timeout at case %0d", case_id);
      end
      if (error) begin
        $fatal(1, "wots_chainx4 reported error at case %0d", case_id);
      end

      latency_cycles = cycles;
      @(posedge clk);
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
    int latency;
    int errors;
    longint total_cycles;
    longint total_steps;
    longint total_thash_equiv;
    real cycles_per_step;
    real cycles_per_thash_equiv;
    logic [127:0] exp0;
    logic [127:0] exp1;
    logic [127:0] exp2;
    logic [127:0] exp3;

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
    total_cycles = 0;
    total_steps = 0;
    total_thash_equiv = 0;

    for (int case_id = 0; case_id < num_cases; case_id++) begin
      rc = $fscanf(fd, "%d %d %d %h %h %h %h %h %h %h %h %h %h %h %h %h",
                   case_id_file, start_step_i, num_steps_i, pub_seed,
                   addr0, addr1, addr2, addr3,
                   in0, in1, in2, in3,
                   exp0, exp1, exp2, exp3);
      if (rc != 16) begin
        $fatal(1, "failed to read WOTS chain x4 case %0d from %s",
               case_id, vectors_path);
      end
      if (case_id_file != case_id) begin
        $fatal(1, "case id mismatch: expected %0d got %0d",
               case_id, case_id_file);
      end

      start_step = start_step_i[7:0];
      num_steps = num_steps_i[7:0];
      run_case(case_id, latency);

      if (out0 !== exp0) begin
        $display("FAIL wots_chainx4 case=%0d lane=0", case_id);
        $display("  expected %h", exp0);
        $display("  got      %h", out0);
        errors++;
      end
      if (out1 !== exp1) begin
        $display("FAIL wots_chainx4 case=%0d lane=1", case_id);
        $display("  expected %h", exp1);
        $display("  got      %h", out1);
        errors++;
      end
      if (out2 !== exp2) begin
        $display("FAIL wots_chainx4 case=%0d lane=2", case_id);
        $display("  expected %h", exp2);
        $display("  got      %h", out2);
        errors++;
      end
      if (out3 !== exp3) begin
        $display("FAIL wots_chainx4 case=%0d lane=3", case_id);
        $display("  expected %h", exp3);
        $display("  got      %h", out3);
        errors++;
      end

      total_cycles += longint'(latency);
      total_steps += longint'(num_steps_i);
      total_thash_equiv += longint'(4 * num_steps_i);
      cycles_per_step = latency;
      cycles_per_step = cycles_per_step / num_steps_i;
      cycles_per_thash_equiv = latency;
      cycles_per_thash_equiv = cycles_per_thash_equiv / (4 * num_steps_i);
      $display("CHAIN_PERF case=%0d start_step=%0d num_steps=%0d cycles=%0d cycles_per_chain_step=%0.2f cycles_per_thash_equiv=%0.2f",
               case_id, start_step_i, num_steps_i, latency,
               cycles_per_step, cycles_per_thash_equiv);
    end

    $fclose(fd);

    if (errors != 0) begin
      $fatal(1, "FAIL wots_chainx4_core mismatches=%0d", errors);
    end

    cycles_per_step = total_cycles;
    cycles_per_step = cycles_per_step / total_steps;
    cycles_per_thash_equiv = total_cycles;
    cycles_per_thash_equiv = cycles_per_thash_equiv / total_thash_equiv;
    $display("CHAIN_PERF_SUMMARY cases=%0d total_cycles=%0d total_steps=%0d avg_cycles_per_chain_step=%0.2f avg_cycles_per_thash_equiv=%0.2f",
             num_cases, total_cycles, total_steps,
             cycles_per_step, cycles_per_thash_equiv);
    $display("PASS wots_chainx4_core (%0d cases)", num_cases);
    $finish;
  end
endmodule
