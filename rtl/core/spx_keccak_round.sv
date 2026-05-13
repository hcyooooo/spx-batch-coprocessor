module spx_keccak_round (
    input  logic [4:0]    round_i,
    input  logic [1599:0] state_i,
    output logic [1599:0] state_o
);
  timeunit 1ns;
  timeprecision 1ps;

  import spx_thashx4_pkg::*;

  spx_u64_t a [0:24];
  spx_u64_t b [0:24];
  spx_u64_t c [0:4];
  spx_u64_t d [0:4];
  spx_u64_t n [0:24];

  always_comb begin
    for (int i = 0; i < KECCAK_WORDS; i++) begin
      a[i] = state_i[64 * i +: 64];
      b[i] = 64'h0;
      n[i] = 64'h0;
    end

    for (int x = 0; x < 5; x++) begin
      c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20];
    end

    for (int x = 0; x < 5; x++) begin
      d[x] = c[(x + 4) % 5] ^ rotl64(c[(x + 1) % 5], 1);
    end

    for (int y = 0; y < 5; y++) begin
      for (int x = 0; x < 5; x++) begin
        a[x + 5 * y] = a[x + 5 * y] ^ d[x];
      end
    end

    for (int y = 0; y < 5; y++) begin
      for (int x = 0; x < 5; x++) begin
        logic [4:0] src;
        logic [4:0] dst;
        src = 5'(x + 5 * y);
        dst = 5'(y + 5 * ((2 * x + 3 * y) % 5));
        b[dst] = rotl64(a[src], keccak_rho_offset(x, y));
      end
    end

    for (int y = 0; y < 5; y++) begin
      for (int x = 0; x < 5; x++) begin
        n[x + 5 * y] = b[x + 5 * y] ^
                       ((~b[((x + 1) % 5) + 5 * y]) &
                        b[((x + 2) % 5) + 5 * y]);
      end
    end

    n[0] = n[0] ^ keccak_round_constant(round_i);

    for (int i = 0; i < KECCAK_WORDS; i++) begin
      state_o[64 * i +: 64] = n[i];
    end
  end
endmodule
