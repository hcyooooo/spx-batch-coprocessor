#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "descriptor_ext_model.h"

static int descriptor_config_ok(const spx_descriptor_model_t *desc)
{
    if (desc == NULL) {
        return 0;
    }
    if (desc->pub_seed_ptr == NULL || desc->addr_base_ptr == NULL ||
        desc->input_base_ptr == NULL || desc->output_base_ptr == NULL) {
        return 0;
    }
    if (desc->lanes != SPX_DESCRIPTOR_MODEL_LANES_X4) {
        return 0;
    }
    if (desc->variant != SPX_DESCRIPTOR_MODEL_VARIANT_SHAKE_128F_SIMPLE) {
        return 0;
    }
    return 1;
}

int spx_descriptor_model_execute(const spx_descriptor_model_t *desc)
{
    uint8_t pub_seed[SPX_WOTS_CHAINX4_N];
    uint8_t addr[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_ADDR_BYTES];

    if (!descriptor_config_ok(desc)) {
        return -1;
    }

    memcpy(pub_seed, desc->pub_seed_ptr, sizeof(pub_seed));
    for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
        memcpy(addr[lane],
               desc->addr_base_ptr + lane * SPX_WOTS_CHAINX4_ADDR_BYTES,
               SPX_WOTS_CHAINX4_ADDR_BYTES);
    }

    if (desc->op_type == SPX_DESCRIPTOR_MODEL_OP_THASHX4) {
        uint8_t input[SPX_WOTS_CHAINX4_LANES][2u * SPX_WOTS_CHAINX4_N] = {{0}};
        uint8_t output[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N];
        const size_t inbytes = (size_t)desc->inblocks * SPX_WOTS_CHAINX4_N;

        if (desc->inblocks != 1u && desc->inblocks != 2u) {
            return -1;
        }
        for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
            memcpy(input[lane],
                   desc->input_base_ptr + lane * inbytes,
                   inbytes);
        }
        if (spx_thashx4_model(output, input, desc->inblocks, pub_seed, addr) != 0) {
            return -1;
        }
        for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
            memcpy(desc->output_base_ptr + lane * SPX_WOTS_CHAINX4_N,
                   output[lane], SPX_WOTS_CHAINX4_N);
        }
        return 0;
    }

    if (desc->op_type == SPX_DESCRIPTOR_MODEL_OP_WOTS_CHAINX4) {
        uint8_t input[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N];
        uint8_t output[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N];

        for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
            memcpy(input[lane],
                   desc->input_base_ptr + lane * SPX_WOTS_CHAINX4_N,
                   SPX_WOTS_CHAINX4_N);
        }
        if (spx_wots_chainx4_model(output, input, pub_seed, addr,
                                   desc->start_step, desc->num_steps) != 0) {
            return -1;
        }
        for (size_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
            memcpy(desc->output_base_ptr + lane * SPX_WOTS_CHAINX4_N,
                   output[lane], SPX_WOTS_CHAINX4_N);
        }
        return 0;
    }

    return -1;
}

void spx_descriptor_model_estimate_repeated_thashx4(
    uint32_t num_steps,
    spx_descriptor_model_stats_t *stats)
{
    if (stats == NULL) {
        return;
    }

    stats->descriptors = num_steps;
    stats->wall_cycles = SPX_DESCRIPTOR_MODEL_BASELINE_WALL_CYCLES * num_steps;
    stats->xif_instr = SPX_DESCRIPTOR_MODEL_BASELINE_XIF_INSTR * num_steps;
    stats->status_polls = SPX_DESCRIPTOR_MODEL_BASELINE_STATUS_POLLS * num_steps;
    stats->bus_rd = SPX_DESCRIPTOR_MODEL_BASELINE_BUS_RD_IB1_4W * num_steps;
    stats->bus_wr = SPX_DESCRIPTOR_MODEL_BASELINE_BUS_WR_4W * num_steps;
    stats->thash_equiv = SPX_WOTS_CHAINX4_LANES * num_steps;
}

void spx_descriptor_model_estimate_wots_chainx4(
    uint32_t num_steps,
    uint32_t chain_scheduler_cycles,
    spx_descriptor_model_stats_t *stats)
{
    if (stats == NULL) {
        return;
    }

    stats->descriptors = (num_steps == 0u) ? 0u : 1u;
    stats->wall_cycles = chain_scheduler_cycles;
    stats->xif_instr = (num_steps == 0u) ? 0u : SPX_DESCRIPTOR_MODEL_BASELINE_XIF_INSTR;
    stats->status_polls = (num_steps == 0u) ? 0u : SPX_DESCRIPTOR_MODEL_BASELINE_STATUS_POLLS;
    stats->bus_rd = (num_steps == 0u) ? 0u : SPX_DESCRIPTOR_MODEL_BASELINE_BUS_RD_IB1_4W;
    stats->bus_wr = (num_steps == 0u) ? 0u : SPX_DESCRIPTOR_MODEL_BASELINE_BUS_WR_4W;
    stats->thash_equiv = SPX_WOTS_CHAINX4_LANES * num_steps;
}
