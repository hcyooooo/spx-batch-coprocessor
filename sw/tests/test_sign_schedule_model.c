#include <inttypes.h>
#include <stdio.h>

#include "sign_schedule_model.h"

static int fail_if(int cond, const char *name)
{
    if (cond) {
        printf("FAIL %s\n", name);
        return 1;
    }
    return 0;
}

static uint64_t rounded_double(double value)
{
    return (uint64_t)(value + 0.5);
}

static void print_component_table(const spx_sign_schedule_result_t *result)
{
    printf("\nComponent | Baseline model cycles | Accelerated model cycles | "
           "Speedup | Notes\n");
    printf("--- | ---: | ---: | ---: | ---\n");
    for (unsigned int i = 0; i < SPX_SIGN_COMPONENT_COUNT; i++) {
        const spx_sign_component_cycles_t *component =
            &result->components[i];
        printf("%s | %" PRIu64 " | %" PRIu64 " | %.2fx | %s\n",
               spx_sign_component_name((spx_sign_component_id_t)i),
               component->baseline_cycles,
               component->accelerated_cycles,
               component->speedup,
               spx_sign_component_note((spx_sign_component_id_t)i));
    }
    printf("Total sign estimate | %" PRIu64 " | %" PRIu64 " | %.2fx | "
           "model total\n",
           result->baseline_total_cycles,
           result->accelerated_total_cycles,
           result->total_speedup);
}

static void print_traffic_table(const spx_sign_schedule_result_t *result)
{
    printf("\nModel | Scope | total descriptors | XIF instructions | "
           "status polls | bus reads | bus writes\n");
    printf("--- | --- | ---: | ---: | ---: | ---: | ---:\n");
    for (unsigned int i = 0; i < SPX_SIGN_TRAFFIC_COUNT; i++) {
        const spx_sign_traffic_t *traffic = &result->traffic[i];

        printf("%s | %s | %" PRIu64 " | %" PRIu64 " | %" PRIu64
               " | %" PRIu64 " | %" PRIu64 "\n",
               spx_sign_traffic_name((spx_sign_traffic_id_t)i),
               spx_sign_traffic_scope((spx_sign_traffic_id_t)i),
               traffic->descriptors,
               traffic->xif_instr,
               traffic->status_polls,
               traffic->bus_reads,
               traffic->bus_writes);
    }
}

static void print_sensitivity_table(const spx_sign_schedule_result_t *result)
{
    printf("\nMode | Baseline total cycles | Grouped total cycles | Speedup | "
           "baseline polls | grouped polls | baseline traffic | grouped traffic\n");
    printf("--- | ---: | ---: | ---: | ---: | ---: | ---: | ---:\n");
    for (unsigned int i = 0; i < SPX_SIGN_SENS_COUNT; i++) {
        const spx_sign_sensitivity_result_t *s = &result->sensitivity[i];

        printf("%s | %" PRIu64 " | %" PRIu64 " | %.2fx | %" PRIu64
               " | %" PRIu64 " | %" PRIu64 " | %" PRIu64 "\n",
               s->name,
               rounded_double(s->baseline_total_cycles),
               rounded_double(s->accelerated_total_cycles),
               s->speedup,
               rounded_double(s->baseline_status_polls),
               rounded_double(s->accelerated_status_polls),
               s->baseline_bus_reads + s->baseline_bus_writes,
               s->accelerated_bus_reads + s->accelerated_bus_writes);
    }
}

int main(void)
{
    spx_sign_schedule_result_t result;
    int failures = 0;

    spx_sign_schedule_model_compute(&result);

    failures += fail_if(SPX_SIGN_MODEL_WOTS_LEN != 35u,
                        "SPX_WOTS_LEN");
    failures += fail_if(SPX_SIGN_MODEL_WOTS_CHAIN_STEPS != 15u,
                        "WOTS chain steps");
    failures += fail_if(SPX_SIGN_MODEL_WOTS_GROUP_DESC_PER_PK != 9u,
                        "WOTS grouped descriptors per pk");
    failures += fail_if(SPX_SIGN_MODEL_WOTS_GROUP_DESC_CYCLES != 444u,
                        "WOTS grouped descriptor cycles");

    failures += fail_if(result.counts.wots_pk_count != 176u,
                        "sign WOTS pk count");
    failures += fail_if(result.counts.wots_chain_useful_steps != 92400u,
                        "WOTS useful chain steps");
    failures += fail_if(result.counts.wots_chain_baseline_descriptors != 23760u,
                        "WOTS baseline descriptors");
    failures += fail_if(result.counts.wots_chain_grouped_descriptors != 1584u,
                        "WOTS grouped descriptors");
    failures += fail_if(result.counts.fors_leaf_jobs != 2112u,
                        "FORS leaf jobs");
    failures += fail_if(result.counts.fors_internal_jobs != 2079u,
                        "FORS internal jobs");
    failures += fail_if(result.counts.merkle_internal_jobs != 154u,
                        "Merkle internal jobs");
    failures += fail_if(result.counts.prf_addr_calls != 8305u,
                        "PRF_ADDR calls");

    failures += fail_if(
        result.components[SPX_SIGN_COMPONENT_WOTS_CHAIN].baseline_cycles !=
            1354320u,
        "WOTS baseline cycles");
    failures += fail_if(
        result.components[SPX_SIGN_COMPONENT_WOTS_CHAIN].accelerated_cycles !=
            703296u,
        "WOTS grouped cycles");
    failures += fail_if(
        result.components[SPX_SIGN_COMPONENT_FORS_LEAF_INTERNAL]
                .baseline_cycles != 59736u,
        "FORS cycles");
    failures += fail_if(
        result.components[SPX_SIGN_COMPONENT_MERKLE_TREEHASH]
                .baseline_cycles != 2223u,
        "Merkle cycles");
    failures += fail_if(result.baseline_total_cycles != 1940223u,
                        "baseline total cycles");
    failures += fail_if(result.accelerated_total_cycles != 1289199u,
                        "accelerated total cycles");

    failures += fail_if(
        result.traffic[SPX_SIGN_TRAFFIC_THASHX4_ONLY].descriptors != 24847u,
        "THASHX4-only descriptors");
    failures += fail_if(
        result.traffic[SPX_SIGN_TRAFFIC_WOTS_GROUPED].descriptors != 2671u,
        "grouped descriptors");
    failures += fail_if(
        result.traffic[SPX_SIGN_TRAFFIC_THASHX4_ONLY].bus_reads != 374941u,
        "THASHX4-only bus reads");
    failures += fail_if(
        result.traffic[SPX_SIGN_TRAFFIC_WOTS_GROUPED].bus_reads != 42301u,
        "grouped bus reads");

    failures += fail_if(
        rounded_double(
            result.sensitivity[SPX_SIGN_SENS_ZERO_WAIT]
                .baseline_total_cycles) != result.baseline_total_cycles,
        "zero-wait sensitivity baseline");
    failures += fail_if(
        rounded_double(
            result.sensitivity[SPX_SIGN_SENS_ZERO_WAIT]
                .accelerated_total_cycles) != result.accelerated_total_cycles,
        "zero-wait sensitivity grouped");

    print_component_table(&result);
    print_traffic_table(&result);
    print_sensitivity_table(&result);

    printf("\nINFO sign model speedup=%.3fx saved_cycles=%" PRIu64
           " contribution=%.2f%%\n",
           result.total_speedup,
           result.wots_grouping_saved_cycles,
           result.wots_grouping_total_contribution_pct);

    if (failures != 0) {
        printf("FAIL sign_schedule_model failures=%d\n", failures);
        return 1;
    }

    printf("PASS sign_schedule_model\n");
    return 0;
}
