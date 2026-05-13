module spx_cvxif_adapter_coarse (
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

  localparam logic [7:0] INSTR_SPX_SET_PTR       = 8'h10;
  localparam logic [7:0] INSTR_SPX_WR_NEXT       = 8'h11;
  localparam logic [7:0] INSTR_SPX_RD_NEXT       = 8'h12;
  localparam logic [7:0] INSTR_SPX_START_THASHX4 = 8'h13;
  localparam logic [7:0] INSTR_SPX_STATUS        = 8'h14;

  localparam logic [7:0] CMD_WRITE = 8'h01;
  localparam logic [7:0] CMD_READ  = 8'h02;
  localparam logic [7:0] CMD_START = 8'h03;

  localparam logic [7:0] REG_PUB_SEED_BASE = 8'h00;  // 0x00 - 0x03
  localparam logic [7:0] REG_ADDR_BASE     = 8'h10;  // 0x10 - 0x2f
  localparam logic [7:0] REG_CONFIG        = 8'h50;
  localparam logic [7:0] REG_STATUS        = 8'h51;
  localparam logic [7:0] REG_OUTPUT_BASE   = 8'h60;  // 0x60 - 0x6f

  typedef enum logic [1:0] {
    STATE_IDLE,
    STATE_WAIT_RSP,
    STATE_START_ISSUE
  } state_e;

  state_e state_q;

  logic [7:0] ptr_q;
  logic [4:0] pending_rd_q;

  logic [7:0] mapped_addr;
  logic       mapped_legal;

  logic        cmd_valid;
  logic        cmd_ready;
  logic [7:0]  cmd_op;
  logic [7:0]  cmd_addr;
  logic [31:0] cmd_wdata;
  logic [31:0] rsp_rdata;
  logic        rsp_valid;

  logic        instr_accept;
  logic        op_uses_ptr;
  logic        decoded_legal;

  assign instr_accept = instr_valid && instr_ready;

  always_comb begin
    mapped_addr  = 8'd0;
    mapped_legal = 1'b1;

    if (ptr_q <= 8'h03) begin
      mapped_addr = ptr_q;
    end else if ((ptr_q >= REG_ADDR_BASE) && (ptr_q <= 8'h4f)) begin
      mapped_addr = ptr_q;
    end else if ((ptr_q >= REG_OUTPUT_BASE) && (ptr_q <= 8'h6f)) begin
      mapped_addr = ptr_q;
    end else begin
      mapped_legal = 1'b0;
    end
  end

  always_comb begin
    op_uses_ptr   = 1'b0;
    decoded_legal = 1'b1;

    unique case (instr_op)
      INSTR_SPX_SET_PTR: begin
        op_uses_ptr = 1'b0;
      end
      INSTR_SPX_WR_NEXT, INSTR_SPX_RD_NEXT: begin
        op_uses_ptr = 1'b1;
      end
      INSTR_SPX_START_THASHX4, INSTR_SPX_STATUS: begin
        op_uses_ptr = 1'b0;
      end
      default: begin
        decoded_legal = 1'b0;
      end
    endcase
  end

  always_comb begin
    instr_ready = 1'b0;

    if (state_q == STATE_IDLE) begin
      if (!decoded_legal) begin
        instr_ready = 1'b1;
      end else if (op_uses_ptr && !mapped_legal) begin
        instr_ready = 1'b1;
      end else begin
        unique case (instr_op)
          INSTR_SPX_SET_PTR: begin
            instr_ready = 1'b1;
          end
          INSTR_SPX_WR_NEXT, INSTR_SPX_RD_NEXT,
          INSTR_SPX_START_THASHX4, INSTR_SPX_STATUS: begin
            instr_ready = cmd_ready;
          end
          default: begin
            instr_ready = 1'b1;
          end
        endcase
      end
    end
  end

  always_comb begin
    cmd_valid = 1'b0;
    cmd_op    = CMD_READ;
    cmd_addr  = 8'd0;
    cmd_wdata = 32'd0;

    if (state_q == STATE_START_ISSUE) begin
      cmd_valid = 1'b1;
      cmd_op    = CMD_START;
    end else if ((state_q == STATE_IDLE) && instr_valid &&
                 decoded_legal && (!op_uses_ptr || mapped_legal)) begin
      unique case (instr_op)
        INSTR_SPX_WR_NEXT: begin
          cmd_valid = 1'b1;
          cmd_op    = CMD_WRITE;
          cmd_addr  = mapped_addr;
          cmd_wdata = instr_rs1;
        end
        INSTR_SPX_RD_NEXT: begin
          cmd_valid = 1'b1;
          cmd_op    = CMD_READ;
          cmd_addr  = mapped_addr;
        end
        INSTR_SPX_START_THASHX4: begin
          cmd_valid = 1'b1;
          cmd_op    = CMD_WRITE;
          cmd_addr  = REG_CONFIG;
          cmd_wdata = {30'd0, instr_rs1[1:0]};
        end
        INSTR_SPX_STATUS: begin
          cmd_valid = 1'b1;
          cmd_op    = CMD_READ;
          cmd_addr  = REG_STATUS;
        end
        default: begin
        end
      endcase
    end
  end

  spx_cop_wrapper u_spx_cop_wrapper (
      .clk(clk),
      .rst_n(rst_n),
      .cmd_valid(cmd_valid),
      .cmd_ready(cmd_ready),
      .cmd_op(cmd_op),
      .cmd_addr(cmd_addr),
      .cmd_wdata(cmd_wdata),
      .rsp_rdata(rsp_rdata),
      .rsp_valid(rsp_valid),
      .busy(instr_busy),
      .done(instr_done),
      .error(instr_error)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q          <= STATE_IDLE;
      ptr_q            <= REG_PUB_SEED_BASE;
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
            pending_rd_q  <= instr_rd;
            instr_resp_rd <= instr_rd;

            if (!decoded_legal || (op_uses_ptr && !mapped_legal)) begin
              instr_resp_valid <= 1'b1;
              instr_illegal    <= 1'b1;
            end else begin
              unique case (instr_op)
                INSTR_SPX_SET_PTR: begin
                  ptr_q            <= instr_addr;
                  instr_resp_valid <= 1'b1;
                end
                INSTR_SPX_WR_NEXT: begin
                  ptr_q            <= ptr_q + 8'd1;
                  instr_resp_valid <= 1'b1;
                end
                INSTR_SPX_RD_NEXT: begin
                  ptr_q   <= ptr_q + 8'd1;
                  state_q <= STATE_WAIT_RSP;
                end
                INSTR_SPX_START_THASHX4: begin
                  state_q <= STATE_START_ISSUE;
                end
                INSTR_SPX_STATUS: begin
                  state_q <= STATE_WAIT_RSP;
                end
                default: begin
                  instr_resp_valid <= 1'b1;
                  instr_illegal    <= 1'b1;
                end
              endcase
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
        STATE_START_ISSUE: begin
          if (cmd_ready) begin
            instr_resp_valid <= 1'b1;
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
