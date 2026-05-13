module spx_mem_master_shim_mock #(
    parameter int MEM_ADDR_WIDTH = 32,
    parameter int MEM_DATA_WIDTH = 128
) (
    input  logic                      clk,
    input  logic                      rst_n,

    input  logic                      mem_valid,
    output logic                      mem_ready,
    input  logic                      mem_we,
    input  logic [MEM_ADDR_WIDTH-1:0] mem_addr,
    input  logic [MEM_DATA_WIDTH-1:0] mem_wdata,
    output logic [MEM_DATA_WIDTH-1:0] mem_rdata,
    output logic                      mem_error,

    output logic                      bus_req_valid,
    input  logic                      bus_req_ready,
    output logic                      bus_req_we,
    output logic [MEM_ADDR_WIDTH-1:0] bus_req_addr,
    output logic [MEM_DATA_WIDTH-1:0] bus_req_wdata,

    input  logic                      bus_rsp_valid,
    input  logic [MEM_DATA_WIDTH-1:0] bus_rsp_rdata,
    input  logic                      bus_rsp_error
);
  timeunit 1ns;
  timeprecision 1ps;

  typedef enum logic {
    ST_IDLE,
    ST_WAIT_RSP
  } state_e;

  state_e state_q;

  logic req_fire;
  logic rsp_fire_idle;
  logic rsp_fire_wait;

  logic req_we_q;
  logic [MEM_ADDR_WIDTH-1:0] req_addr_q;
  logic [MEM_DATA_WIDTH-1:0] req_wdata_q;

  assign req_fire      = bus_req_valid && bus_req_ready;
  assign rsp_fire_idle = (state_q == ST_IDLE) && req_fire && bus_rsp_valid;
  assign rsp_fire_wait = (state_q == ST_WAIT_RSP) && bus_rsp_valid;

  assign bus_req_valid = (state_q == ST_IDLE) && mem_valid;
  assign bus_req_we    = (state_q == ST_IDLE) ? mem_we : req_we_q;
  assign bus_req_addr  = (state_q == ST_IDLE) ? mem_addr : req_addr_q;
  assign bus_req_wdata = (state_q == ST_IDLE) ? mem_wdata : req_wdata_q;

  assign mem_ready = mem_valid && (rsp_fire_idle || rsp_fire_wait);
  assign mem_rdata = bus_rsp_rdata;
  assign mem_error = (rsp_fire_idle || rsp_fire_wait) && bus_rsp_error;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q     <= ST_IDLE;
      req_we_q    <= 1'b0;
      req_addr_q  <= '0;
      req_wdata_q <= '0;
    end else begin
      unique case (state_q)
        ST_IDLE: begin
          if (req_fire && !bus_rsp_valid) begin
            state_q     <= ST_WAIT_RSP;
            req_we_q    <= mem_we;
            req_addr_q  <= mem_addr;
            req_wdata_q <= mem_wdata;
          end
        end

        ST_WAIT_RSP: begin
          if (bus_rsp_valid) begin
            state_q <= ST_IDLE;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end
endmodule
