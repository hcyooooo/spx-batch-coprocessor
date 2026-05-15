#ifndef SPX_SIGN_SCHEDULE_MODEL_H
#define SPX_SIGN_SCHEDULE_MODEL_H

#include <stdint.h>

#include "descriptor_ext_model.h"
#include "wots_pk_grouping_model.h"

#define SPX_SIGN_MODEL_N 16u
#define SPX_SIGN_MODEL_FULL_HEIGHT 66u
#define SPX_SIGN_MODEL_D 22u
#define SPX_SIGN_MODEL_TREE_HEIGHT \
    (SPX_SIGN_MODEL_FULL_HEIGHT / SPX_SIGN_MODEL_D)
#define SPX_SIGN_MODEL_FORS_HEIGHT 6u
#define SPX_SIGN_MODEL_FORS_TREES 33u
#define SPX_SIGN_MODEL_WOTS_LEN \
    SPX_WOTS_PK_GROUPING_CURRENT_SHAKE_128F_LEN
#define SPX_SIGN_MODEL_WOTS_CHAIN_STEPS \
    SPX_WOTS_PK_GROUPING_PK_NUM_STEPS
#define SPX_SIGN_MODEL_THASHX4_LANES SPX_DESCRIPTOR_MODEL_LANES_X4

#define SPX_SIGN_MODEL_THASHX4_DESC_CYCLES \
    SPX_DESCRIPTOR_MODEL_BASELINE_WALL_CYCLES
#define SPX_SIGN_MODEL_WOTS_GROUP_DESC_CYCLES \
    (SPX_WOTS_PK_GROUPING_DESCRIPTOR_SETUP_CYCLES + \
     SPX_SIGN_MODEL_WOTS_CHAIN_STEPS * \
     SPX_WOTS_PK_GROUPING_CYCLES_PER_PHYSICAL_STEP)
#define SPX_SIGN_MODEL_WOTS_GROUP_DESC_PER_PK \
    ((SPX_SIGN_MODEL_WOTS_LEN + SPX_SIGN_MODEL_THASHX4_LANES - 1u) / \
     SPX_SIGN_MODEL_THASHX4_LANES)

#define SPX_SIGN_MODEL_XIF_PER_DESC \
    SPX_DESCRIPTOR_MODEL_BASELINE_XIF_INSTR
#define SPX_SIGN_MODEL_POLLS_PER_DESC \
    SPX_DESCRIPTOR_MODEL_BASELINE_STATUS_POLLS
#define SPX_SIGN_MODEL_BUS_RD_IB1_4W \
    SPX_DESCRIPTOR_MODEL_BASELINE_BUS_RD_IB1_4W
#define SPX_SIGN_MODEL_BUS_RD_IB2_4W 19u
#define SPX_SIGN_MODEL_BUS_WR_4W \
    SPX_DESCRIPTOR_MODEL_BASELINE_BUS_WR_4W

#define SPX_SIGN_MODEL_SOFTWARE_PRF_ADDR_CYCLES 57u
#define SPX_SIGN_MODEL_SOFTWARE_SHAKE_LONG_CYCLES \
    (5u * SPX_SIGN_MODEL_THASHX4_DESC_CYCLES)
#define SPX_SIGN_MODEL_TOP_HASH_CONTROL_CALLS 2u

typedef enum {
    SPX_SIGN_COMPONENT_WOTS_CHAIN = 0,
    SPX_SIGN_COMPONENT_WOTS_PK_COMPRESSION,
    SPX_SIGN_COMPONENT_FORS_LEAF_INTERNAL,
    SPX_SIGN_COMPONENT_MERKLE_TREEHASH,
    SPX_SIGN_COMPONENT_PRF_ADDR_CONTROL,
    SPX_SIGN_COMPONENT_COUNT
} spx_sign_component_id_t;

typedef enum {
    SPX_SIGN_TRAFFIC_WOTS_DESC_PER_STEP = 0,
    SPX_SIGN_TRAFFIC_THASHX4_ONLY,
    SPX_SIGN_TRAFFIC_WOTS_GROUPED,
    SPX_SIGN_TRAFFIC_COUNT
} spx_sign_traffic_id_t;

typedef enum {
    SPX_SIGN_SENS_ZERO_WAIT = 0,
    SPX_SIGN_SENS_WAIT1,
    SPX_SIGN_SENS_WAIT2,
    SPX_SIGN_SENS_SPLIT_READ2_WRITE4,
    SPX_SIGN_SENS_RANDOM_READY_50,
    SPX_SIGN_SENS_RANDOM_READY_75,
    SPX_SIGN_SENS_COUNT
} spx_sign_sensitivity_id_t;

typedef struct {
    uint64_t baseline_cycles;
    uint64_t accelerated_cycles;
    double speedup;
} spx_sign_component_cycles_t;

typedef struct {
    uint64_t descriptors;
    uint64_t xif_instr;
    uint64_t status_polls;
    uint64_t bus_reads;
    uint64_t bus_writes;
} spx_sign_traffic_t;

typedef struct {
    const char *name;
    double baseline_total_cycles;
    double accelerated_total_cycles;
    double speedup;
    double baseline_status_polls;
    double accelerated_status_polls;
    uint64_t baseline_bus_reads;
    uint64_t accelerated_bus_reads;
    uint64_t baseline_bus_writes;
    uint64_t accelerated_bus_writes;
} spx_sign_sensitivity_result_t;

typedef struct {
    uint64_t wots_pk_count;
    uint64_t wots_chain_useful_steps;
    uint64_t wots_chain_physical_lane_ops;
    uint64_t wots_chain_baseline_descriptors;
    uint64_t wots_chain_grouped_descriptors;
    uint64_t wots_pk_compression_calls;
    uint64_t fors_leaf_jobs;
    uint64_t fors_internal_jobs;
    uint64_t fors_leaf_descriptors;
    uint64_t fors_internal_descriptors;
    uint64_t merkle_internal_jobs;
    uint64_t merkle_internal_descriptors;
    uint64_t prf_addr_calls;
    uint64_t wots_prf_addr_calls;
    uint64_t fors_prf_addr_calls;
    uint64_t fors_pk_compression_calls;
} spx_sign_work_counts_t;

typedef struct {
    spx_sign_work_counts_t counts;
    spx_sign_component_cycles_t components[SPX_SIGN_COMPONENT_COUNT];
    spx_sign_traffic_t traffic[SPX_SIGN_TRAFFIC_COUNT];
    spx_sign_sensitivity_result_t sensitivity[SPX_SIGN_SENS_COUNT];
    uint64_t baseline_total_cycles;
    uint64_t accelerated_total_cycles;
    uint64_t wots_grouping_saved_cycles;
    double total_speedup;
    double wots_grouping_total_contribution_pct;
} spx_sign_schedule_result_t;

uint64_t spx_sign_schedule_ceil_div(uint64_t value, uint64_t divisor);

void spx_sign_schedule_model_compute(spx_sign_schedule_result_t *result);

const char *spx_sign_component_name(spx_sign_component_id_t id);
const char *spx_sign_component_note(spx_sign_component_id_t id);
const char *spx_sign_traffic_name(spx_sign_traffic_id_t id);
const char *spx_sign_traffic_scope(spx_sign_traffic_id_t id);

#endif
