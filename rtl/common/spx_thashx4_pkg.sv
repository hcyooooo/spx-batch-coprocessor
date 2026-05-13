package spx_thashx4_pkg;
  timeunit 1ns;
  timeprecision 1ps;

  localparam int unsigned SPX_N            = 16;
  localparam int unsigned SPX_ADDR_BYTES   = 32;
  localparam int unsigned SHAKE256_RATE    = 136;
  localparam int unsigned KECCAK_STATE_BITS = 1600;
  localparam int unsigned KECCAK_WORDS     = 25;
  localparam logic [4:0]  KECCAK_LAST_ROUND = 5'd23;

  typedef logic [63:0] spx_u64_t;

  function automatic spx_u64_t rotl64(input spx_u64_t value,
                                      input int unsigned offset);
    if (offset == 0) begin
      rotl64 = value;
    end else begin
      rotl64 = (value << offset) | (value >> (64 - offset));
    end
  endfunction

  function automatic spx_u64_t keccak_round_constant(input logic [4:0] round);
    unique case (round)
      5'd0:  keccak_round_constant = 64'h0000_0000_0000_0001;
      5'd1:  keccak_round_constant = 64'h0000_0000_0000_8082;
      5'd2:  keccak_round_constant = 64'h8000_0000_0000_808a;
      5'd3:  keccak_round_constant = 64'h8000_0000_8000_8000;
      5'd4:  keccak_round_constant = 64'h0000_0000_0000_808b;
      5'd5:  keccak_round_constant = 64'h0000_0000_8000_0001;
      5'd6:  keccak_round_constant = 64'h8000_0000_8000_8081;
      5'd7:  keccak_round_constant = 64'h8000_0000_0000_8009;
      5'd8:  keccak_round_constant = 64'h0000_0000_0000_008a;
      5'd9:  keccak_round_constant = 64'h0000_0000_0000_0088;
      5'd10: keccak_round_constant = 64'h0000_0000_8000_8009;
      5'd11: keccak_round_constant = 64'h0000_0000_8000_000a;
      5'd12: keccak_round_constant = 64'h0000_0000_8000_808b;
      5'd13: keccak_round_constant = 64'h8000_0000_0000_008b;
      5'd14: keccak_round_constant = 64'h8000_0000_0000_8089;
      5'd15: keccak_round_constant = 64'h8000_0000_0000_8003;
      5'd16: keccak_round_constant = 64'h8000_0000_0000_8002;
      5'd17: keccak_round_constant = 64'h8000_0000_0000_0080;
      5'd18: keccak_round_constant = 64'h0000_0000_0000_800a;
      5'd19: keccak_round_constant = 64'h8000_0000_8000_000a;
      5'd20: keccak_round_constant = 64'h8000_0000_8000_8081;
      5'd21: keccak_round_constant = 64'h8000_0000_0000_8080;
      5'd22: keccak_round_constant = 64'h0000_0000_8000_0001;
      5'd23: keccak_round_constant = 64'h8000_0000_8000_8008;
      default: keccak_round_constant = 64'h0;
    endcase
  endfunction

  function automatic int unsigned keccak_rho_offset(input int unsigned x,
                                                    input int unsigned y);
    unique case (x + 5 * y)
      0:  keccak_rho_offset = 0;
      1:  keccak_rho_offset = 1;
      2:  keccak_rho_offset = 62;
      3:  keccak_rho_offset = 28;
      4:  keccak_rho_offset = 27;
      5:  keccak_rho_offset = 36;
      6:  keccak_rho_offset = 44;
      7:  keccak_rho_offset = 6;
      8:  keccak_rho_offset = 55;
      9:  keccak_rho_offset = 20;
      10: keccak_rho_offset = 3;
      11: keccak_rho_offset = 10;
      12: keccak_rho_offset = 43;
      13: keccak_rho_offset = 25;
      14: keccak_rho_offset = 39;
      15: keccak_rho_offset = 41;
      16: keccak_rho_offset = 45;
      17: keccak_rho_offset = 15;
      18: keccak_rho_offset = 21;
      19: keccak_rho_offset = 8;
      20: keccak_rho_offset = 18;
      21: keccak_rho_offset = 2;
      22: keccak_rho_offset = 61;
      23: keccak_rho_offset = 56;
      24: keccak_rho_offset = 14;
      default: keccak_rho_offset = 0;
    endcase
  endfunction
endpackage
