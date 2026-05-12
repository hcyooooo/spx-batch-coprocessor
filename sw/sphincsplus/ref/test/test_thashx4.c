#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../context.h"
#include "../params.h"
#include "../thash.h"
#include "../thashx4_shake_simple.h"

#define TEST_ROUNDS 1000

static uint64_t prng_next(uint64_t *state)
{
    uint64_t x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    return x;
}

static void fill_bytes(unsigned char *out, size_t outlen, uint64_t *seed)
{
    for (size_t i = 0; i < outlen; i++) {
        out[i] = (unsigned char)(prng_next(seed) & 0xffU);
    }
}

static void fill_addrs(uint32_t addr[4][8], uint64_t *seed)
{
    for (size_t lane = 0; lane < 4; lane++) {
        for (size_t i = 0; i < 8; i++) {
            addr[lane][i] = (uint32_t)prng_next(seed);
        }
    }
}

static int compare_thashx4(unsigned int inblocks,
                           uint64_t *seed,
                           size_t round)
{
    spx_ctx ctx = {0};
    unsigned char input[4][2 * SPX_N];
    unsigned char out_ref[4][SPX_N];
    unsigned char out_x4[4][SPX_N];
    uint32_t addr[4][8];

    fill_bytes(ctx.pub_seed, sizeof(ctx.pub_seed), seed);
    fill_bytes(ctx.sk_seed, sizeof(ctx.sk_seed), seed);
    for (size_t lane = 0; lane < 4; lane++) {
        fill_bytes(input[lane], inblocks * SPX_N, seed);
    }
    fill_addrs(addr, seed);

    input[0][0] = 0x11;
    input[1][0] = 0x33;
    input[2][0] = 0x55;
    input[3][0] = 0x77;
    addr[0][0] = 0x10203040;
    addr[1][0] = 0x21314151;
    addr[2][0] = 0x32425262;
    addr[3][0] = 0x43536373;

    for (size_t lane = 0; lane < 4; lane++) {
        thash(out_ref[lane], input[lane], inblocks, &ctx, addr[lane]);
    }

    thashx4(out_x4[0], out_x4[1], out_x4[2], out_x4[3],
            input[0], input[1], input[2], input[3],
            inblocks, &ctx, addr[0], addr[1], addr[2], addr[3]);

    for (size_t lane = 0; lane < 4; lane++) {
        if (memcmp(out_ref[lane], out_x4[lane], SPX_N) != 0) {
            printf("FAIL thashx4 inblocks=%u round=%zu lane=%zu\n",
                   inblocks, round, lane);
            return -1;
        }
    }

    return 0;
}

int main(void)
{
    uint64_t seed = 0x0f1e2d3c4b5a6978ULL;

    setbuf(stdout, NULL);

    for (size_t round = 0; round < TEST_ROUNDS; round++) {
        if (compare_thashx4(1, &seed, round)) {
            return 1;
        }
        if (compare_thashx4(2, &seed, round)) {
            return 1;
        }
    }

    printf("PASS thashx4 true Keccakx4 correctness for inblocks=1,2 (%u rounds each)\n",
           TEST_ROUNDS);
    return 0;
}
