#ifndef SPX_DESCRIPTOR_EXT_MODEL_H
#define SPX_DESCRIPTOR_EXT_MODEL_H

#include <stdint.h>

#include "wots_chainx4_model.h"

#define SPX_DESCRIPTOR_MODEL_VARIANT_SHAKE_128F_SIMPLE 1u
#define SPX_DESCRIPTOR_MODEL_LANES_X4 4u
#define SPX_DESCRIPTOR_MODEL_BASELINE_WALL_CYCLES 57u
#define SPX_DESCRIPTOR_MODEL_BASELINE_XIF_INSTR 9u
#define SPX_DESCRIPTOR_MODEL_BASELINE_STATUS_POLLS 5u
#define SPX_DESCRIPTOR_MODEL_BASELINE_BUS_RD_IB1_4W 15u
#define SPX_DESCRIPTOR_MODEL_BASELINE_BUS_WR_4W 5u

typedef enum {
    SPX_DESCRIPTOR_MODEL_OP_THASHX4 = 0,
    SPX_DESCRIPTOR_MODEL_OP_WOTS_CHAINX4 = 1,
    SPX_DESCRIPTOR_MODEL_OP_WOTS_CHAINX4_MIXED = 2
} spx_descriptor_model_op_t;

typedef struct {
    spx_descriptor_model_op_t op_type;
    const uint8_t *pub_seed_ptr;
    const uint8_t *addr_base_ptr;
    const uint8_t *input_base_ptr;
    uint8_t *output_base_ptr;
    uint32_t inblocks;
    uint32_t start_step;
    uint32_t num_steps;
    uint32_t start_steps[SPX_WOTS_CHAINX4_LANES];
    uint32_t lane_num_steps[SPX_WOTS_CHAINX4_LANES];
    uint32_t lanes;
    uint32_t variant;
} spx_descriptor_model_t;

typedef struct {
    uint32_t descriptors;
    uint32_t wall_cycles;
    uint32_t xif_instr;
    uint32_t status_polls;
    uint32_t bus_rd;
    uint32_t bus_wr;
    uint32_t thash_equiv;
} spx_descriptor_model_stats_t;

int spx_descriptor_model_execute(const spx_descriptor_model_t *desc);

void spx_descriptor_model_estimate_repeated_thashx4(
    uint32_t num_steps,
    spx_descriptor_model_stats_t *stats);

void spx_descriptor_model_estimate_wots_chainx4(
    uint32_t num_steps,
    uint32_t chain_scheduler_cycles,
    spx_descriptor_model_stats_t *stats);

void spx_descriptor_model_estimate_wots_chainx4_mixed(
    const uint32_t num_steps[SPX_WOTS_CHAINX4_LANES],
    uint32_t chain_scheduler_cycles,
    spx_descriptor_model_stats_t *stats);

#endif
