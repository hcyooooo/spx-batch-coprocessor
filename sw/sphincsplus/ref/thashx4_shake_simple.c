#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "fips202.h"
#include "keccakx4.h"
#include "params.h"
#include "thash.h"
#include "thashx4_shake_simple.h"

static uint64_t load64(const unsigned char *x)
{
    uint64_t r = 0;

    for (size_t i = 0; i < 8; i++) {
        r |= (uint64_t)x[i] << (8 * i);
    }

    return r;
}

static void copy_addr(uint32_t dst[8], const uint32_t src[8])
{
    for (size_t i = 0; i < 8; i++) {
        dst[i] = src[i];
    }
}

static void thashx4_scalar_fallback(unsigned char *out0,
                                    unsigned char *out1,
                                    unsigned char *out2,
                                    unsigned char *out3,
                                    const unsigned char *in0,
                                    const unsigned char *in1,
                                    const unsigned char *in2,
                                    const unsigned char *in3,
                                    unsigned int inblocks,
                                    const spx_ctx *ctx,
                                    const uint32_t addr0[8],
                                    const uint32_t addr1[8],
                                    const uint32_t addr2[8],
                                    const uint32_t addr3[8])
{
    uint32_t a0[8];
    uint32_t a1[8];
    uint32_t a2[8];
    uint32_t a3[8];

    copy_addr(a0, addr0);
    copy_addr(a1, addr1);
    copy_addr(a2, addr2);
    copy_addr(a3, addr3);

    thash(out0, in0, inblocks, ctx, a0);
    thash(out1, in1, inblocks, ctx, a1);
    thash(out2, in2, inblocks, ctx, a2);
    thash(out3, in3, inblocks, ctx, a3);
}

static void build_thash_block(unsigned char block[SHAKE256_RATE],
                              const unsigned char *in,
                              unsigned int inblocks,
                              const spx_ctx *ctx,
                              const uint32_t addr[8])
{
    const size_t inbytes = (size_t)inblocks * SPX_N;
    size_t offset = 0;

    memset(block, 0, SHAKE256_RATE);

    memcpy(block + offset, ctx->pub_seed, SPX_N);
    offset += SPX_N;
    memcpy(block + offset, addr, SPX_ADDR_BYTES);
    offset += SPX_ADDR_BYTES;
    memcpy(block + offset, in, inbytes);
    offset += inbytes;

    block[offset] = 0x1F;
    block[SHAKE256_RATE - 1] |= 0x80;
}

static void squeeze_nbytes(unsigned char *out, const uint64_t state[25])
{
    for (size_t i = 0; i < SPX_N; i++) {
        out[i] = (unsigned char)(state[i >> 3] >> (8 * (i & 0x07)));
    }
}

void thashx4(unsigned char *out0,
             unsigned char *out1,
             unsigned char *out2,
             unsigned char *out3,
             const unsigned char *in0,
             const unsigned char *in1,
             const unsigned char *in2,
             const unsigned char *in3,
             unsigned int inblocks,
             const spx_ctx *ctx,
             const uint32_t addr0[8],
             const uint32_t addr1[8],
             const uint32_t addr2[8],
             const uint32_t addr3[8])
{
    uint64_t state[4][25] = {{0}};
    unsigned char block[4][SHAKE256_RATE];
    const unsigned char *in[4] = {in0, in1, in2, in3};
    unsigned char *out[4] = {out0, out1, out2, out3};
    const uint32_t *addr[4] = {addr0, addr1, addr2, addr3};

    if (inblocks > 2) {
        thashx4_scalar_fallback(out0, out1, out2, out3,
                                in0, in1, in2, in3,
                                inblocks, ctx,
                                addr0, addr1, addr2, addr3);
        return;
    }

    for (size_t lane = 0; lane < 4; lane++) {
        build_thash_block(block[lane], in[lane], inblocks, ctx, addr[lane]);
        for (size_t word = 0; word < SHAKE256_RATE / 8; word++) {
            state[lane][word] = load64(block[lane] + 8 * word);
        }
    }

    keccak_f1600x4(state);

    for (size_t lane = 0; lane < 4; lane++) {
        squeeze_nbytes(out[lane], state[lane]);
    }
}
