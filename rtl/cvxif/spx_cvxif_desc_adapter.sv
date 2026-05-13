module spx_cvxif_desc_adapter (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        instr_valid,
    output logic        instr_ready,
    input  logic [7:0]  instr_op,
    input  logic [31:0] instr_rs1,

    output logic        instr_resp_valid,
    output logic [31:0] instr_resp_data,
    output logic        instr_illegal,

    output logic        desc_start,
    output logic [31:0] desc_addr,
    input  logic        desc_busy,
    input  logic        desc_done,
    input  logic        desc_error,
    input  logic [3:0]  desc_error_code
);
  timeunit 1ns;
  timeprecision 1ps;

  localparam logic [7:0] INSTR_SPX_SET_DESC = 8'h10;
  localparam logic [7:0] INSTR_SPX_START    = 8'h11;
  localparam logic [7:0] INSTR_SPX_STATUS   = 8'h12;
  localparam logic [7:0] INSTR_SPX_CLEAR    = 8'h13;
  localparam logic [7:0] INSTR_SPX_WAIT     = 8'h14;

  logic [31:0] desc_addr_q;
  logic        sticky_done_q;
  logic        sticky_error_q;
  logic [3:0]  sticky_error_code_q;
  logic        desc_done_seen_q;

  logic instr_accept;
  logic decoded_legal;
  logic start_issue;
  logic clear_issue;
  logic desc_done_edge;
  logic live_done;
  logic live_error;
  logic [3:0] live_error_code;
  logic [31:0] live_status;
  logic [31:0] response_status;

  assign instr_ready  = 1'b1;
  assign instr_accept = instr_valid && instr_ready;
  assign desc_addr    = desc_addr_q;
  assign desc_start   = start_issue;

  assign desc_done_edge = desc_done && !desc_done_seen_q;
  assign start_issue = instr_accept && (instr_op == INSTR_SPX_START) &&
                       decoded_legal && !desc_busy;
  assign clear_issue = instr_accept && (instr_op == INSTR_SPX_CLEAR) &&
                       decoded_legal;

  always_comb begin
    decoded_legal = 1'b1;
    unique case (instr_op)
      INSTR_SPX_SET_DESC,
      INSTR_SPX_START,
      INSTR_SPX_STATUS,
      INSTR_SPX_CLEAR,
      INSTR_SPX_WAIT: begin
        decoded_legal = 1'b1;
      end
      default: begin
        decoded_legal = 1'b0;
      end
    endcase
  end

  always_comb begin
    live_done       = sticky_done_q || desc_done_edge;
    live_error      = sticky_error_q || (desc_done_edge && desc_error);
    live_error_code = sticky_error_q ? sticky_error_code_q :
                      ((desc_done_edge && desc_error) ? desc_error_code : 4'd0);

    live_status = 32'd0;
    live_status[0] = desc_busy;
    live_status[1] = live_done;
    live_status[2] = live_error;
    live_status[7:4] = live_error_code;
  end

  always_comb begin
    response_status = live_status;

    if (start_issue) begin
      response_status = 32'd0;
      response_status[0] = 1'b1;
    end else if (clear_issue) begin
      response_status = 32'd0;
      response_status[0] = desc_busy;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      desc_addr_q          <= 32'd0;
      sticky_done_q        <= 1'b0;
      sticky_error_q       <= 1'b0;
      sticky_error_code_q  <= 4'd0;
      desc_done_seen_q     <= 1'b0;
      instr_resp_valid     <= 1'b0;
      instr_resp_data      <= 32'd0;
      instr_illegal        <= 1'b0;
    end else begin
      desc_done_seen_q <= desc_done;

      if (desc_done_edge) begin
        sticky_done_q       <= 1'b1;
        sticky_error_q      <= desc_error;
        sticky_error_code_q <= desc_error ? desc_error_code : 4'd0;
      end

      instr_resp_valid <= instr_accept;
      instr_resp_data  <= decoded_legal ? response_status : 32'd0;
      instr_illegal    <= instr_accept && !decoded_legal;

      if (instr_accept && decoded_legal) begin
        unique case (instr_op)
          INSTR_SPX_SET_DESC: begin
            desc_addr_q <= instr_rs1;
          end
          INSTR_SPX_START: begin
            if (!desc_busy) begin
              sticky_done_q       <= 1'b0;
              sticky_error_q      <= 1'b0;
              sticky_error_code_q <= 4'd0;
            end
          end
          INSTR_SPX_CLEAR: begin
            sticky_done_q       <= 1'b0;
            sticky_error_q      <= 1'b0;
            sticky_error_code_q <= 4'd0;
          end
          default: begin
          end
        endcase
      end
    end
  end
endmodule
