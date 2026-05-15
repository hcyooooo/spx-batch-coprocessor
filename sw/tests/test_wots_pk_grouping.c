#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "wots_pk_grouping_model.h"

#define SHAKE_CHAIN_ADDR_OFFSET 27u

static uint32_t prng_next(uint32_t *state)
{
    *state = *state * 1664525u + 1013904223u;
    return *state;
}

static void fill_bytes(uint8_t *out, uint32_t len, uint32_t *state)
{
    for (uint32_t i = 0; i < len; i++) {
        out[i] = (uint8_t)(prng_next(state) >> 24);
    }
}

static void fill_pub_seed(uint8_t pub_seed[SPX_WOTS_CHAINX4_N],
                          uint32_t seed)
{
    uint32_t state = seed;

    fill_bytes(pub_seed, SPX_WOTS_CHAINX4_N, &state);
}

static void fill_uniform_pk_chains(spx_wots_pk_chain_t *chains,
                                   uint32_t chain_count,
                                   uint32_t seed)
{
    uint32_t state = seed;

    for (uint32_t chain = 0; chain < chain_count; chain++) {
        fill_bytes(chains[chain].input, SPX_WOTS_CHAINX4_N, &state);
        fill_bytes(chains[chain].addr, SPX_WOTS_CHAINX4_ADDR_BYTES, &state);
        chains[chain].addr[SHAKE_CHAIN_ADDR_OFFSET] = (uint8_t)chain;
        chains[chain].addr[SPX_WOTS_CHAINX4_SHAKE_HASH_ADDR_OFFSET] = 0u;
        chains[chain].start_step = SPX_WOTS_PK_GROUPING_PK_START_STEP;
        chains[chain].num_steps = SPX_WOTS_PK_GROUPING_PK_NUM_STEPS;
    }
}

static int fail_if(int cond, const char *name)
{
    if (cond) {
        printf("FAIL %s\n", name);
        return 1;
    }

    return 0;
}

static int check_stats_67(void)
{
    spx_wots_pk_chain_t chains[SPX_WOTS_PK_GROUPING_STRESS_LEN_67];
    spx_wots_pk_grouping_desc_t descs[17];
    spx_wots_pk_grouping_stats_t stats;
    uint8_t pub_seed[SPX_WOTS_CHAINX4_N];
    int failures = 0;

    fill_pub_seed(pub_seed, 0x510067u);
    fill_uniform_pk_chains(chains, SPX_WOTS_PK_GROUPING_STRESS_LEN_67,
                           0x6700f00du);

    failures += fail_if(spx_wots_pk_group_chains(
                            chains, SPX_WOTS_PK_GROUPING_STRESS_LEN_67,
                            descs, 17u, &stats) != 0,
                        "group 67 chains");
    failures += fail_if(stats.descriptor_count != 17u,
                        "67 descriptor_count");
    failures += fail_if(stats.uniform_descriptor_count != 16u,
                        "67 uniform_descriptor_count");
    failures += fail_if(stats.mixed_descriptor_count != 1u,
                        "67 mixed_descriptor_count");
    failures += fail_if(stats.baseline_descriptor_count != 255u,
                        "67 baseline_descriptor_count");
    failures += fail_if(stats.useful_lane_ops != 1005u,
                        "67 useful_lane_ops");
    failures += fail_if(stats.physical_lane_ops != 1020u,
                        "67 physical_lane_ops");
    failures += fail_if(stats.baseline_cycles != 14535u,
                        "67 baseline_cycles");
    failures += fail_if(stats.estimated_cycles != 7548u,
                        "67 estimated_cycles");
    failures += fail_if(descs[16].op_type != SPX_WOTS_PK_GROUPING_DESC_MIXED,
                        "67 tail mixed descriptor");
    failures += fail_if(descs[16].lane_count != 3u,
                        "67 tail lane_count");
    failures += fail_if(spx_wots_pk_grouping_compare_scalar(
                            chains, SPX_WOTS_PK_GROUPING_STRESS_LEN_67,
                            pub_seed, &stats) != 0,
                        "67 grouped vs scalar outputs");

    if (failures == 0) {
        printf("INFO 67-chain pk grouping: descriptors=%u baseline_desc=%u "
               "cycles=%llu baseline_cycles=%llu speedup=%.2fx util=%.4f\n",
               stats.descriptor_count, stats.baseline_descriptor_count,
               (unsigned long long)stats.estimated_cycles,
               (unsigned long long)stats.baseline_cycles,
               stats.estimated_speedup, stats.lane_utilization);
    }

    return failures;
}

static int check_stats_current_len(void)
{
    spx_wots_pk_chain_t chains[SPX_WOTS_PK_GROUPING_CURRENT_SHAKE_128F_LEN];
    spx_wots_pk_grouping_stats_t stats;
    uint8_t pub_seed[SPX_WOTS_CHAINX4_N];
    int failures = 0;

    fill_pub_seed(pub_seed, 0x510035u);
    fill_uniform_pk_chains(chains,
                           SPX_WOTS_PK_GROUPING_CURRENT_SHAKE_128F_LEN,
                           0x3500f00du);

    failures += fail_if(spx_wots_pk_grouping_compare_scalar(
                            chains,
                            SPX_WOTS_PK_GROUPING_CURRENT_SHAKE_128F_LEN,
                            pub_seed, &stats) != 0,
                        "current-len grouped vs scalar outputs");
    failures += fail_if(stats.descriptor_count != 9u,
                        "current-len descriptor_count");
    failures += fail_if(stats.uniform_descriptor_count != 8u,
                        "current-len uniform_descriptor_count");
    failures += fail_if(stats.mixed_descriptor_count != 1u,
                        "current-len mixed_descriptor_count");
    failures += fail_if(stats.baseline_descriptor_count != 135u,
                        "current-len baseline_descriptor_count");
    failures += fail_if(stats.useful_lane_ops != 525u,
                        "current-len useful_lane_ops");
    failures += fail_if(stats.physical_lane_ops != 540u,
                        "current-len physical_lane_ops");
    failures += fail_if(stats.baseline_cycles != 7695u,
                        "current-len baseline_cycles");
    failures += fail_if(stats.estimated_cycles != 3996u,
                        "current-len estimated_cycles");

    if (failures == 0) {
        printf("INFO current SHAKE-128f len grouping: descriptors=%u "
               "baseline_desc=%u cycles=%llu baseline_cycles=%llu "
               "speedup=%.2fx util=%.4f\n",
               stats.descriptor_count, stats.baseline_descriptor_count,
               (unsigned long long)stats.estimated_cycles,
               (unsigned long long)stats.baseline_cycles,
               stats.estimated_speedup, stats.lane_utilization);
    }

    return failures;
}

static int check_tail_counts(void)
{
    spx_wots_pk_chain_t chains[3];
    uint8_t pub_seed[SPX_WOTS_CHAINX4_N];
    int failures = 0;

    fill_pub_seed(pub_seed, 0x510003u);
    fill_uniform_pk_chains(chains, 3u, 0x0300f00du);

    for (uint32_t count = 1; count <= 3u; count++) {
        spx_wots_pk_grouping_stats_t stats;

        failures += fail_if(spx_wots_pk_grouping_compare_scalar(
                                chains, count, pub_seed, &stats) != 0,
                            "tail grouped vs scalar outputs");
        failures += fail_if(stats.descriptor_count != 1u,
                            "tail descriptor_count");
        failures += fail_if(stats.uniform_descriptor_count != 0u,
                            "tail uniform_descriptor_count");
        failures += fail_if(stats.mixed_descriptor_count != 1u,
                            "tail mixed_descriptor_count");
        failures += fail_if(stats.useful_lane_ops !=
                            (uint64_t)count *
                            SPX_WOTS_PK_GROUPING_PK_NUM_STEPS,
                            "tail useful_lane_ops");
        failures += fail_if(stats.physical_lane_ops !=
                            SPX_WOTS_CHAINX4_LANES *
                            SPX_WOTS_PK_GROUPING_PK_NUM_STEPS,
                            "tail physical_lane_ops");
    }

    return failures;
}

static int check_mixed_windows(void)
{
    static const uint32_t starts[8] = {0u, 1u, 5u, 3u, 4u, 0u, 14u, 16u};
    static const uint32_t steps[8] = {15u, 14u, 0u, 7u, 4u, 1u, 1u, 0u};
    spx_wots_pk_chain_t chains[8];
    spx_wots_pk_grouping_desc_t descs[2];
    spx_wots_pk_grouping_stats_t stats;
    uint8_t pub_seed[SPX_WOTS_CHAINX4_N];
    int failures = 0;

    fill_pub_seed(pub_seed, 0x510008u);
    fill_uniform_pk_chains(chains, 8u, 0x0800f00du);
    for (uint32_t chain = 0; chain < 8u; chain++) {
        chains[chain].start_step = starts[chain];
        chains[chain].num_steps = steps[chain];
    }

    failures += fail_if(spx_wots_pk_group_chains(
                            chains, 8u, descs, 2u, &stats) != 0,
                        "mixed group chains");
    failures += fail_if(stats.descriptor_count != 2u,
                        "mixed descriptor_count");
    failures += fail_if(stats.uniform_descriptor_count != 0u,
                        "mixed uniform_descriptor_count");
    failures += fail_if(stats.mixed_descriptor_count != 2u,
                        "mixed mixed_descriptor_count");
    failures += fail_if(stats.baseline_descriptor_count != 19u,
                        "mixed baseline_descriptor_count");
    failures += fail_if(stats.useful_lane_ops != 42u,
                        "mixed useful_lane_ops");
    failures += fail_if(stats.physical_lane_ops != 76u,
                        "mixed physical_lane_ops");
    failures += fail_if(stats.baseline_cycles != 1083u,
                        "mixed baseline_cycles");
    failures += fail_if(stats.estimated_cycles != 580u,
                        "mixed estimated_cycles");
    failures += fail_if(descs[0].num_steps[2] != 0u,
                        "mixed zero-step lane");
    failures += fail_if(spx_wots_pk_grouping_compare_scalar(
                            chains, 8u, pub_seed, &stats) != 0,
                        "mixed grouped vs scalar outputs");

    return failures;
}

static int check_invalid_window(void)
{
    spx_wots_pk_chain_t chain;
    spx_wots_pk_grouping_stats_t stats;

    memset(&chain, 0, sizeof(chain));
    chain.start_step = 10u;
    chain.num_steps = 7u;

    return fail_if(spx_wots_pk_group_chains(&chain, 1u, NULL, 0u,
                                            &stats) == 0,
                   "invalid chain window rejected");
}

int main(void)
{
    int failures = 0;

    failures += check_stats_67();
    failures += check_stats_current_len();
    failures += check_tail_counts();
    failures += check_mixed_windows();
    failures += check_invalid_window();

    if (failures != 0) {
        printf("FAIL wots_pk_grouping_model failures=%d\n", failures);
        return 1;
    }

    printf("PASS wots_pk_grouping_model\n");
    return 0;
}
