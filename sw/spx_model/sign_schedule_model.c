#include <stddef.h>
#include <string.h>

#include "sign_schedule_model.h"

typedef struct {
    const char *name;
    double thash_desc_cycles;
    double polls_per_desc;
} sensitivity_mode_t;

static const char *const component_names[SPX_SIGN_COMPONENT_COUNT] = {
    "WOTS chain generation",
    "WOTS pk compression",
    "FORS leaf/internal",
    "Merkle/treehash",
    "PRF/address/control"
};

static const char *const component_notes[SPX_SIGN_COMPONENT_COUNT] = {
    "176 WOTS pk generations; 135 THASHX4 descriptors/pk -> 9 grouped descriptors/pk",
    "software estimate; current accelerator does not cover inblocks=SPX_WOTS_LEN",
    "THASHX4 descriptor estimate for FORS leaves and inblocks=2 internal nodes",
    "THASHX4 descriptor estimate for sign-time treehash internal nodes",
    "software estimate for PRF_ADDR, message hashing/control, and FORS pk compression"
};

static const char *const traffic_names[SPX_SIGN_TRAFFIC_COUNT] = {
    "descriptor-per-step baseline",
    "THASHX4-only descriptor model",
    "WOTS_CHAINX4 grouped model"
};

static const char *const traffic_scopes[SPX_SIGN_TRAFFIC_COUNT] = {
    "WOTS chain generation only",
    "Full sign 1/2-block THASH work",
    "Full sign with grouped WOTS chains"
};

static const sensitivity_mode_t sensitivity_modes[SPX_SIGN_SENS_COUNT] = {
    {"zero wait", 57.00, 5.00},
    {"wait1", 84.50, 7.50},
    {"wait2", 106.50, 9.50},
    {"split read2/write4", 117.50, 10.50},
    {"random ready 50%", 81.06, 7.19},
    {"random ready 75%", 65.94, 5.81}
};

uint64_t spx_sign_schedule_ceil_div(uint64_t value, uint64_t divisor)
{
    if (divisor == 0u) {
        return 0u;
    }
    return (value + divisor - 1u) / divisor;
}

static void set_component(spx_sign_component_cycles_t *component,
                          uint64_t baseline_cycles,
                          uint64_t accelerated_cycles)
{
    component->baseline_cycles = baseline_cycles;
    component->accelerated_cycles = accelerated_cycles;
    component->speedup = (accelerated_cycles == 0u) ? 0.0 :
        (double)baseline_cycles / (double)accelerated_cycles;
}

static void add_traffic(spx_sign_traffic_t *traffic,
                        uint64_t descriptors,
                        uint64_t bus_reads_per_desc,
                        uint64_t bus_writes_per_desc)
{
    traffic->descriptors += descriptors;
    traffic->xif_instr += descriptors * SPX_SIGN_MODEL_XIF_PER_DESC;
    traffic->status_polls += descriptors * SPX_SIGN_MODEL_POLLS_PER_DESC;
    traffic->bus_reads += descriptors * bus_reads_per_desc;
    traffic->bus_writes += descriptors * bus_writes_per_desc;
}

static uint64_t wots_chain_baseline_descriptors_per_pk(void)
{
    return SPX_SIGN_MODEL_WOTS_GROUP_DESC_PER_PK *
           SPX_SIGN_MODEL_WOTS_CHAIN_STEPS;
}

static uint64_t wots_chain_baseline_cycles_per_pk(void)
{
    return wots_chain_baseline_descriptors_per_pk() *
           SPX_SIGN_MODEL_THASHX4_DESC_CYCLES;
}

static uint64_t wots_chain_grouped_cycles_per_pk(void)
{
    return SPX_SIGN_MODEL_WOTS_GROUP_DESC_PER_PK *
           SPX_SIGN_MODEL_WOTS_GROUP_DESC_CYCLES;
}

static uint64_t compute_prf_control_cycles(const spx_sign_work_counts_t *counts)
{
    return counts->prf_addr_calls * SPX_SIGN_MODEL_SOFTWARE_PRF_ADDR_CYCLES +
           SPX_SIGN_MODEL_TOP_HASH_CONTROL_CALLS *
               SPX_SIGN_MODEL_THASHX4_DESC_CYCLES +
           counts->fors_pk_compression_calls *
               SPX_SIGN_MODEL_SOFTWARE_SHAKE_LONG_CYCLES;
}

static uint64_t compute_software_constant_cycles(
    const spx_sign_schedule_result_t *result)
{
    return result->components[SPX_SIGN_COMPONENT_WOTS_PK_COMPRESSION]
               .accelerated_cycles +
           result->components[SPX_SIGN_COMPONENT_PRF_ADDR_CONTROL]
               .accelerated_cycles;
}

static void fill_counts(spx_sign_work_counts_t *counts)
{
    const uint64_t leaves_per_merkle_tree =
        1ULL << SPX_SIGN_MODEL_TREE_HEIGHT;
    const uint64_t fors_leaves_per_tree =
        1ULL << SPX_SIGN_MODEL_FORS_HEIGHT;
    const uint64_t fors_internal_per_tree = fors_leaves_per_tree - 1u;
    const uint64_t merkle_internal_per_tree = leaves_per_merkle_tree - 1u;

    memset(counts, 0, sizeof(*counts));

    counts->wots_pk_count = SPX_SIGN_MODEL_D * leaves_per_merkle_tree;
    counts->wots_chain_useful_steps =
        counts->wots_pk_count * SPX_SIGN_MODEL_WOTS_LEN *
        SPX_SIGN_MODEL_WOTS_CHAIN_STEPS;
    counts->wots_chain_physical_lane_ops =
        counts->wots_pk_count * SPX_SIGN_MODEL_WOTS_GROUP_DESC_PER_PK *
        SPX_SIGN_MODEL_THASHX4_LANES * SPX_SIGN_MODEL_WOTS_CHAIN_STEPS;
    counts->wots_chain_baseline_descriptors =
        counts->wots_pk_count * wots_chain_baseline_descriptors_per_pk();
    counts->wots_chain_grouped_descriptors =
        counts->wots_pk_count * SPX_SIGN_MODEL_WOTS_GROUP_DESC_PER_PK;
    counts->wots_pk_compression_calls = counts->wots_pk_count;

    counts->fors_leaf_jobs = SPX_SIGN_MODEL_FORS_TREES * fors_leaves_per_tree;
    counts->fors_internal_jobs =
        SPX_SIGN_MODEL_FORS_TREES * fors_internal_per_tree;
    counts->fors_leaf_descriptors =
        spx_sign_schedule_ceil_div(counts->fors_leaf_jobs,
                                   SPX_SIGN_MODEL_THASHX4_LANES);
    counts->fors_internal_descriptors =
        spx_sign_schedule_ceil_div(counts->fors_internal_jobs,
                                   SPX_SIGN_MODEL_THASHX4_LANES);

    counts->merkle_internal_jobs =
        SPX_SIGN_MODEL_D * merkle_internal_per_tree;
    counts->merkle_internal_descriptors =
        spx_sign_schedule_ceil_div(counts->merkle_internal_jobs,
                                   SPX_SIGN_MODEL_THASHX4_LANES);

    counts->wots_prf_addr_calls =
        counts->wots_pk_count * SPX_SIGN_MODEL_WOTS_LEN;
    counts->fors_prf_addr_calls =
        counts->fors_leaf_jobs + SPX_SIGN_MODEL_FORS_TREES;
    counts->prf_addr_calls =
        counts->wots_prf_addr_calls + counts->fors_prf_addr_calls;
    counts->fors_pk_compression_calls = 1u;
}

static void fill_components(spx_sign_schedule_result_t *result)
{
    const spx_sign_work_counts_t *counts = &result->counts;
    const uint64_t wots_baseline_cycles =
        counts->wots_pk_count * wots_chain_baseline_cycles_per_pk();
    const uint64_t wots_grouped_cycles =
        counts->wots_pk_count * wots_chain_grouped_cycles_per_pk();
    const uint64_t wots_pk_compression_cycles =
        counts->wots_pk_compression_calls *
        SPX_SIGN_MODEL_SOFTWARE_SHAKE_LONG_CYCLES;
    const uint64_t fors_cycles =
        (counts->fors_leaf_descriptors + counts->fors_internal_descriptors) *
        SPX_SIGN_MODEL_THASHX4_DESC_CYCLES;
    const uint64_t merkle_cycles =
        counts->merkle_internal_descriptors *
        SPX_SIGN_MODEL_THASHX4_DESC_CYCLES;
    const uint64_t prf_control_cycles =
        compute_prf_control_cycles(counts);

    set_component(&result->components[SPX_SIGN_COMPONENT_WOTS_CHAIN],
                  wots_baseline_cycles, wots_grouped_cycles);
    set_component(&result->components[SPX_SIGN_COMPONENT_WOTS_PK_COMPRESSION],
                  wots_pk_compression_cycles, wots_pk_compression_cycles);
    set_component(&result->components[SPX_SIGN_COMPONENT_FORS_LEAF_INTERNAL],
                  fors_cycles, fors_cycles);
    set_component(&result->components[SPX_SIGN_COMPONENT_MERKLE_TREEHASH],
                  merkle_cycles, merkle_cycles);
    set_component(&result->components[SPX_SIGN_COMPONENT_PRF_ADDR_CONTROL],
                  prf_control_cycles, prf_control_cycles);
}

static void fill_traffic(spx_sign_schedule_result_t *result)
{
    const spx_sign_work_counts_t *counts = &result->counts;

    add_traffic(&result->traffic[SPX_SIGN_TRAFFIC_WOTS_DESC_PER_STEP],
                counts->wots_chain_baseline_descriptors,
                SPX_SIGN_MODEL_BUS_RD_IB1_4W,
                SPX_SIGN_MODEL_BUS_WR_4W);

    add_traffic(&result->traffic[SPX_SIGN_TRAFFIC_THASHX4_ONLY],
                counts->wots_chain_baseline_descriptors,
                SPX_SIGN_MODEL_BUS_RD_IB1_4W,
                SPX_SIGN_MODEL_BUS_WR_4W);
    add_traffic(&result->traffic[SPX_SIGN_TRAFFIC_THASHX4_ONLY],
                counts->fors_leaf_descriptors,
                SPX_SIGN_MODEL_BUS_RD_IB1_4W,
                SPX_SIGN_MODEL_BUS_WR_4W);
    add_traffic(&result->traffic[SPX_SIGN_TRAFFIC_THASHX4_ONLY],
                counts->fors_internal_descriptors,
                SPX_SIGN_MODEL_BUS_RD_IB2_4W,
                SPX_SIGN_MODEL_BUS_WR_4W);
    add_traffic(&result->traffic[SPX_SIGN_TRAFFIC_THASHX4_ONLY],
                counts->merkle_internal_descriptors,
                SPX_SIGN_MODEL_BUS_RD_IB2_4W,
                SPX_SIGN_MODEL_BUS_WR_4W);

    add_traffic(&result->traffic[SPX_SIGN_TRAFFIC_WOTS_GROUPED],
                counts->wots_chain_grouped_descriptors,
                SPX_SIGN_MODEL_BUS_RD_IB1_4W,
                SPX_SIGN_MODEL_BUS_WR_4W);
    add_traffic(&result->traffic[SPX_SIGN_TRAFFIC_WOTS_GROUPED],
                counts->fors_leaf_descriptors,
                SPX_SIGN_MODEL_BUS_RD_IB1_4W,
                SPX_SIGN_MODEL_BUS_WR_4W);
    add_traffic(&result->traffic[SPX_SIGN_TRAFFIC_WOTS_GROUPED],
                counts->fors_internal_descriptors,
                SPX_SIGN_MODEL_BUS_RD_IB2_4W,
                SPX_SIGN_MODEL_BUS_WR_4W);
    add_traffic(&result->traffic[SPX_SIGN_TRAFFIC_WOTS_GROUPED],
                counts->merkle_internal_descriptors,
                SPX_SIGN_MODEL_BUS_RD_IB2_4W,
                SPX_SIGN_MODEL_BUS_WR_4W);
}

static void fill_totals(spx_sign_schedule_result_t *result)
{
    uint64_t baseline_total = 0;
    uint64_t accelerated_total = 0;

    for (size_t i = 0; i < SPX_SIGN_COMPONENT_COUNT; i++) {
        baseline_total += result->components[i].baseline_cycles;
        accelerated_total += result->components[i].accelerated_cycles;
    }

    result->baseline_total_cycles = baseline_total;
    result->accelerated_total_cycles = accelerated_total;
    result->wots_grouping_saved_cycles =
        result->components[SPX_SIGN_COMPONENT_WOTS_CHAIN].baseline_cycles -
        result->components[SPX_SIGN_COMPONENT_WOTS_CHAIN].accelerated_cycles;
    result->total_speedup = (accelerated_total == 0u) ? 0.0 :
        (double)baseline_total / (double)accelerated_total;
    result->wots_grouping_total_contribution_pct =
        (baseline_total == 0u) ? 0.0 :
        100.0 * (double)result->wots_grouping_saved_cycles /
        (double)baseline_total;
}

static void fill_sensitivity(spx_sign_schedule_result_t *result)
{
    const spx_sign_work_counts_t *counts = &result->counts;
    const uint64_t software_cycles = compute_software_constant_cycles(result);
    const uint64_t thash_only_desc =
        result->traffic[SPX_SIGN_TRAFFIC_THASHX4_ONLY].descriptors;
    const uint64_t grouped_desc =
        result->traffic[SPX_SIGN_TRAFFIC_WOTS_GROUPED].descriptors;
    const uint64_t non_wots_thash_desc =
        counts->fors_leaf_descriptors + counts->fors_internal_descriptors +
        counts->merkle_internal_descriptors;

    for (size_t i = 0; i < SPX_SIGN_SENS_COUNT; i++) {
        const sensitivity_mode_t *mode = &sensitivity_modes[i];
        const double memory_extra =
            mode->thash_desc_cycles -
            (double)SPX_SIGN_MODEL_THASHX4_DESC_CYCLES;
        const double grouped_desc_cycles =
            (double)SPX_SIGN_MODEL_WOTS_GROUP_DESC_CYCLES + memory_extra;
        spx_sign_sensitivity_result_t *out = &result->sensitivity[i];

        out->name = mode->name;
        out->baseline_total_cycles =
            (double)software_cycles +
            (double)thash_only_desc * mode->thash_desc_cycles;
        out->accelerated_total_cycles =
            (double)software_cycles +
            (double)counts->wots_chain_grouped_descriptors *
                grouped_desc_cycles +
            (double)non_wots_thash_desc * mode->thash_desc_cycles;
        out->speedup = out->accelerated_total_cycles == 0.0 ? 0.0 :
            out->baseline_total_cycles / out->accelerated_total_cycles;
        out->baseline_status_polls =
            (double)thash_only_desc * mode->polls_per_desc;
        out->accelerated_status_polls =
            (double)grouped_desc * mode->polls_per_desc;
        out->baseline_bus_reads =
            result->traffic[SPX_SIGN_TRAFFIC_THASHX4_ONLY].bus_reads;
        out->accelerated_bus_reads =
            result->traffic[SPX_SIGN_TRAFFIC_WOTS_GROUPED].bus_reads;
        out->baseline_bus_writes =
            result->traffic[SPX_SIGN_TRAFFIC_THASHX4_ONLY].bus_writes;
        out->accelerated_bus_writes =
            result->traffic[SPX_SIGN_TRAFFIC_WOTS_GROUPED].bus_writes;
    }
}

void spx_sign_schedule_model_compute(spx_sign_schedule_result_t *result)
{
    if (result == NULL) {
        return;
    }

    memset(result, 0, sizeof(*result));
    fill_counts(&result->counts);
    fill_components(result);
    fill_traffic(result);
    fill_totals(result);
    fill_sensitivity(result);
}

const char *spx_sign_component_name(spx_sign_component_id_t id)
{
    if (id >= SPX_SIGN_COMPONENT_COUNT) {
        return "unknown";
    }
    return component_names[id];
}

const char *spx_sign_component_note(spx_sign_component_id_t id)
{
    if (id >= SPX_SIGN_COMPONENT_COUNT) {
        return "";
    }
    return component_notes[id];
}

const char *spx_sign_traffic_name(spx_sign_traffic_id_t id)
{
    if (id >= SPX_SIGN_TRAFFIC_COUNT) {
        return "unknown";
    }
    return traffic_names[id];
}

const char *spx_sign_traffic_scope(spx_sign_traffic_id_t id)
{
    if (id >= SPX_SIGN_TRAFFIC_COUNT) {
        return "";
    }
    return traffic_scopes[id];
}
