module tb_spx_cvxif_real_adapter_lint;
  timeunit 1ns;
  timeprecision 1ps;

  logic clk;
  logic rst_n;

  cv32e40x_if_xif #(
      .X_NUM_RS(2),
      .X_ID_WIDTH(4),
      .X_MEM_WIDTH(32),
      .X_RFR_WIDTH(32),
      .X_RFW_WIDTH(32),
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

  always_comb begin
    clk                    = 1'b0;
    rst_n                  = 1'b1;
    xif.compressed_valid   = 1'b0;
    xif.compressed_req     = '0;
    xif.issue_valid        = 1'b0;
    xif.issue_req          = '0;
    xif.commit_valid       = 1'b0;
    xif.commit             = '0;
    xif.mem_ready          = 1'b1;
    xif.mem_resp           = '0;
    xif.mem_result_valid   = 1'b0;
    xif.mem_result         = '0;
    xif.result_ready       = 1'b1;
    instr_ready            = 1'b1;
    instr_resp_valid       = 1'b0;
    instr_resp_data        = 32'd0;
    instr_illegal          = 1'b0;
  end

  logic unused_outputs;
  assign unused_outputs =
      xif.compressed_ready |
      (|xif.compressed_resp) |
      xif.issue_ready |
      (|xif.issue_resp) |
      xif.mem_valid |
      (|xif.mem_req) |
      xif.result_valid |
      (|xif.result) |
      instr_valid |
      (|instr_op) |
      (|instr_rs1);
endmodule
