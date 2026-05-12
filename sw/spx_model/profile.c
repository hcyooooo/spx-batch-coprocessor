#define _POSIX_C_SOURCE 199309L

#include "profile.h"

#if defined(SPX_PROFILE) || defined(SPX_BATCH_PROFILE)

#include <inttypes.h>
#include <string.h>
#include <time.h>

#include "address.h"
#include "params.h"

struct spx_profile_record {
    uint64_t calls;
    uint64_t time_ns;
};

typedef enum {
    SPX_BATCH_THASH_WOTS_CHAIN = 0,
    SPX_BATCH_THASH_WOTS_PK_COMPRESSION,
    SPX_BATCH_THASH_FORS_LEAF,
    SPX_BATCH_THASH_FORS_INTERNAL,
    SPX_BATCH_THASH_MERKLE_INTERNAL,
    SPX_BATCH_THASH_OTHER,
    SPX_BATCH_THASH_TYPE_COUNT
} spx_batch_thash_type_t;

typedef enum {
    SPX_BATCH_BLOCKS_1 = 0,
    SPX_BATCH_BLOCKS_2,
    SPX_BATCH_BLOCKS_GT2,
    SPX_BATCH_BLOCKS_COUNT
} spx_batch_block_bucket_t;

typedef enum {
    SPX_BATCH_JOB_PRF_ADDR = 0,
    SPX_BATCH_JOB_THASH_WOTS_CHAIN_1,
    SPX_BATCH_JOB_THASH_WOTS_CHAIN_2,
    SPX_BATCH_JOB_THASH_WOTS_CHAIN_GT2,
    SPX_BATCH_JOB_THASH_WOTS_PK_COMPRESSION_1,
    SPX_BATCH_JOB_THASH_WOTS_PK_COMPRESSION_2,
    SPX_BATCH_JOB_THASH_WOTS_PK_COMPRESSION_GT2,
    SPX_BATCH_JOB_THASH_FORS_LEAF_1,
    SPX_BATCH_JOB_THASH_FORS_LEAF_2,
    SPX_BATCH_JOB_THASH_FORS_LEAF_GT2,
    SPX_BATCH_JOB_THASH_FORS_INTERNAL_1,
    SPX_BATCH_JOB_THASH_FORS_INTERNAL_2,
    SPX_BATCH_JOB_THASH_FORS_INTERNAL_GT2,
    SPX_BATCH_JOB_THASH_MERKLE_INTERNAL_1,
    SPX_BATCH_JOB_THASH_MERKLE_INTERNAL_2,
    SPX_BATCH_JOB_THASH_MERKLE_INTERNAL_GT2,
    SPX_BATCH_JOB_THASH_OTHER_1,
    SPX_BATCH_JOB_THASH_OTHER_2,
    SPX_BATCH_JOB_THASH_OTHER_GT2,
    SPX_BATCH_JOB_COUNT
} spx_batch_job_t;

struct spx_batch_histogram {
    uint64_t x4;
    uint64_t x3;
    uint64_t x2;
    uint64_t x1;
    uint64_t total_jobs;
    uint64_t useful_lanes;
    uint64_t allocated_lanes;
};

static struct spx_profile_record spx_profile_records[SPX_PROFILE_PHASE_COUNT]
                                                    [SPX_PROFILE_FN_COUNT];
static uint64_t spx_profile_phase_time_ns[SPX_PROFILE_PHASE_COUNT];
static uint64_t spx_profile_phase_start_ns;
static spx_profile_phase_t spx_profile_current_phase =
    SPX_PROFILE_PHASE_COUNT;
static uint64_t spx_batch_thash_counts[SPX_BATCH_THASH_TYPE_COUNT]
                                      [SPX_BATCH_BLOCKS_COUNT];
static uint64_t spx_batch_region_jobs[SPX_BATCH_REGION_COUNT]
                                     [SPX_BATCH_JOB_COUNT];
static spx_batch_region_t spx_batch_current_region = SPX_BATCH_REGION_NONE;

static const char *const spx_profile_phase_names[SPX_PROFILE_PHASE_COUNT] = {
    "keygen",
    "sign",
    "verify"
};

static const char *const spx_profile_fn_names[SPX_PROFILE_FN_COUNT] = {
    "thash",
    "prf_addr",
    "gen_message_random",
    "hash_message",
    "gen_chain",
    "wots_gen_pk",
    "wots_pk_from_sig",
    "fors_gen_leaf",
    "fors_sign",
    "fors_pk_from_sig",
    "fors_treehash",
    "treehash",
    "compute_root"
};

static const char *const spx_batch_thash_type_names[SPX_BATCH_THASH_TYPE_COUNT] = {
    "WOTS chain thash",
    "WOTS pk compression thash",
    "FORS leaf thash",
    "FORS internal node thash",
    "Merkle internal node thash",
    "other thash"
};

static const char *const spx_batch_region_names[SPX_BATCH_REGION_COUNT] = {
    "none",
    "wots_gen_pk",
    "fors_gen_leaf",
    "fors_treehash",
    "merkle_internal",
    "verify_gen_chain"
};

static spx_batch_block_bucket_t spx_batch_block_bucket(unsigned int inblocks)
{
    if (inblocks == 1) {
        return SPX_BATCH_BLOCKS_1;
    }
    if (inblocks == 2) {
        return SPX_BATCH_BLOCKS_2;
    }
    return SPX_BATCH_BLOCKS_GT2;
}

static spx_batch_thash_type_t spx_batch_thash_type(const uint32_t addr[8],
                                                   unsigned int inblocks)
{
    const unsigned int addr_type =
        (unsigned int)((const unsigned char *)addr)[SPX_OFFSET_TYPE];

    switch (addr_type) {
    case SPX_ADDR_TYPE_WOTS:
        return SPX_BATCH_THASH_WOTS_CHAIN;
    case SPX_ADDR_TYPE_WOTSPK:
        return SPX_BATCH_THASH_WOTS_PK_COMPRESSION;
    case SPX_ADDR_TYPE_FORSTREE:
        if (inblocks == 1) {
            return SPX_BATCH_THASH_FORS_LEAF;
        }
        if (inblocks == 2) {
            return SPX_BATCH_THASH_FORS_INTERNAL;
        }
        return SPX_BATCH_THASH_OTHER;
    case SPX_ADDR_TYPE_HASHTREE:
        if (inblocks == 2) {
            return SPX_BATCH_THASH_MERKLE_INTERNAL;
        }
        return SPX_BATCH_THASH_OTHER;
    default:
        return SPX_BATCH_THASH_OTHER;
    }
}

static spx_batch_job_t spx_batch_thash_job(spx_batch_thash_type_t type,
                                           spx_batch_block_bucket_t bucket)
{
    return (spx_batch_job_t)(SPX_BATCH_JOB_THASH_WOTS_CHAIN_1 +
                            (unsigned int)type * SPX_BATCH_BLOCKS_COUNT +
                            (unsigned int)bucket);
}

static void spx_batch_histogram_add_jobs(struct spx_batch_histogram *hist,
                                         uint64_t jobs)
{
    const uint64_t full = jobs / 4;
    const uint64_t remainder = jobs & 3ULL;

    hist->x4 += full;
    switch (remainder) {
    case 3:
        hist->x3++;
        break;
    case 2:
        hist->x2++;
        break;
    case 1:
        hist->x1++;
        break;
    default:
        break;
    }

    hist->total_jobs += jobs;
    hist->useful_lanes += jobs;
    hist->allocated_lanes += full * 4ULL + (remainder == 0 ? 0ULL : 4ULL);
}

uint64_t spx_profile_now_ns(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

int spx_profile_phase_begin(spx_profile_phase_t phase)
{
    if (phase >= SPX_PROFILE_PHASE_COUNT ||
            spx_profile_current_phase != SPX_PROFILE_PHASE_COUNT) {
        return 0;
    }

    spx_profile_current_phase = phase;
    spx_profile_phase_start_ns = spx_profile_now_ns();
    return 1;
}

void spx_profile_phase_end(spx_profile_phase_t phase, int started)
{
    if (!started || phase != spx_profile_current_phase) {
        return;
    }

    spx_profile_phase_time_ns[phase] +=
        spx_profile_now_ns() - spx_profile_phase_start_ns;
    spx_profile_current_phase = SPX_PROFILE_PHASE_COUNT;
}

void spx_profile_event_add(spx_profile_fn_t fn, uint64_t elapsed_ns)
{
    struct spx_profile_record *record;

    if (fn >= SPX_PROFILE_FN_COUNT ||
            spx_profile_current_phase >= SPX_PROFILE_PHASE_COUNT) {
        return;
    }

    record = &spx_profile_records[spx_profile_current_phase][fn];
    record->calls++;
    record->time_ns += elapsed_ns;
}

void spx_profile_thash_record(unsigned int inblocks, const uint32_t addr[8])
{
    const spx_batch_block_bucket_t bucket = spx_batch_block_bucket(inblocks);
    const spx_batch_thash_type_t type = spx_batch_thash_type(addr, inblocks);

    spx_batch_thash_counts[type][bucket]++;

    if (spx_batch_current_region != SPX_BATCH_REGION_NONE &&
            spx_batch_current_region < SPX_BATCH_REGION_COUNT) {
        spx_batch_region_jobs[spx_batch_current_region]
                             [spx_batch_thash_job(type, bucket)]++;
    }
}

void spx_profile_prf_addr_record(const uint32_t addr[8])
{
    (void)addr;

    if (spx_batch_current_region != SPX_BATCH_REGION_NONE &&
            spx_batch_current_region < SPX_BATCH_REGION_COUNT) {
        spx_batch_region_jobs[spx_batch_current_region]
                             [SPX_BATCH_JOB_PRF_ADDR]++;
    }
}

spx_batch_region_t spx_profile_batch_region_push(spx_batch_region_t region)
{
    const spx_batch_region_t previous = spx_batch_current_region;

    if (region < SPX_BATCH_REGION_COUNT) {
        spx_batch_current_region = region;
    }
    return previous;
}

void spx_profile_batch_region_pop(spx_batch_region_t previous)
{
    if (previous < SPX_BATCH_REGION_COUNT) {
        spx_batch_current_region = previous;
    }
}

void spx_profile_reset_all(void)
{
    memset(spx_profile_records, 0, sizeof(spx_profile_records));
    memset(spx_profile_phase_time_ns, 0, sizeof(spx_profile_phase_time_ns));
    memset(spx_batch_thash_counts, 0, sizeof(spx_batch_thash_counts));
    memset(spx_batch_region_jobs, 0, sizeof(spx_batch_region_jobs));
    spx_profile_current_phase = SPX_PROFILE_PHASE_COUNT;
    spx_profile_phase_start_ns = 0;
    spx_batch_current_region = SPX_BATCH_REGION_NONE;
}

void spx_profile_reset_phase(spx_profile_phase_t phase)
{
    if (phase >= SPX_PROFILE_PHASE_COUNT) {
        return;
    }

    memset(spx_profile_records[phase], 0, sizeof(spx_profile_records[phase]));
    spx_profile_phase_time_ns[phase] = 0;
    if (spx_profile_current_phase == phase) {
        spx_profile_phase_start_ns = spx_profile_now_ns();
    }
}

void spx_profile_print_phase(spx_profile_phase_t phase, FILE *out)
{
    uint64_t total_ns;
    unsigned int i;

    if (phase >= SPX_PROFILE_PHASE_COUNT || out == NULL) {
        return;
    }

    total_ns = spx_profile_phase_time_ns[phase];

    fprintf(out, "\n%s profile (total: %" PRIu64 " ns, %.3f ms)\n",
            spx_profile_phase_names[phase],
            total_ns,
            (double)total_ns / 1000000.0);
    fprintf(out, "%-22s %12s %16s %10s\n",
            "Function", "Calls", "Time(ns)", "Percent");
    fprintf(out, "---------------------------------------------------------------\n");

    for (i = 0; i < SPX_PROFILE_FN_COUNT; i++) {
        const struct spx_profile_record *record =
            &spx_profile_records[phase][i];
        const double percent = total_ns == 0 ? 0.0 :
            ((double)record->time_ns * 100.0) / (double)total_ns;

        fprintf(out, "%-22s %12" PRIu64 " %16" PRIu64 " %9.2f%%\n",
                spx_profile_fn_names[i],
                record->calls,
                record->time_ns,
                percent);
    }
}

void spx_profile_print_batch(FILE *out)
{
    unsigned int i;

    if (out == NULL) {
        return;
    }

    fprintf(out, "\nthash type and input-block distribution\n");
    fprintf(out, "%-34s %12s %12s %12s %12s\n",
            "Type", "inblocks=1", "inblocks=2", "inblocks>2", "total");
    fprintf(out, "--------------------------------------------------------------------------------\n");
    for (i = 0; i < SPX_BATCH_THASH_TYPE_COUNT; i++) {
        const uint64_t in1 = spx_batch_thash_counts[i][SPX_BATCH_BLOCKS_1];
        const uint64_t in2 = spx_batch_thash_counts[i][SPX_BATCH_BLOCKS_2];
        const uint64_t gt2 = spx_batch_thash_counts[i][SPX_BATCH_BLOCKS_GT2];

        fprintf(out, "%-34s %12" PRIu64 " %12" PRIu64
                " %12" PRIu64 " %12" PRIu64 "\n",
                spx_batch_thash_type_names[i], in1, in2, gt2,
                in1 + in2 + gt2);
    }

    fprintf(out, "\nx4 batch lane occupancy by region\n");
    fprintf(out, "%-22s %10s %6s %6s %6s %12s %12s\n",
            "Region", "full_x4", "x3", "x2", "x1", "total_jobs",
            "utilization");
    fprintf(out, "-------------------------------------------------------------------------------\n");

    for (i = SPX_BATCH_REGION_WOTS_GEN_PK;
            i < SPX_BATCH_REGION_COUNT; i++) {
        struct spx_batch_histogram hist = {0};
        unsigned int job;
        double utilization;

        for (job = 0; job < SPX_BATCH_JOB_COUNT; job++) {
            spx_batch_histogram_add_jobs(
                &hist,
                spx_batch_region_jobs[i][job]);
        }

        utilization = hist.allocated_lanes == 0 ? 0.0 :
            (double)hist.useful_lanes * 100.0 /
            (double)hist.allocated_lanes;

        fprintf(out, "%-22s %10" PRIu64 " %6" PRIu64 " %6" PRIu64
                " %6" PRIu64 " %12" PRIu64 " %11.2f%%\n",
                spx_batch_region_names[i],
                hist.x4,
                hist.x3,
                hist.x2,
                hist.x1,
                hist.total_jobs,
                utilization);
    }
}

#else
enum { spx_profile_disabled_translation_unit = 0 };
#endif
