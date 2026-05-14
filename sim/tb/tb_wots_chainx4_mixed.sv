module tb_wots_chainx4_mixed;
  timeunit 1ns;
  timeprecision 1ps;

  logic clk;
  logic rst_n;
  logic start;
  logic mixed_mode;
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
  logic [31:0] start_steps_packed;
  logic [31:0] num_steps_packed;
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
      .mixed_mode(mixed_mode),
      .start_steps_packed(start_steps_packed),
      .num_steps_packed(num_steps_packed),
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

  function automatic int lane_byte(input logic [31:0] packed_value, input int lane);
    begin
      lane_byte = int'(packed_value[8 * lane +: 8]);
    end
  endfunction

  function automatic int useful_lane_ops(input logic [31:0] packed_steps);
    begin
      useful_lane_ops = lane_byte(packed_steps, 0) +
                        lane_byte(packed_steps, 1) +
                        lane_byte(packed_steps, 2) +
                        lane_byte(packed_steps, 3);
    end
  endfunction

  function automatic int max_lane_steps(input logic [31:0] packed_steps);
    int max_steps;
    begin
      max_steps = 0;
      for (int lane = 0; lane < 4; lane++) begin
        if (lane_byte(packed_steps, lane) > max_steps) begin
          max_steps = lane_byte(packed_steps, lane);
        end
      end
      max_lane_steps = max_steps;
    end
  endfunction

  function automatic bit all_lanes_equal(input logic [31:0] packed_value);
    begin
      all_lanes_equal = (packed_value[7:0] == packed_value[15:8]) &&
                        (packed_value[7:0] == packed_value[23:16]) &&
                        (packed_value[7:0] == packed_value[31:24]);
    end
  endfunction

  task automatic reset_dut;
    begin
      rst_n              = 1'b0;
      start              = 1'b0;
      mixed_mode         = 1'b1;
      pub_seed           = '0;
      addr0              = '0;
      addr1              = '0;
      addr2              = '0;
      addr3              = '0;
      in0                = '0;
      in1                = '0;
      in2                = '0;
      in3                = '0;
      start_step         = '0;
      num_steps          = '0;
      start_steps_packed = '0;
      num_steps_packed   = '0;
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
      while (!done && cycles < 2000) begin
        @(posedge clk);
        cycles++;
      end

      if (!done) begin
        $fatal(1, "wots_chainx4_mixed timeout at case %0d", case_id);
      end
      if (error) begin
        $fatal(1, "wots_chainx4_mixed reported error at case %0d", case_id);
      end

      latency_cycles = cycles;
      @(posedge clk);
    end
  endtask

  task automatic compare_lane(input int case_id,
                              input int lane,
                              input logic [127:0] expected,
                              input logic [127:0] got,
                              inout int errors);
    begin
      if (got !== expected) begin
        $display("FAIL wots_chainx4_mixed case=%0d lane=%0d", case_id, lane);
        $display("  expected %h", expected);
        $display("  got      %h", got);
        errors++;
      end
    end
  endtask

  initial begin
    string vectors_path;
    int fd;
    int rc;
    int num_cases;
    int case_id_file;
    int latency;
    int uniform_latency;
    int errors;
    int useful_ops;
    int max_steps;
    int physical_ops;
    longint total_cycles;
    longint total_useful_ops;
    longint total_physical_ops;
    real lane_utilization;
    real cycles_per_useful;
    real speedup_vs_scalar;
    logic [127:0] exp0;
    logic [127:0] exp1;
    logic [127:0] exp2;
    logic [127:0] exp3;
    logic [127:0] mixed_out0;
    logic [127:0] mixed_out1;
    logic [127:0] mixed_out2;
    logic [127:0] mixed_out3;

    if (!$value$plusargs("VECTORS=%s", vectors_path)) begin
      vectors_path = "sim/vectors/wots_chainx4_mixed_vectors.hex";
    end

    reset_dut();

    fd = $fopen(vectors_path, "r");
    if (fd == 0) begin
      $fatal(1, "failed to open %s", vectors_path);
    end

    rc = $fscanf(fd, "%d", num_cases);
    if (rc != 1) begin
      $fatal(1, "failed to read mixed case count from %s", vectors_path);
    end

    errors = 0;
    total_cycles = 0;
    total_useful_ops = 0;
    total_physical_ops = 0;

    $display("WOTS_CHAINX4_MIXED_TABLE");
    $display("case lane_steps max_steps useful_lane_ops physical_lane_ops lane_utilization cycles cycles_per_useful_thash speedup_vs_scalar_descriptors");
    $display("--------------------------------------------------------------------------------------------------------------------------------");

    for (int case_id = 0; case_id < num_cases; case_id++) begin
      rc = $fscanf(fd, "%d %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                   case_id_file, start_steps_packed, num_steps_packed, pub_seed,
                   addr0, addr1, addr2, addr3,
                   in0, in1, in2, in3,
                   exp0, exp1, exp2, exp3);
      if (rc != 16) begin
        $fatal(1, "failed to read WOTS mixed case %0d from %s",
               case_id, vectors_path);
      end
      if (case_id_file != case_id) begin
        $fatal(1, "mixed case id mismatch: expected %0d got %0d",
               case_id, case_id_file);
      end

      mixed_mode = 1'b1;
      start_step = start_steps_packed[7:0];
      num_steps = num_steps_packed[7:0];
      run_case(case_id, latency);

      compare_lane(case_id, 0, exp0, out0, errors);
      compare_lane(case_id, 1, exp1, out1, errors);
      compare_lane(case_id, 2, exp2, out2, errors);
      compare_lane(case_id, 3, exp3, out3, errors);

      mixed_out0 = out0;
      mixed_out1 = out1;
      mixed_out2 = out2;
      mixed_out3 = out3;

      if (all_lanes_equal(start_steps_packed) &&
          all_lanes_equal(num_steps_packed)) begin
        mixed_mode = 1'b0;
        start_step = start_steps_packed[7:0];
        num_steps = num_steps_packed[7:0];
        run_case(case_id, uniform_latency);
        if ((out0 !== mixed_out0) || (out1 !== mixed_out1) ||
            (out2 !== mixed_out2) || (out3 !== mixed_out3)) begin
          $fatal(1, "uniform equivalence failed for mixed case %0d", case_id);
        end
        $display("WOTS_CHAINX4_MIXED_UNIFORM_EQUIV case=%0d mixed_cycles=%0d uniform_cycles=%0d",
                 case_id, latency, uniform_latency);
      end

      useful_ops = useful_lane_ops(num_steps_packed);
      max_steps = max_lane_steps(num_steps_packed);
      physical_ops = 4 * max_steps;
      lane_utilization = (physical_ops == 0) ? 0.0 :
                         (real'(useful_ops) / real'(physical_ops));
      cycles_per_useful = (useful_ops == 0) ? 0.0 :
                          (real'(latency) / real'(useful_ops));
      speedup_vs_scalar = (latency == 0) ? 0.0 :
                          (real'(57 * useful_ops) / real'(latency));

      total_cycles += longint'(latency);
      total_useful_ops += longint'(useful_ops);
      total_physical_ops += longint'(physical_ops);

      $display("%4d [%0d,%0d,%0d,%0d] %9d %15d %17d %16.2f %6d %24.2f %29.2fx",
               case_id,
               lane_byte(num_steps_packed, 0), lane_byte(num_steps_packed, 1),
               lane_byte(num_steps_packed, 2), lane_byte(num_steps_packed, 3),
               max_steps, useful_ops, physical_ops, lane_utilization,
               latency, cycles_per_useful, speedup_vs_scalar);
    end

    $fclose(fd);

    if (errors != 0) begin
      $fatal(1, "FAIL wots_chainx4_mixed mismatches=%0d", errors);
    end

    lane_utilization = (total_physical_ops == 0) ? 0.0 :
                       (real'(total_useful_ops) / real'(total_physical_ops));
    cycles_per_useful = (total_useful_ops == 0) ? 0.0 :
                        (real'(total_cycles) / real'(total_useful_ops));
    $display("WOTS_CHAINX4_MIXED_SUMMARY cases=%0d total_cycles=%0d useful_lane_ops=%0d physical_lane_ops=%0d lane_utilization=%0.2f avg_cycles_per_useful_thash=%0.2f",
             num_cases, total_cycles, total_useful_ops, total_physical_ops,
             lane_utilization, cycles_per_useful);
    $display("PASS wots_chainx4_mixed (%0d cases)", num_cases);
    $finish;
  end
endmodule
