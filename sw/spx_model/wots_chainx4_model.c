#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "keccakx4.h"
#include "wots_chainx4_model.h"

#define SHAKE256_RATE 136u
#define KECCAK_WORDS 25u

static uint64_t load64_le(const uint8_t *x)
{
    uint64_t r = 0;

    for (size_t i = 0; i < 8; i++) {
        r |= (uint64_t)x[i] << (8 * i);
    }

    return r;
}

static void squeeze_spx_n(uint8_t out[SPX_WOTS_CHAINX4_N],
                          const uint64_t state[KECCAK_WORDS])
{
    for (size_t i = 0; i < SPX_WOTS_CHAINX4_N; i++) {
        out[i] = (uint8_t)(state[i >> 3] >> (8 * (i & 0x07u)));
    }
}

static void build_thash_block(
    uint8_t block[SHAKE256_RATE],
    const uint8_t input[2u * SPX_WOTS_CHAINX4_N],
    unsigned int inblocks,
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_ADDR_BYTES])
{
    const size_t inbytes = (size_t)inblocks * SPX_WOTS_CHAINX4_N;
    size_t offset = 0;

    memset(block, 0, SHAKE256_RATE);

    memcpy(block + offset, pub_seed, SPX_WOTS_CHAINX4_N);
    offset += SPX_WOTS_CHAINX4_N;
    memcpy(block + offset, addr, SPX_WOTS_CHAINX4_ADDR_BYTES);
    offset += SPX_WOTS_CHAINX4_ADDR_BYTES;
    memcpy(block + offset, input, inbytes);
    offset += inbytes;

    block[offset] = 0x1fu;
    block[SHAKE256_RATE - 1u] |= 0x80u;
}

static int valid_chain_window(uint32_t start_step, uint32_t num_steps)
{
    if (start_step > SPX_WOTS_CHAINX4_W) {
        return 0;
    }
    if (num_steps > SPX_WOTS_CHAINX4_MAX_STEPS) {
        return 0;
    }
    if (start_step + num_steps > SPX_WOTS_CHAINX4_W) {
        return 0;
    }
    return 1;
}

static int valid_mixed_chain_windows(
    const uint32_t start_steps[SPX_WOTS_CHAINX4_LANES],
    const uint32_t num_steps[SPX_WOTS_CHAINX4_LANES])
{
    if (start_steps == NULL || num_steps == NULL) {
        return 0;
    }

    for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
        if (!valid_chain_window(start_steps[lane], num_steps[lane])) {
            return 0;
        }
    }

    return 1;
}

static void compute_mixed_stats(
    const uint32_t num_steps[SPX_WOTS_CHAINX4_LANES],
    spx_wots_chainx4_stats_t *stats)
{
    uint32_t useful_lane_ops = 0;
    uint32_t max_num_steps = 0;
    uint32_t physical_lane_ops;

    if (stats == NULL) {
        return;
    }

    for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
        useful_lane_ops += num_steps[lane];
        if (num_steps[lane] > max_num_steps) {
            max_num_steps = num_steps[lane];
        }
    }

    physical_lane_ops = SPX_WOTS_CHAINX4_LANES * max_num_steps;
    stats->useful_lane_ops = useful_lane_ops;
    stats->physical_lane_ops = physical_lane_ops;
    stats->max_num_steps = max_num_steps;
    stats->lane_utilization = (physical_lane_ops == 0u) ? 0.0 :
        ((double)useful_lane_ops / (double)physical_lane_ops);
}

static void set_hash_addr(uint8_t addr[SPX_WOTS_CHAINX4_ADDR_BYTES],
                          uint32_t hash_step)
{
    addr[SPX_WOTS_CHAINX4_SHAKE_HASH_ADDR_OFFSET] = (uint8_t)hash_step;
}

static void thash_scalar_ref(
    uint8_t out[SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_ADDR_BYTES])
{
    uint8_t block[SHAKE256_RATE];
    uint8_t input[2u * SPX_WOTS_CHAINX4_N] = {0};
    uint64_t state[SPX_WOTS_CHAINX4_LANES][KECCAK_WORDS] = {{0}};

    memcpy(input, in, SPX_WOTS_CHAINX4_N);
    build_thash_block(block, input, 1u, pub_seed, addr);
    for (size_t word = 0; word < SHAKE256_RATE / 8u; word++) {
        state[0][word] = load64_le(block + 8u * word);
    }

    keccak_f1600x4(state);
    squeeze_spx_n(out, state[0]);
}

int spx_thashx4_model(
    uint8_t out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][2u * SPX_WOTS_CHAINX4_N],
    unsigned int inblocks,
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES])
{
    uint64_t state[SPX_WOTS_CHAINX4_LANES][KECCAK_WORDS] = {{0}};

    if (inblocks != 1u && inblocks != 2u) {
        return -1;
    }

    for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
        uint8_t block[SHAKE256_RATE];

        build_thash_block(block, in[lane], inblocks, pub_seed, addr[lane]);
        for (size_t word = 0; word < SHAKE256_RATE / 8u; word++) {
            state[lane][word] = load64_le(block + 8u * word);
        }
    }

    keccak_f1600x4(state);

    for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
        squeeze_spx_n(out[lane], state[lane]);
    }

    return 0;
}

int spx_wots_chainx4_model(
    uint8_t out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    uint32_t start_step,
    uint32_t num_steps)
{
    uint32_t start_steps[SPX_WOTS_CHAINX4_LANES];
    uint32_t lane_num_steps[SPX_WOTS_CHAINX4_LANES];

    for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
        start_steps[lane] = start_step;
        lane_num_steps[lane] = num_steps;
    }

    return spx_wots_chainx4_mixed_model(out, in, pub_seed, addr,
                                        start_steps, lane_num_steps, NULL);
}

int spx_wots_chainx4_mixed_model(
    uint8_t out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    const uint32_t start_steps[SPX_WOTS_CHAINX4_LANES],
    const uint32_t num_steps[SPX_WOTS_CHAINX4_LANES],
    spx_wots_chainx4_stats_t *stats)
{
    uint8_t chain[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N];
    uint8_t step_addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES];
    uint32_t max_num_steps = 0;

    if (!valid_mixed_chain_windows(start_steps, num_steps)) {
        return -1;
    }

    compute_mixed_stats(num_steps, stats);

    for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
        if (num_steps[lane] > max_num_steps) {
            max_num_steps = num_steps[lane];
        }
    }

    memcpy(chain, in, sizeof(chain));
    memcpy(step_addr, addr, sizeof(step_addr));

    for (uint32_t step = 0; step < max_num_steps; step++) {
        uint8_t thash_in[SPX_WOTS_CHAINX4_LANES][2u * SPX_WOTS_CHAINX4_N] = {{0}};
        uint8_t thash_out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N];

        for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
            if (step < num_steps[lane]) {
                set_hash_addr(step_addr[lane], start_steps[lane] + step);
            }
            memcpy(thash_in[lane], chain[lane], SPX_WOTS_CHAINX4_N);
        }

        if (spx_thashx4_model(thash_out, thash_in, 1u, pub_seed, step_addr) != 0) {
            return -1;
        }
        for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
            if (step < num_steps[lane]) {
                memcpy(chain[lane], thash_out[lane], SPX_WOTS_CHAINX4_N);
            }
        }
    }

    memcpy(out, chain, sizeof(chain));
    return 0;
}

int spx_wots_chainx4_scalar_ref(
    uint8_t out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    uint32_t start_step,
    uint32_t num_steps)
{
    uint32_t start_steps[SPX_WOTS_CHAINX4_LANES];
    uint32_t lane_num_steps[SPX_WOTS_CHAINX4_LANES];

    for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
        start_steps[lane] = start_step;
        lane_num_steps[lane] = num_steps;
    }

    return spx_wots_chainx4_mixed_scalar_ref(out, in, pub_seed, addr,
                                             start_steps, lane_num_steps);
}

int spx_wots_chainx4_mixed_scalar_ref(
    uint8_t out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    const uint32_t start_steps[SPX_WOTS_CHAINX4_LANES],
    const uint32_t num_steps[SPX_WOTS_CHAINX4_LANES])
{
    if (!valid_mixed_chain_windows(start_steps, num_steps)) {
        return -1;
    }

    for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
        uint8_t chain[SPX_WOTS_CHAINX4_N];
        uint8_t step_addr[SPX_WOTS_CHAINX4_ADDR_BYTES];

        memcpy(chain, in[lane], sizeof(chain));
        memcpy(step_addr, addr[lane], sizeof(step_addr));

        for (uint32_t step = 0; step < num_steps[lane]; step++) {
            uint8_t next[SPX_WOTS_CHAINX4_N];

            set_hash_addr(step_addr, start_steps[lane] + step);
            thash_scalar_ref(next, chain, pub_seed, step_addr);
            memcpy(chain, next, sizeof(chain));
        }

        memcpy(out[lane], chain, sizeof(chain));
    }

    return 0;
}

int spx_wots_chainx4_compare_scalar(
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    uint32_t start_step,
    uint32_t num_steps)
{
    uint8_t x4[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N];
    uint8_t scalar[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N];

    if (spx_wots_chainx4_model(x4, in, pub_seed, addr, start_step, num_steps) != 0) {
        return -1;
    }
    if (spx_wots_chainx4_scalar_ref(scalar, in, pub_seed, addr,
                                    start_step, num_steps) != 0) {
        return -1;
    }

    return memcmp(x4, scalar, sizeof(x4));
}

int spx_wots_chainx4_mixed_compare_scalar(
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    const uint32_t start_steps[SPX_WOTS_CHAINX4_LANES],
    const uint32_t num_steps[SPX_WOTS_CHAINX4_LANES],
    spx_wots_chainx4_stats_t *stats)
{
    uint8_t x4[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N];
    uint8_t scalar[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N];

    if (spx_wots_chainx4_mixed_model(x4, in, pub_seed, addr,
                                     start_steps, num_steps, stats) != 0) {
        return -1;
    }
    if (spx_wots_chainx4_mixed_scalar_ref(scalar, in, pub_seed, addr,
                                          start_steps, num_steps) != 0) {
        return -1;
    }

    return memcmp(x4, scalar, sizeof(x4));
}
