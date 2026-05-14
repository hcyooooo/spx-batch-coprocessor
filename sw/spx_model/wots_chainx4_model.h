#ifndef SPX_WOTS_CHAINX4_MODEL_H
#define SPX_WOTS_CHAINX4_MODEL_H

#include <stdint.h>

#define SPX_WOTS_CHAINX4_LANES 4u
#define SPX_WOTS_CHAINX4_N 16u
#define SPX_WOTS_CHAINX4_ADDR_BYTES 32u
#define SPX_WOTS_CHAINX4_W 16u
#define SPX_WOTS_CHAINX4_MAX_STEPS (SPX_WOTS_CHAINX4_W - 1u)
#define SPX_WOTS_CHAINX4_SHAKE_HASH_ADDR_OFFSET 31u

typedef struct {
    uint32_t useful_lane_ops;
    uint32_t physical_lane_ops;
    uint32_t max_num_steps;
    double lane_utilization;
} spx_wots_chainx4_stats_t;

int spx_thashx4_model(
    uint8_t out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][2u * SPX_WOTS_CHAINX4_N],
    unsigned int inblocks,
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES]);

int spx_wots_chainx4_model(
    uint8_t out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    uint32_t start_step,
    uint32_t num_steps);

int spx_wots_chainx4_mixed_model(
    uint8_t out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    const uint32_t start_steps[SPX_WOTS_CHAINX4_LANES],
    const uint32_t num_steps[SPX_WOTS_CHAINX4_LANES],
    spx_wots_chainx4_stats_t *stats);

int spx_wots_chainx4_scalar_ref(
    uint8_t out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    uint32_t start_step,
    uint32_t num_steps);

int spx_wots_chainx4_mixed_scalar_ref(
    uint8_t out[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    const uint32_t start_steps[SPX_WOTS_CHAINX4_LANES],
    const uint32_t num_steps[SPX_WOTS_CHAINX4_LANES]);

int spx_wots_chainx4_compare_scalar(
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    uint32_t start_step,
    uint32_t num_steps);

int spx_wots_chainx4_mixed_compare_scalar(
    const uint8_t in[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N],
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    const uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES],
    const uint32_t start_steps[SPX_WOTS_CHAINX4_LANES],
    const uint32_t num_steps[SPX_WOTS_CHAINX4_LANES],
    spx_wots_chainx4_stats_t *stats);

#endif
