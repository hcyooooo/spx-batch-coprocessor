#ifndef SPX_WOTS_PK_GROUPING_MODEL_H
#define SPX_WOTS_PK_GROUPING_MODEL_H

#include <stdint.h>

#include "wots_chainx4_model.h"

#define SPX_WOTS_PK_GROUPING_CURRENT_SHAKE_128F_LEN 35u
#define SPX_WOTS_PK_GROUPING_STRESS_LEN_67 67u
#define SPX_WOTS_PK_GROUPING_PK_START_STEP 0u
#define SPX_WOTS_PK_GROUPING_PK_NUM_STEPS SPX_WOTS_CHAINX4_MAX_STEPS

#define SPX_WOTS_PK_GROUPING_BASELINE_STEP_CYCLES 57u
#define SPX_WOTS_PK_GROUPING_DESCRIPTOR_SETUP_CYCLES 24u
#define SPX_WOTS_PK_GROUPING_CYCLES_PER_PHYSICAL_STEP 28u
#define SPX_WOTS_PK_GROUPING_XIF_INSTR_PER_DESCRIPTOR 9u
#define SPX_WOTS_PK_GROUPING_STATUS_POLLS_PER_DESCRIPTOR 5u
#define SPX_WOTS_PK_GROUPING_BUS_READS_PER_DESCRIPTOR 15u
#define SPX_WOTS_PK_GROUPING_BUS_WRITES_PER_DESCRIPTOR 5u

#define SPX_WOTS_PK_GROUPING_INVALID_CHAIN 0xffffffffu

typedef enum {
    SPX_WOTS_PK_GROUPING_DESC_UNIFORM = 1,
    SPX_WOTS_PK_GROUPING_DESC_MIXED = 2
} spx_wots_pk_grouping_desc_op_t;

typedef struct {
    uint8_t input[SPX_WOTS_CHAINX4_N];
    uint8_t addr[SPX_WOTS_CHAINX4_ADDR_BYTES];
    uint32_t start_step;
    uint32_t num_steps;
} spx_wots_pk_chain_t;

typedef struct {
    spx_wots_pk_grouping_desc_op_t op_type;
    uint32_t lane_count;
    uint32_t chain_index[SPX_WOTS_CHAINX4_LANES];
    uint32_t start_steps[SPX_WOTS_CHAINX4_LANES];
    uint32_t num_steps[SPX_WOTS_CHAINX4_LANES];
    uint32_t useful_lane_ops;
    uint32_t physical_lane_ops;
    uint32_t max_num_steps;
} spx_wots_pk_grouping_desc_t;

typedef struct {
    uint32_t descriptor_count;
    uint32_t uniform_descriptor_count;
    uint32_t mixed_descriptor_count;
    uint32_t baseline_descriptor_count;
    uint64_t total_chain_steps;
    uint64_t useful_lane_ops;
    uint64_t physical_lane_ops;
    double lane_utilization;
    uint64_t estimated_cycles;
    uint64_t baseline_cycles;
    double estimated_speedup;
    uint64_t xif_instr;
    uint64_t baseline_xif_instr;
    uint64_t status_polls;
    uint64_t baseline_status_polls;
    uint64_t bus_reads;
    uint64_t baseline_bus_reads;
    uint64_t bus_writes;
    uint64_t baseline_bus_writes;
} spx_wots_pk_grouping_stats_t;

uint32_t spx_wots_pk_grouping_descriptor_capacity(uint32_t chain_count);

int spx_wots_pk_group_chains(
    const spx_wots_pk_chain_t *chains,
    uint32_t chain_count,
    spx_wots_pk_grouping_desc_t *descriptors,
    uint32_t max_descriptors,
    spx_wots_pk_grouping_stats_t *stats);

int spx_wots_pk_grouping_execute(
    uint8_t (*out)[SPX_WOTS_CHAINX4_N],
    const spx_wots_pk_chain_t *chains,
    uint32_t chain_count,
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    spx_wots_pk_grouping_stats_t *stats);

int spx_wots_pk_grouping_scalar_ref(
    uint8_t (*out)[SPX_WOTS_CHAINX4_N],
    const spx_wots_pk_chain_t *chains,
    uint32_t chain_count,
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N]);

int spx_wots_pk_grouping_compare_scalar(
    const spx_wots_pk_chain_t *chains,
    uint32_t chain_count,
    const uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
    spx_wots_pk_grouping_stats_t *stats);

#endif
