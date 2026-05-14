module tb_cv32e40x_spx_core_smoke import cv32e40x_pkg::*;
();
  timeunit 1ns;
  timeprecision 1ps;

  localparam int X_NUM_RS             = 2;
  localparam int X_ID_WIDTH           = 4;
  localparam int X_MEM_WIDTH          = 32;
  localparam int X_RFR_WIDTH          = 32;
  localparam int X_RFW_WIDTH          = 32;
  localparam int MEM_WORDS_PER_CYCLE  = 4;
  localparam int MEM_ADDR_WIDTH       = 32;
  localparam int MEM_DATA_WIDTH       = 32 * MEM_WORDS_PER_CYCLE;
  localparam int MEM_BYTES            = 128 * 1024;
  localparam int TIMEOUT_CYCLES       = 300000;
  localparam logic [31:0] BOOT_ADDR   = 32'h0000_0000;
  localparam logic [31:0] MTVEC_ADDR  = 32'h0000_0000;
  localparam logic [31:0] MAGIC_ADDR  = 32'h0000_fffc;
  localparam logic [31:0] MAGIC_PASS  = 32'h0000_0001;
  localparam logic [31:0] MAGIC_FAIL  = 32'h0000_dead;

  logic clk;
  logic rst_n;
  logic fetch_enable;

  logic        instr_req;
  logic        instr_gnt;
  logic        instr_rvalid;
  logic [31:0] instr_addr;
  logic [1:0]  instr_memtype;
  logic [2:0]  instr_prot;
  logic        instr_dbg;
  logic [31:0] instr_rdata;
  logic        instr_err;

  logic        data_req;
  logic        data_gnt;
  logic        data_rvalid;
  logic [31:0] data_addr;
  logic [3:0]  data_be;
  logic        data_we;
  logic [31:0] data_wdata;
  logic [1:0]  data_memtype;
  logic [2:0]  data_prot;
  logic        data_dbg;
  logic [5:0]  data_atop;
  logic [31:0] data_rdata;
  logic        data_err;
  logic        data_exokay;

  logic [63:0] mcycle;
  logic [63:0] time_q;

  logic        fencei_flush_req;
  logic        fencei_flush_ack;
  logic        debug_havereset;
  logic        debug_running;
  logic        debug_halted;
  logic        debug_pc_valid;
  logic [31:0] debug_pc;
  logic        core_sleep;

  cv32e40x_if_xif #(
      .X_NUM_RS(X_NUM_RS),
      .X_ID_WIDTH(X_ID_WIDTH),
      .X_MEM_WIDTH(X_MEM_WIDTH),
      .X_RFR_WIDTH(X_RFR_WIDTH),
      .X_RFW_WIDTH(X_RFW_WIDTH),
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

  logic        desc_start;
  logic [31:0] desc_addr;
  logic        desc_busy;
  logic        desc_done;
  logic        desc_error;
  logic [31:0] desc_status;
  logic [3:0]  desc_error_code;

  logic                      mem_valid;
  logic                      mem_ready;
  logic                      mem_we;
  logic [MEM_ADDR_WIDTH-1:0] mem_addr;
  logic [MEM_DATA_WIDTH-1:0] mem_wdata;
  logic [MEM_DATA_WIDTH-1:0] mem_rdata;
  logic                      mem_error;

  logic                      bus_req_valid;
  logic                      bus_req_ready;
  logic                      bus_req_we;
  logic [MEM_ADDR_WIDTH-1:0] bus_req_addr;
  logic [MEM_DATA_WIDTH-1:0] bus_req_wdata;
  logic                      bus_rsp_valid;
  logic [MEM_DATA_WIDTH-1:0] bus_rsp_rdata;
  logic                      bus_rsp_error;

  logic [31:0] perf_load_cycles;
  logic [31:0] perf_core_cycles;
  logic [31:0] perf_store_cycles;
  logic [31:0] perf_total_cycles;

  logic [7:0] memory [0:MEM_BYTES-1];

  int unsigned cycle_q;
  int unsigned instr_fetch_count_q;
  int unsigned data_read_count_q;
  int unsigned data_write_count_q;
  int unsigned xif_issue_count_q;
  int unsigned xif_accept_count_q;
  int unsigned xif_result_count_q;
  int unsigned xif_mem_valid_count_q;
  int unsigned desc_control_count_q;
  int unsigned bus_read_count_q;
  int unsigned bus_write_count_q;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    string smoke_hex;

    for (int i = 0; i < MEM_BYTES; i++) begin
      memory[i] = 8'h00;
    end

    if (!$value$plusargs("SMOKE_HEX=%s", smoke_hex)) begin
      smoke_hex = "build/spx_cvxif_smoke.hex";
    end
    $display("Loading CV32E40X smoke image: %s", smoke_hex);
    $readmemh(smoke_hex, memory);
  end

  initial begin
    rst_n        = 1'b0;
    fetch_enable = 1'b0;
    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);
    fetch_enable = 1'b1;
  end

  function automatic logic [31:0] read_word(input logic [31:0] byte_addr);
    int unsigned addr;
    begin
      addr = int'(byte_addr);
      if ((addr + 3) >= MEM_BYTES) begin
        $fatal(1, "memory read out of range addr=0x%08x", byte_addr);
      end
      read_word = 32'(memory[addr]) |
                  (32'(memory[addr + 1]) << 8) |
                  (32'(memory[addr + 2]) << 16) |
                  (32'(memory[addr + 3]) << 24);
    end
  endfunction

  task automatic write_word(
      input logic [31:0] byte_addr,
      input logic [31:0] wdata,
      input logic [3:0]  be
  );
    int unsigned addr;
    begin
      addr = int'(byte_addr);
      if ((addr + 3) >= MEM_BYTES) begin
        $fatal(1, "memory write out of range addr=0x%08x data=0x%08x",
               byte_addr, wdata);
      end
      if (be[0]) begin
        memory[addr] = wdata[7:0];
      end
      if (be[1]) begin
        memory[addr + 1] = wdata[15:8];
      end
      if (be[2]) begin
        memory[addr + 2] = wdata[23:16];
      end
      if (be[3]) begin
        memory[addr + 3] = wdata[31:24];
      end
    end
  endtask

  function automatic logic [MEM_DATA_WIDTH-1:0] read_bus_beat(
      input logic [MEM_ADDR_WIDTH-1:0] byte_addr
  );
    logic [MEM_DATA_WIDTH-1:0] data;
    begin
      data = '0;
      for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
        data[32 * lane +: 32] = read_word(byte_addr + 32'(lane * 4));
      end
      read_bus_beat = data;
    end
  endfunction

  task automatic write_bus_beat(
      input logic [MEM_ADDR_WIDTH-1:0] byte_addr,
      input logic [MEM_DATA_WIDTH-1:0] wdata
  );
    begin
      for (int lane = 0; lane < MEM_WORDS_PER_CYCLE; lane++) begin
        write_word(byte_addr + 32'(lane * 4), wdata[32 * lane +: 32], 4'hf);
      end
    end
  endtask

  cv32e40x_core #(
      .LIB(0),
      .RV32(RV32I),
      .A_EXT(A_NONE),
      .B_EXT(B_NONE),
      .M_EXT(M),
      .DEBUG(1'b0),
      .DBG_NUM_TRIGGERS(1),
      .CLIC(1'b0),
      .X_EXT(1'b1),
      .X_NUM_RS(X_NUM_RS),
      .X_ID_WIDTH(X_ID_WIDTH),
      .X_MEM_WIDTH(X_MEM_WIDTH),
      .X_RFR_WIDTH(X_RFR_WIDTH),
      .X_RFW_WIDTH(X_RFW_WIDTH),
      .X_MISA(32'h0000_0000),
      .X_ECS_XS(2'b00),
      .NUM_MHPMCOUNTERS(1)
  ) u_core (
      .clk_i(clk),
      .rst_ni(rst_n),
      .scan_cg_en_i(1'b0),
      .boot_addr_i(BOOT_ADDR),
      .dm_exception_addr_i(32'hf000_0000),
      .dm_halt_addr_i(32'hf000_0800),
      .mhartid_i(32'd0),
      .mimpid_patch_i(4'd0),
      .mtvec_addr_i(MTVEC_ADDR),
      .instr_req_o(instr_req),
      .instr_gnt_i(instr_gnt),
      .instr_rvalid_i(instr_rvalid),
      .instr_addr_o(instr_addr),
      .instr_memtype_o(instr_memtype),
      .instr_prot_o(instr_prot),
      .instr_dbg_o(instr_dbg),
      .instr_rdata_i(instr_rdata),
      .instr_err_i(instr_err),
      .data_req_o(data_req),
      .data_gnt_i(data_gnt),
      .data_rvalid_i(data_rvalid),
      .data_addr_o(data_addr),
      .data_be_o(data_be),
      .data_we_o(data_we),
      .data_wdata_o(data_wdata),
      .data_memtype_o(data_memtype),
      .data_prot_o(data_prot),
      .data_dbg_o(data_dbg),
      .data_atop_o(data_atop),
      .data_rdata_i(data_rdata),
      .data_err_i(data_err),
      .data_exokay_i(data_exokay),
      .mcycle_o(mcycle),
      .time_i(time_q),
      .xif_compressed_if(xif),
      .xif_issue_if(xif),
      .xif_commit_if(xif),
      .xif_mem_if(xif),
      .xif_mem_result_if(xif),
      .xif_result_if(xif),
      .irq_i(32'd0),
      .wu_wfe_i(1'b0),
      .clic_irq_i(1'b0),
      .clic_irq_id_i('0),
      .clic_irq_level_i(8'd0),
      .clic_irq_priv_i(2'd0),
      .clic_irq_shv_i(1'b0),
      .fencei_flush_req_o(fencei_flush_req),
      .fencei_flush_ack_i(fencei_flush_ack),
      .debug_req_i(1'b0),
      .debug_havereset_o(debug_havereset),
      .debug_running_o(debug_running),
      .debug_halted_o(debug_halted),
      .debug_pc_valid_o(debug_pc_valid),
      .debug_pc_o(debug_pc),
      .fetch_enable_i(fetch_enable),
      .core_sleep_o(core_sleep)
  );

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

  spx_cvxif_desc_adapter u_cvxif_desc_adapter (
      .clk(clk),
      .rst_n(rst_n),
      .instr_valid(instr_valid),
      .instr_ready(instr_ready),
      .instr_op(instr_op),
      .instr_rs1(instr_rs1),
      .instr_resp_valid(instr_resp_valid),
      .instr_resp_data(instr_resp_data),
      .instr_illegal(instr_illegal),
      .desc_start(desc_start),
      .desc_addr(desc_addr),
      .desc_busy(desc_busy),
      .desc_done(desc_done),
      .desc_error(desc_error),
      .desc_error_code(desc_error_code)
  );

  spx_descriptor_adapter #(
      .MEM_WORDS_PER_CYCLE(MEM_WORDS_PER_CYCLE),
      .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH)
  ) u_descriptor_adapter (
      .clk(clk),
      .rst_n(rst_n),
      .start(desc_start),
      .descriptor_addr(desc_addr),
      .busy(desc_busy),
      .done(desc_done),
      .error(desc_error),
      .status(desc_status),
      .mem_valid(mem_valid),
      .mem_ready(mem_ready),
      .mem_we(mem_we),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_rdata(mem_rdata),
      .mem_error(mem_error),
      .perf_load_cycles(perf_load_cycles),
      .perf_core_cycles(perf_core_cycles),
      .perf_store_cycles(perf_store_cycles),
      .perf_total_cycles(perf_total_cycles)
  );

  spx_mem_master_shim_mock #(
      .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH),
      .MEM_DATA_WIDTH(MEM_DATA_WIDTH)
  ) u_mem_master_shim_mock (
      .clk(clk),
      .rst_n(rst_n),
      .mem_valid(mem_valid),
      .mem_ready(mem_ready),
      .mem_we(mem_we),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_rdata(mem_rdata),
      .mem_error(mem_error),
      .bus_req_valid(bus_req_valid),
      .bus_req_ready(bus_req_ready),
      .bus_req_we(bus_req_we),
      .bus_req_addr(bus_req_addr),
      .bus_req_wdata(bus_req_wdata),
      .bus_rsp_valid(bus_rsp_valid),
      .bus_rsp_rdata(bus_rsp_rdata),
      .bus_rsp_error(bus_rsp_error)
  );

  assign desc_error_code = desc_status[19:16];

  assign instr_gnt = instr_req;
  assign data_gnt = data_req;
  assign data_exokay = 1'b0;
  assign fencei_flush_ack = fencei_flush_req;
  assign bus_req_ready = bus_req_valid;
  assign bus_rsp_valid = bus_req_valid && bus_req_ready;
  assign bus_rsp_error = 1'b0;

  always_comb begin
    bus_rsp_rdata = bus_req_valid ? read_bus_beat(bus_req_addr) : '0;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_rvalid <= 1'b0;
      instr_rdata  <= 32'd0;
      instr_err    <= 1'b0;
    end else begin
      instr_rvalid <= instr_req && instr_gnt;
      instr_err    <= 1'b0;
      if (instr_req && instr_gnt) begin
        instr_rdata <= read_word(instr_addr);
      end else begin
        instr_rdata <= 32'd0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_rvalid <= 1'b0;
      data_rdata  <= 32'd0;
      data_err    <= 1'b0;
    end else begin
      data_rvalid <= data_req && data_gnt;
      data_err    <= 1'b0;
      if (data_req && data_gnt) begin
        data_rdata <= read_word(data_addr);
        if (data_we) begin
          write_word(data_addr, data_wdata, data_be);
        end
      end else begin
        data_rdata <= 32'd0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n && bus_req_valid && bus_req_ready && bus_req_we) begin
      write_bus_beat(bus_req_addr, bus_req_wdata);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_q              <= 0;
      instr_fetch_count_q  <= 0;
      data_read_count_q    <= 0;
      data_write_count_q   <= 0;
      xif_issue_count_q    <= 0;
      xif_accept_count_q   <= 0;
      xif_result_count_q   <= 0;
      xif_mem_valid_count_q <= 0;
      desc_control_count_q <= 0;
      bus_read_count_q     <= 0;
      bus_write_count_q    <= 0;
      time_q               <= 64'd0;
    end else begin
      logic [31:0] magic_word;

      cycle_q <= cycle_q + 1;
      time_q  <= time_q + 64'd1;

      if (instr_req && instr_gnt) begin
        instr_fetch_count_q <= instr_fetch_count_q + 1;
      end
      if (data_req && data_gnt) begin
        if (data_we) begin
          data_write_count_q <= data_write_count_q + 1;
        end else begin
          data_read_count_q <= data_read_count_q + 1;
        end
      end
      if (xif.issue_valid && xif.issue_ready) begin
        xif_issue_count_q <= xif_issue_count_q + 1;
        if (xif.issue_resp.accept) begin
          xif_accept_count_q <= xif_accept_count_q + 1;
        end
      end
      if (xif.result_valid && xif.result_ready) begin
        xif_result_count_q <= xif_result_count_q + 1;
      end
      if (instr_valid && instr_ready) begin
        desc_control_count_q <= desc_control_count_q + 1;
      end
      if (bus_req_valid && bus_req_ready) begin
        if (bus_req_we) begin
          bus_write_count_q <= bus_write_count_q + 1;
        end else begin
          bus_read_count_q <= bus_read_count_q + 1;
        end
      end
      if (xif.mem_valid) begin
        xif_mem_valid_count_q <= xif_mem_valid_count_q + 1;
        $fatal(1, "CV-X-IF memory interface was used; descriptor bulk data must stay on memory-side path");
      end

      magic_word = read_word(MAGIC_ADDR);
      if (magic_word == MAGIC_PASS) begin
        if (xif_accept_count_q < 8) begin
          $fatal(1, "PASS magic observed before expected XIF traffic count=%0d",
                 xif_accept_count_q);
        end
        if (desc_control_count_q < 8) begin
          $fatal(1, "PASS magic observed before descriptor controls count=%0d",
                 desc_control_count_q);
        end
        $display("PASS cv32e40x_spx_core_smoke cycles=%0d instr_fetch=%0d data_rd=%0d data_wr=%0d xif_issue=%0d xif_accept=%0d xif_result=%0d desc_ctrl=%0d bus_rd=%0d bus_wr=%0d perf_load=%0d perf_core=%0d perf_store=%0d perf_total=%0d",
                 cycle_q, instr_fetch_count_q, data_read_count_q, data_write_count_q,
                 xif_issue_count_q, xif_accept_count_q, xif_result_count_q,
                 desc_control_count_q, bus_read_count_q, bus_write_count_q,
                 perf_load_cycles, perf_core_cycles, perf_store_cycles,
                 perf_total_cycles);
        $finish;
      end
      if (magic_word == MAGIC_FAIL) begin
        $fatal(1, "FAIL magic observed at 0x%08x", MAGIC_ADDR);
      end
      if (cycle_q > TIMEOUT_CYCLES) begin
        $fatal(1, "timeout waiting for PASS magic pc_valid=%0b pc=0x%08x magic=0x%08x xif_accept=%0d desc_status=0x%08x",
               debug_pc_valid, debug_pc, magic_word, xif_accept_count_q, desc_status);
      end
    end
  end

  logic unused_signals;
  assign unused_signals =
      (|instr_memtype) | (|instr_prot) | instr_dbg |
      (|data_memtype) | (|data_prot) | data_dbg | (|data_atop) |
      (|mcycle) | debug_havereset | debug_running | debug_halted |
      debug_pc_valid | (|debug_pc) | core_sleep | desc_busy | desc_done |
      desc_error | mem_valid | mem_we | mem_error | (|mem_addr) |
      (|mem_wdata) | (|mem_rdata) | xif_mem_valid_count_q;

endmodule
