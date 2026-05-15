#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "wots_pk_grouping_model.h"

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

uint32_t spx_wots_pk_grouping_descriptor_capacity(uint32_t chain_count)
{
    return (chain_count + SPX_WOTS_CHAINX4_LANES - 1u) /
           SPX_WOTS_CHAINX4_LANES;
}

static void finish_stats(spx_wots_pk_grouping_stats_t *stats)
{
    if (stats == NULL) {
        return;
    }

    stats->total_chain_steps = stats->useful_lane_ops;
    stats->lane_utilization = (stats->physical_lane_ops == 0u) ? 0.0 :
        ((double)stats->useful_lane_ops / (double)stats->physical_lane_ops);
    stats->estimated_speedup = (stats->estimated_cycles == 0u) ? 0.0 :
        ((double)stats->baseline_cycles / (double)stats->estimated_cycles);

    stats->xif_instr =
        (uint64_t)stats->descriptor_count *
        SPX_WOTS_PK_GROUPING_XIF_INSTR_PER_DESCRIPTOR;
    stats->status_polls =
        (uint64_t)stats->descriptor_count *
        SPX_WOTS_PK_GROUPING_STATUS_POLLS_PER_DESCRIPTOR;
    stats->bus_reads =
        (uint64_t)stats->descriptor_count *
        SPX_WOTS_PK_GROUPING_BUS_READS_PER_DESCRIPTOR;
    stats->bus_writes =
        (uint64_t)stats->descriptor_count *
        SPX_WOTS_PK_GROUPING_BUS_WRITES_PER_DESCRIPTOR;

    stats->baseline_xif_instr =
        (uint64_t)stats->baseline_descriptor_count *
        SPX_WOTS_PK_GROUPING_XIF_INSTR_PER_DESCRIPTOR;
    stats->baseline_status_polls =
        (uint64_t)stats->baseline_descriptor_count *
        SPX_WOTS_PK_GROUPING_STATUS_POLLS_PER_DESCRIPTOR;
    stats->baseline_bus_reads =
        (uint64_t)stats->baseline_descriptor_count *
        SPX_WOTS_PK_GROUPING_BUS_READS_PER_DESCRIPTOR;
    stats->baseline_bus_writes =
        (uint64_t)stats->baseline_descriptor_count *
        SPX_WOTS_PK_GROUPING_BUS_WRITES_PER_DESCRIPTOR;
}

static int build_descriptor(
    const spx_wots_pk_chain_t *chains,
    uint32_t chain_count,
    uint32_t group,
    spx_wots_pk_grouping_desc_t *desc)
{
    uint32_t first_chain = group * SPX_WOTS_CHAINX4_LANES;
    uint32_t active_lanes = 0;
    uint32_t useful_lane_ops = 0;
    uint32_t max_num_steps = 0;
    int uniform = 1;

    memset(desc, 0, sizeof(*desc));
    desc->op_type = SPX_WOTS_PK_GROUPING_DESC_MIXED;

    for (uint32_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
        uint32_t chain_index = first_chain + lane;

        desc->chain_index[lane] = SPX_WOTS_PK_GROUPING_INVALID_CHAIN;
        if (chain_index >= chain_count) {
            continue;
        }

        if (!valid_chain_window(chains[chain_index].start_step,
                                chains[chain_index].num_steps)) {
            return -1;
        }

        desc->chain_index[lane] = chain_index;
        desc->start_steps[lane] = chains[chain_index].start_step;
        desc->num_steps[lane] = chains[chain_index].num_steps;

        useful_lane_ops += chains[chain_index].num_steps;
        if (chains[chain_index].num_steps > max_num_steps) {
            max_num_steps = chains[chain_index].num_steps;
        }

        if (active_lanes > 0u &&
            (desc->start_steps[lane] != desc->start_steps[0] ||
             desc->num_steps[lane] != desc->num_steps[0])) {
            uniform = 0;
        }
        active_lanes++;
    }

    desc->lane_count = active_lanes;
    desc->useful_lane_ops = useful_lane_ops;
    desc->max_num_steps = max_num_steps;
    desc->physical_lane_ops =
        (max_num_steps == 0u) ? 0u :
        SPX_WOTS_CHAINX4_LANES * max_num_steps;

    if (active_lanes == SPX_WOTS_CHAINX4_LANES &&
        max_num_steps > 0u && uniform) {
        desc->op_type = SPX_WOTS_PK_GROUPING_DESC_UNIFORM;
    }

    return 0;
}

int spx_wots_pk_group_chains(
    const spx_wots_pk_chain_t *chains,
    uint32_t chain_count,
    spx_wots_pk_grouping_desc_t *descriptors,
    uint32_t max_descriptors,
    spx_wots_pk_grouping_stats_t *stats)
{
    const uint32_t descriptor_capacity =
        spx_wots_pk_grouping_descriptor_capacity(chain_count);

    if (chain_count > 0u && chains == NULL) {
        return -1;
    }
    if (descriptors != NULL && max_descriptors < descriptor_capacity) {
        return -1;
    }

    if (stats != NULL) {
        memset(stats, 0, sizeof(*stats));
    }

    for (uint32_t group = 0; group < descriptor_capacity; group++) {
        spx_wots_pk_grouping_desc_t local_desc;
        spx_wots_pk_grouping_desc_t *desc =
            (descriptors == NULL) ? &local_desc : &descriptors[group];

        if (build_descriptor(chains, chain_count, group, desc) != 0) {
            return -1;
        }

        if (stats != NULL && desc->max_num_steps > 0u) {
            stats->descriptor_count++;
            if (desc->op_type == SPX_WOTS_PK_GROUPING_DESC_UNIFORM) {
                stats->uniform_descriptor_count++;
            } else {
                stats->mixed_descriptor_count++;
            }
            stats->baseline_descriptor_count += desc->max_num_steps;
            stats->useful_lane_ops += desc->useful_lane_ops;
            stats->physical_lane_ops += desc->physical_lane_ops;
            stats->baseline_cycles +=
                (uint64_t)desc->max_num_steps *
                SPX_WOTS_PK_GROUPING_BASELINE_STEP_CYCLES;
            stats->estimated_cycles +=
                SPX_WOTS_PK_GROUPING_DESCRIPTOR_SETUP_CYCLES +
                (uint64_t)desc->max_num_steps *
                SPX_WOTS_PK_GROUPING_CYCLES_PER_PHYSICAL_STEP;
        }
    }

    finish_stats(stats);
    return 0;
}

int spx_wots_pk_grouping_execute(
    uint8_t (*out)[SPX_WOTS_CHAINX4_N],
    const spx_wots_pk_chain_t *chains,
    uint32_t chain_count,
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    spx_wots_pk_grouping_stats_t *stats)
{
    const uint32_t descriptor_capacity =
        spx_wots_pk_grouping_descriptor_capacity(chain_count);

    if (chain_count > 0u && (out == NULL || chains == NULL || pub_seed == NULL)) {
        return -1;
    }

    if (spx_wots_pk_group_chains(chains, chain_count, NULL, 0u, stats) != 0) {
        return -1;
    }

    for (uint32_t group = 0; group < descriptor_capacity; group++) {
        spx_wots_pk_grouping_desc_t desc;
        uint8_t input[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N] = {{0}};
        uint8_t output[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N] = {{0}};
        uint8_t addr[SPX_WOTS_CHAINX4_LANES]
                    [SPX_WOTS_CHAINX4_ADDR_BYTES] = {{0}};

        if (build_descriptor(chains, chain_count, group, &desc) != 0) {
            return -1;
        }

        for (uint32_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
            if (desc.chain_index[lane] == SPX_WOTS_PK_GROUPING_INVALID_CHAIN) {
                continue;
            }
            memcpy(input[lane], chains[desc.chain_index[lane]].input,
                   SPX_WOTS_CHAINX4_N);
            memcpy(addr[lane], chains[desc.chain_index[lane]].addr,
                   SPX_WOTS_CHAINX4_ADDR_BYTES);
        }

        if (desc.max_num_steps == 0u) {
            memcpy(output, input, sizeof(output));
        } else if (desc.op_type == SPX_WOTS_PK_GROUPING_DESC_UNIFORM) {
            if (spx_wots_chainx4_model(output, input, pub_seed, addr,
                                       desc.start_steps[0],
                                       desc.num_steps[0]) != 0) {
                return -1;
            }
        } else {
            if (spx_wots_chainx4_mixed_model(output, input, pub_seed, addr,
                                             desc.start_steps,
                                             desc.num_steps, NULL) != 0) {
                return -1;
            }
        }

        for (uint32_t lane = 0; lane < SPX_WOTS_CHAINX4_LANES; lane++) {
            if (desc.chain_index[lane] == SPX_WOTS_PK_GROUPING_INVALID_CHAIN) {
                continue;
            }
            memcpy(out[desc.chain_index[lane]], output[lane],
                   SPX_WOTS_CHAINX4_N);
        }
    }

    return 0;
}

int spx_wots_pk_grouping_scalar_ref(
    uint8_t (*out)[SPX_WOTS_CHAINX4_N],
    const spx_wots_pk_chain_t *chains,
    uint32_t chain_count,
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N])
{
    if (chain_count > 0u && (out == NULL || chains == NULL || pub_seed == NULL)) {
        return -1;
    }

    for (uint32_t chain = 0; chain < chain_count; chain++) {
        uint8_t input[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N] = {{0}};
        uint8_t output[SPX_WOTS_CHAINX4_LANES][SPX_WOTS_CHAINX4_N] = {{0}};
        uint8_t addr[SPX_WOTS_CHAINX4_LANES]
                    [SPX_WOTS_CHAINX4_ADDR_BYTES] = {{0}};
        uint32_t start_steps[SPX_WOTS_CHAINX4_LANES] = {0};
        uint32_t num_steps[SPX_WOTS_CHAINX4_LANES] = {0};

        if (!valid_chain_window(chains[chain].start_step,
                                chains[chain].num_steps)) {
            return -1;
        }

        memcpy(input[0], chains[chain].input, SPX_WOTS_CHAINX4_N);
        memcpy(addr[0], chains[chain].addr, SPX_WOTS_CHAINX4_ADDR_BYTES);
        start_steps[0] = chains[chain].start_step;
        num_steps[0] = chains[chain].num_steps;

        if (spx_wots_chainx4_mixed_scalar_ref(output, input, pub_seed, addr,
                                              start_steps, num_steps) != 0) {
            return -1;
        }
        memcpy(out[chain], output[0], SPX_WOTS_CHAINX4_N);
    }

    return 0;
}

int spx_wots_pk_grouping_compare_scalar(
    const spx_wots_pk_chain_t *chains,
    uint32_t chain_count,
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    spx_wots_pk_grouping_stats_t *stats)
{
    const size_t output_bytes = (size_t)chain_count * SPX_WOTS_CHAINX4_N;
    uint8_t (*grouped)[SPX_WOTS_CHAINX4_N] = NULL;
    uint8_t (*scalar)[SPX_WOTS_CHAINX4_N] = NULL;
    int result = -1;

    if (chain_count == 0u) {
        return spx_wots_pk_group_chains(chains, chain_count, NULL, 0u, stats);
    }
    if (output_bytes / SPX_WOTS_CHAINX4_N != chain_count) {
        return -1;
    }

    grouped = malloc(output_bytes);
    scalar = malloc(output_bytes);
    if (grouped == NULL || scalar == NULL) {
        goto out;
    }

    if (spx_wots_pk_grouping_execute(grouped, chains, chain_count,
                                     pub_seed, stats) != 0) {
        goto out;
    }
    if (spx_wots_pk_grouping_scalar_ref(scalar, chains, chain_count,
                                        pub_seed) != 0) {
        goto out;
    }

    result = memcmp(grouped, scalar, output_bytes);

out:
    free(grouped);
    free(scalar);
    return result;
}
