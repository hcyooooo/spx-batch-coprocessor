module spx_cvxif_adapter (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        instr_valid,
    output logic        instr_ready,
    input  logic [7:0]  instr_op,
    input  logic [7:0]  instr_addr,
    input  logic [31:0] instr_rs1,
    input  logic [4:0]  instr_rd,

    output logic        instr_resp_valid,
    output logic [31:0] instr_resp_data,
    output logic [4:0]  instr_resp_rd,
    output logic        instr_illegal,
    output logic        instr_busy,
    output logic        instr_done,
    output logic        instr_error
);
  timeunit 1ns;
  timeprecision 1ps;

  localparam logic [7:0] INSTR_SPX_WR     = 8'h01;
  localparam logic [7:0] INSTR_SPX_RD     = 8'h02;
  localparam logic [7:0] INSTR_SPX_START  = 8'h03;
  localparam logic [7:0] INSTR_SPX_STATUS = 8'h04;
  localparam logic [7:0] INSTR_SPX_CLR    = 8'h05;

  localparam logic [7:0] CMD_WRITE = 8'h01;
  localparam logic [7:0] CMD_READ  = 8'h02;
  localparam logic [7:0] CMD_START = 8'h03;

  localparam logic [7:0] REG_STATUS = 8'h51;

  typedef enum logic {
    STATE_IDLE,
    STATE_WAIT_RSP
  } state_e;

  state_e state_q;

  logic        decoded_legal;
  logic [7:0]  decoded_cmd_op;
  logic [7:0]  decoded_cmd_addr;
  logic [31:0] decoded_cmd_wdata;

  logic        cmd_valid;
  logic        cmd_ready;
  logic [31:0] rsp_rdata;
  logic        rsp_valid;

  logic        instr_accept;
  logic [4:0]  pending_rd_q;

  assign instr_accept = instr_valid && instr_ready;

  always_comb begin
    decoded_legal     = 1'b1;
    decoded_cmd_op    = CMD_READ;
    decoded_cmd_addr  = instr_addr;
    decoded_cmd_wdata = 32'd0;

    unique case (instr_op)
      INSTR_SPX_WR: begin
        decoded_cmd_op    = CMD_WRITE;
        decoded_cmd_addr  = instr_addr;
        decoded_cmd_wdata = instr_rs1;
      end
      INSTR_SPX_RD: begin
        decoded_cmd_op   = CMD_READ;
        decoded_cmd_addr = instr_addr;
      end
      INSTR_SPX_START: begin
        decoded_cmd_op   = CMD_START;
        decoded_cmd_addr = 8'd0;
      end
      INSTR_SPX_STATUS: begin
        decoded_cmd_op   = CMD_READ;
        decoded_cmd_addr = REG_STATUS;
      end
      INSTR_SPX_CLR: begin
        decoded_cmd_op    = CMD_WRITE;
        decoded_cmd_addr  = REG_STATUS;
        decoded_cmd_wdata = 32'h0000_0006;
      end
      default: begin
        decoded_legal = 1'b0;
      end
    endcase
  end

  assign instr_ready = (state_q == STATE_IDLE) && (decoded_legal ? cmd_ready : 1'b1);

  assign cmd_valid = (state_q == STATE_IDLE) && instr_valid && decoded_legal;

  spx_cop_wrapper u_spx_cop_wrapper (
      .clk(clk),
      .rst_n(rst_n),
      .cmd_valid(cmd_valid),
      .cmd_ready(cmd_ready),
      .cmd_op(decoded_cmd_op),
      .cmd_addr(decoded_cmd_addr),
      .cmd_wdata(decoded_cmd_wdata),
      .rsp_rdata(rsp_rdata),
      .rsp_valid(rsp_valid),
      .busy(instr_busy),
      .done(instr_done),
      .error(instr_error)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q          <= STATE_IDLE;
      pending_rd_q     <= 5'd0;
      instr_resp_valid <= 1'b0;
      instr_resp_data  <= 32'd0;
      instr_resp_rd    <= 5'd0;
      instr_illegal    <= 1'b0;
    end else begin
      instr_resp_valid <= 1'b0;
      instr_resp_data  <= 32'd0;
      instr_resp_rd    <= pending_rd_q;
      instr_illegal    <= 1'b0;

      unique case (state_q)
        STATE_IDLE: begin
          if (instr_accept) begin
            pending_rd_q <= instr_rd;
            instr_resp_rd <= instr_rd;
            if (!decoded_legal) begin
              instr_resp_valid <= 1'b1;
              instr_illegal    <= 1'b1;
            end else begin
              state_q <= STATE_WAIT_RSP;
            end
          end
        end
        STATE_WAIT_RSP: begin
          if (rsp_valid) begin
            instr_resp_valid <= 1'b1;
            instr_resp_data  <= rsp_rdata;
            instr_resp_rd    <= pending_rd_q;
            state_q          <= STATE_IDLE;
          end
        end
        default: begin
          state_q <= STATE_IDLE;
        end
      endcase
    end
  end
endmodule
