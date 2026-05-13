module spx_cop_wrapper (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        cmd_valid,
    output logic        cmd_ready,
    input  logic [7:0]  cmd_op,
    input  logic [7:0]  cmd_addr,
    input  logic [31:0] cmd_wdata,

    output logic [31:0] rsp_rdata,
    output logic        rsp_valid,

    output logic        busy,
    output logic        done,
    output logic        error
);
  timeunit 1ns;
  timeprecision 1ps;

  localparam logic [7:0] CMD_WRITE = 8'h01;
  localparam logic [7:0] CMD_READ  = 8'h02;
  localparam logic [7:0] CMD_START = 8'h03;

  localparam logic [7:0] REG_PUB_SEED_BASE = 8'h00;  // 0x00 - 0x03
  localparam logic [7:0] REG_ADDR_BASE     = 8'h10;  // 0x10 - 0x2f
  localparam logic [7:0] REG_INPUT_BASE    = 8'h30;  // 0x30 - 0x4f
  localparam logic [7:0] REG_CONFIG        = 8'h50;
  localparam logic [7:0] REG_STATUS        = 8'h51;
  localparam logic [7:0] REG_OUTPUT_BASE   = 8'h60;  // 0x60 - 0x6f

  localparam logic [3:0] ERR_NONE          = 4'h0;
  localparam logic [3:0] ERR_BAD_OP        = 4'h1;
  localparam logic [3:0] ERR_BAD_ADDR      = 4'h2;
  localparam logic [3:0] ERR_BAD_INBLOCKS  = 4'h3;

  logic [127:0] pub_seed_q;
  logic [255:0] addr_q [0:3];
  logic [255:0] input_q [0:3];
  logic [127:0] output_q [0:3];
  logic [1:0]   inblocks_q;

  logic         busy_q;
  logic         done_q;
  logic         error_q;
  logic [3:0]   error_code_q;

  logic         cmd_accept;
  logic         read_accept;
  logic         write_accept;
  logic         start_accept;
  logic         core_start;
  logic         core_done;
  logic [127:0] core_out [0:3];

  logic         addr_pub_seed_sel;
  logic         addr_addr_sel;
  logic         addr_input_sel;
  logic         addr_config_sel;
  logic         addr_status_sel;
  logic         addr_output_sel;
  logic [1:0]   addr_word4_idx;
  logic [2:0]   addr_word8_idx;
  logic [1:0]   addr_lane_idx;
  logic [4:0]   addr_offset;

  logic [31:0]  read_rdata;

  assign cmd_accept  = cmd_valid && cmd_ready;
  assign read_accept = cmd_accept && (cmd_op == CMD_READ);
  assign write_accept = cmd_accept && (cmd_op == CMD_WRITE);
  assign start_accept = cmd_accept && (cmd_op == CMD_START);
  assign core_start = start_accept && ((inblocks_q == 2'd1) || (inblocks_q == 2'd2));

  assign busy  = busy_q;
  assign done  = done_q;
  assign error = error_q;

  always_comb begin
    unique case (cmd_op)
      CMD_READ: begin
        cmd_ready = 1'b1;
      end
      CMD_WRITE, CMD_START: begin
        cmd_ready = !busy_q;
      end
      default: begin
        cmd_ready = !busy_q;
      end
    endcase
  end

  always_comb begin
    addr_pub_seed_sel = 1'b0;
    addr_addr_sel     = 1'b0;
    addr_input_sel    = 1'b0;
    addr_config_sel   = 1'b0;
    addr_status_sel   = 1'b0;
    addr_output_sel   = 1'b0;
    addr_word4_idx    = 2'd0;
    addr_word8_idx    = 3'd0;
    addr_lane_idx     = 2'd0;
    addr_offset       = 5'd0;

    if ((cmd_addr - REG_PUB_SEED_BASE) <= 8'h03) begin
      addr_pub_seed_sel = 1'b1;
      addr_word4_idx = cmd_addr[1:0];
    end else if ((cmd_addr >= REG_ADDR_BASE) && (cmd_addr <= 8'h2f)) begin
      addr_addr_sel = 1'b1;
      addr_offset = cmd_addr[4:0] - REG_ADDR_BASE[4:0];
      addr_lane_idx = addr_offset[4:3];
      addr_word8_idx = addr_offset[2:0];
    end else if ((cmd_addr >= REG_INPUT_BASE) && (cmd_addr <= 8'h4f)) begin
      addr_input_sel = 1'b1;
      addr_offset = cmd_addr[4:0] - REG_INPUT_BASE[4:0];
      addr_lane_idx = addr_offset[4:3];
      addr_word8_idx = addr_offset[2:0];
    end else if (cmd_addr == REG_CONFIG) begin
      addr_config_sel = 1'b1;
    end else if (cmd_addr == REG_STATUS) begin
      addr_status_sel = 1'b1;
    end else if ((cmd_addr >= REG_OUTPUT_BASE) && (cmd_addr <= 8'h6f)) begin
      addr_output_sel = 1'b1;
      addr_offset = cmd_addr[4:0] - REG_OUTPUT_BASE[4:0];
      addr_lane_idx = addr_offset[3:2];
      addr_word4_idx = addr_offset[1:0];
    end
  end

  function automatic logic [31:0] status_word(
      input logic       busy_f,
      input logic       done_f,
      input logic       error_f,
      input logic [1:0] inblocks_f,
      input logic [3:0] error_code_f
  );
    logic [31:0] word;
    begin
      word = 32'd0;
      word[0] = busy_f;
      word[1] = done_f;
      word[2] = error_f;
      word[9:8] = inblocks_f;
      word[19:16] = error_code_f;
      status_word = word;
    end
  endfunction

  always_comb begin
    read_rdata = 32'd0;

    if (addr_pub_seed_sel) begin
      read_rdata = pub_seed_q[32 * addr_word4_idx +: 32];
    end else if (addr_addr_sel) begin
      read_rdata = addr_q[addr_lane_idx][32 * addr_word8_idx +: 32];
    end else if (addr_input_sel) begin
      read_rdata = input_q[addr_lane_idx][32 * addr_word8_idx +: 32];
    end else if (addr_config_sel) begin
      read_rdata = {30'd0, inblocks_q};
    end else if (addr_status_sel) begin
      read_rdata = status_word(busy_q, done_q, error_q, inblocks_q, error_code_q);
    end else if (addr_output_sel) begin
      read_rdata = output_q[addr_lane_idx][32 * addr_word4_idx +: 32];
    end
  end

  spx_thashx4_core u_thashx4_core (
      .clk(clk),
      .rst_n(rst_n),
      .start(core_start),
      .inblocks(inblocks_q),
      .pub_seed(pub_seed_q),
      .addr0(addr_q[0]),
      .addr1(addr_q[1]),
      .addr2(addr_q[2]),
      .addr3(addr_q[3]),
      .in0(input_q[0]),
      .in1(input_q[1]),
      .in2(input_q[2]),
      .in3(input_q[3]),
      .done(core_done),
      .out0(core_out[0]),
      .out1(core_out[1]),
      .out2(core_out[2]),
      .out3(core_out[3])
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pub_seed_q   <= '0;
      addr_q[0]    <= '0;
      addr_q[1]    <= '0;
      addr_q[2]    <= '0;
      addr_q[3]    <= '0;
      input_q[0]   <= '0;
      input_q[1]   <= '0;
      input_q[2]   <= '0;
      input_q[3]   <= '0;
      output_q[0]  <= '0;
      output_q[1]  <= '0;
      output_q[2]  <= '0;
      output_q[3]  <= '0;
      inblocks_q   <= 2'd1;
      busy_q       <= 1'b0;
      done_q       <= 1'b0;
      error_q      <= 1'b0;
      error_code_q <= ERR_NONE;
      rsp_rdata    <= 32'd0;
      rsp_valid    <= 1'b0;
    end else begin
      rsp_valid <= cmd_accept;
      rsp_rdata <= read_accept ? read_rdata : 32'd0;

      if (core_done && busy_q) begin
        busy_q      <= 1'b0;
        done_q      <= 1'b1;
        output_q[0] <= core_out[0];
        output_q[1] <= core_out[1];
        output_q[2] <= core_out[2];
        output_q[3] <= core_out[3];
      end

      if (write_accept) begin
        if (addr_pub_seed_sel) begin
          pub_seed_q[32 * addr_word4_idx +: 32] <= cmd_wdata;
        end else if (addr_addr_sel) begin
          addr_q[addr_lane_idx][32 * addr_word8_idx +: 32] <= cmd_wdata;
        end else if (addr_input_sel) begin
          input_q[addr_lane_idx][32 * addr_word8_idx +: 32] <= cmd_wdata;
        end else if (addr_config_sel) begin
          inblocks_q <= cmd_wdata[1:0];
        end else if (addr_status_sel) begin
          if (cmd_wdata[1]) begin
            done_q <= 1'b0;
          end
          if (cmd_wdata[2]) begin
            error_q      <= 1'b0;
            error_code_q <= ERR_NONE;
          end
        end else begin
          error_q      <= 1'b1;
          error_code_q <= ERR_BAD_ADDR;
        end
      end else if (start_accept) begin
        done_q <= 1'b0;
        if ((inblocks_q == 2'd1) || (inblocks_q == 2'd2)) begin
          busy_q       <= 1'b1;
          error_q      <= 1'b0;
          error_code_q <= ERR_NONE;
        end else begin
          busy_q       <= 1'b0;
          error_q      <= 1'b1;
          error_code_q <= ERR_BAD_INBLOCKS;
        end
      end else if (cmd_accept && (cmd_op != CMD_READ)) begin
        error_q      <= 1'b1;
        error_code_q <= ERR_BAD_OP;
      end else if (read_accept && !(addr_pub_seed_sel || addr_addr_sel || addr_input_sel ||
                                    addr_config_sel || addr_status_sel || addr_output_sel)) begin
        error_q      <= 1'b1;
        error_code_q <= ERR_BAD_ADDR;
      end
    end
  end
endmodule
