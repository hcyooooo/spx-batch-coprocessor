module spx_cvxif_real_adapter (
    input logic clk,
    input logic rst_n,

    cv32e40x_if_xif.coproc_compressed xif_compressed_if,
    cv32e40x_if_xif.coproc_issue      xif_issue_if,
    cv32e40x_if_xif.coproc_commit     xif_commit_if,
    cv32e40x_if_xif.coproc_mem        xif_mem_if,
    cv32e40x_if_xif.coproc_mem_result xif_mem_result_if,
    cv32e40x_if_xif.coproc_result     xif_result_if,

    output logic        instr_valid,
    input  logic        instr_ready,
    output logic [7:0]  instr_op,
    output logic [31:0] instr_rs1,

    input logic        instr_resp_valid,
    input logic [31:0] instr_resp_data,
    input logic        instr_illegal
);
  timeunit 1ns;
  timeprecision 1ps;

  localparam logic [6:0] SPX_OPCODE_CUSTOM0 = 7'b0001011;
  localparam logic [6:0] SPX_FUNCT7         = 7'h5a;

  localparam logic [2:0] SPX_F3_SET_DESC = 3'h0;
  localparam logic [2:0] SPX_F3_START    = 3'h1;
  localparam logic [2:0] SPX_F3_STATUS   = 3'h2;
  localparam logic [2:0] SPX_F3_CLEAR    = 3'h3;

  localparam logic [7:0] INSTR_SPX_SET_DESC = 8'h10;
  localparam logic [7:0] INSTR_SPX_START    = 8'h11;
  localparam logic [7:0] INSTR_SPX_STATUS   = 8'h12;
  localparam logic [7:0] INSTR_SPX_CLEAR    = 8'h13;

  localparam logic [5:0] EXC_ILLEGAL_INSN = 6'd2;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_WAIT_COMMIT,
    ST_ISSUE_DESC,
    ST_WAIT_DESC_RESP,
    ST_RESULT
  } state_e;

  state_e state_q;

  logic [7:0]  pending_op_q;
  logic [31:0] pending_rs1_q;
  logic [4:0]  pending_rd_q;
  logic [xif_issue_if.X_ID_WIDTH-1:0] pending_id_q;
  logic        pending_we_q;

  logic [31:0] result_data_q;
  logic [4:0]  result_rd_q;
  logic [xif_issue_if.X_ID_WIDTH-1:0] result_id_q;
  logic        result_we_q;
  logic        result_exc_q;
  logic [5:0]  result_exccode_q;
  logic        result_valid_q;

  logic        issue_supported;
  logic        issue_operands_ok;
  logic        issue_accept;
  logic        issue_fire;
  logic [7:0]  issue_decoded_op;
  logic [4:0]  issue_rd;
  logic [4:0]  issue_rs1;
  logic [4:0]  issue_rs2;
  logic [2:0]  issue_funct3;
  logic [6:0]  issue_funct7;
  logic [6:0]  issue_opcode;

  logic commit_match;
  logic commit_take;
  logic desc_issue_fire;
  logic result_fire;

  assign issue_opcode = xif_issue_if.issue_req.instr[6:0];
  assign issue_rd     = xif_issue_if.issue_req.instr[11:7];
  assign issue_funct3 = xif_issue_if.issue_req.instr[14:12];
  assign issue_rs1    = xif_issue_if.issue_req.instr[19:15];
  assign issue_rs2    = xif_issue_if.issue_req.instr[24:20];
  assign issue_funct7 = xif_issue_if.issue_req.instr[31:25];

  always_comb begin
    issue_decoded_op = 8'h00;
    issue_supported  = 1'b0;

    if ((issue_opcode == SPX_OPCODE_CUSTOM0) &&
        (issue_funct7 == SPX_FUNCT7) &&
        (issue_rs2 == 5'd0)) begin
      unique case (issue_funct3)
        SPX_F3_SET_DESC: begin
          issue_supported  = 1'b1;
          issue_decoded_op = INSTR_SPX_SET_DESC;
        end
        SPX_F3_START: begin
          issue_supported  = (issue_rs1 == 5'd0);
          issue_decoded_op = INSTR_SPX_START;
        end
        SPX_F3_STATUS: begin
          issue_supported  = (issue_rs1 == 5'd0);
          issue_decoded_op = INSTR_SPX_STATUS;
        end
        SPX_F3_CLEAR: begin
          issue_supported  = (issue_rs1 == 5'd0);
          issue_decoded_op = INSTR_SPX_CLEAR;
        end
        default: begin
          issue_supported  = 1'b0;
          issue_decoded_op = 8'h00;
        end
      endcase
    end
  end

  always_comb begin
    issue_operands_ok = 1'b1;
    if (issue_decoded_op == INSTR_SPX_SET_DESC) begin
      issue_operands_ok = xif_issue_if.issue_req.rs_valid[0];
    end
  end

  assign issue_accept = xif_issue_if.issue_valid && issue_supported &&
                        issue_operands_ok && (state_q == ST_IDLE);
  assign issue_fire   = xif_issue_if.issue_valid && xif_issue_if.issue_ready;

  assign xif_issue_if.issue_ready          = issue_supported ? (state_q == ST_IDLE) : 1'b1;
  assign xif_issue_if.issue_resp.accept    = issue_accept;
  assign xif_issue_if.issue_resp.writeback = issue_accept && (issue_rd != 5'd0);
  assign xif_issue_if.issue_resp.dualwrite = 1'b0;
  assign xif_issue_if.issue_resp.dualread  = 3'b000;
  assign xif_issue_if.issue_resp.loadstore = 1'b0;
  assign xif_issue_if.issue_resp.ecswrite  = 1'b0;
  assign xif_issue_if.issue_resp.exc       = 1'b0;

  assign commit_match = (state_q == ST_WAIT_COMMIT) &&
                        (xif_commit_if.commit.id == pending_id_q);
  assign commit_take  = xif_commit_if.commit_valid && commit_match &&
                        !xif_commit_if.commit.commit_kill;

  assign instr_valid     = ((state_q == ST_ISSUE_DESC) || commit_take) && !result_valid_q;
  assign instr_op        = pending_op_q;
  assign instr_rs1       = pending_rs1_q;
  assign desc_issue_fire = instr_valid && instr_ready;

  assign result_fire = result_valid_q && xif_result_if.result_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q          <= ST_IDLE;
      pending_op_q     <= 8'h00;
      pending_rs1_q    <= 32'd0;
      pending_rd_q     <= 5'd0;
      pending_id_q     <= '0;
      pending_we_q     <= 1'b0;
      result_data_q    <= 32'd0;
      result_rd_q      <= 5'd0;
      result_id_q      <= '0;
      result_we_q      <= 1'b0;
      result_exc_q     <= 1'b0;
      result_exccode_q <= 6'd0;
      result_valid_q   <= 1'b0;
    end else begin
      if (result_fire) begin
        result_valid_q <= 1'b0;
      end

      unique case (state_q)
        ST_IDLE: begin
          if (issue_fire && issue_accept) begin
            state_q      <= ST_WAIT_COMMIT;
            pending_op_q <= issue_decoded_op;
            pending_rs1_q <= (issue_decoded_op == INSTR_SPX_SET_DESC) ?
                             xif_issue_if.issue_req.rs[0] : 32'd0;
            pending_rd_q <= issue_rd;
            pending_id_q <= xif_issue_if.issue_req.id;
            pending_we_q <= (issue_rd != 5'd0);
          end
        end

        ST_WAIT_COMMIT: begin
          if (xif_commit_if.commit_valid && commit_match) begin
            if (xif_commit_if.commit.commit_kill) begin
              state_q <= ST_IDLE;
            end else if (desc_issue_fire) begin
              state_q <= ST_WAIT_DESC_RESP;
            end else begin
              state_q <= ST_ISSUE_DESC;
            end
          end
        end

        ST_ISSUE_DESC: begin
          if (desc_issue_fire) begin
            state_q <= ST_WAIT_DESC_RESP;
          end
        end

        ST_WAIT_DESC_RESP: begin
          if (instr_resp_valid) begin
            state_q          <= ST_RESULT;
            result_valid_q   <= 1'b1;
            result_id_q      <= pending_id_q;
            result_rd_q      <= pending_rd_q;
            result_we_q      <= pending_we_q && !instr_illegal;
            result_data_q    <= instr_resp_data;
            result_exc_q     <= instr_illegal;
            result_exccode_q <= instr_illegal ? EXC_ILLEGAL_INSN : 6'd0;
          end
        end

        ST_RESULT: begin
          if (result_fire) begin
            state_q <= ST_IDLE;
          end
        end

        default: begin
          state_q        <= ST_IDLE;
          result_valid_q <= 1'b0;
        end
      endcase
    end
  end

  assign xif_result_if.result_valid   = result_valid_q;
  assign xif_result_if.result.id      = result_id_q;
  assign xif_result_if.result.data    = result_data_q;
  assign xif_result_if.result.rd      = result_rd_q;
  assign xif_result_if.result.we      = result_we_q;
  assign xif_result_if.result.ecsdata = 6'd0;
  assign xif_result_if.result.ecswe   = 3'd0;
  assign xif_result_if.result.exc     = result_exc_q;
  assign xif_result_if.result.exccode = result_exccode_q;
  assign xif_result_if.result.err     = 1'b0;
  assign xif_result_if.result.dbg     = 1'b0;

  assign xif_compressed_if.compressed_ready       = 1'b1;
  assign xif_compressed_if.compressed_resp.instr  = 32'd0;
  assign xif_compressed_if.compressed_resp.accept = 1'b0;

  assign xif_mem_if.mem_valid = 1'b0;
  assign xif_mem_if.mem_req   = '0;

  logic unused_xif_inputs;
  assign unused_xif_inputs =
      xif_compressed_if.compressed_valid |
      (|xif_compressed_if.compressed_req) |
      (|xif_issue_if.issue_req) |
      xif_mem_if.mem_ready |
      (|xif_mem_if.mem_resp) |
      xif_mem_result_if.mem_result_valid |
      (|xif_mem_result_if.mem_result);

endmodule
