#include <inttypes.h>
#include <stddef.h>
#include <string.h>

#include "batch_scheduler.h"

static spx_thashx4_batch_stats_t
    spx_thashx4_batch_stats[SPX_THASHX4_BATCH_REGION_COUNT];

static const char *const spx_thashx4_batch_region_names
    [SPX_THASHX4_BATCH_REGION_COUNT] = {
        "wots_gen_pk",
        "fors_leaf",
        "fors_internal"
};

void spx_thashx4_batch_reset(void)
{
    memset(spx_thashx4_batch_stats, 0, sizeof(spx_thashx4_batch_stats));
}

void spx_thashx4_batch_record_x4(spx_thashx4_batch_region_t region)
{
    if (region >= SPX_THASHX4_BATCH_REGION_COUNT) {
        return;
    }

    spx_thashx4_batch_stats[region].thashx4_calls++;
    spx_thashx4_batch_stats[region].replaced_scalar_thash += 4;
}

void spx_thashx4_batch_record_scalar(spx_thashx4_batch_region_t region,
                                     uint64_t calls)
{
    if (region >= SPX_THASHX4_BATCH_REGION_COUNT) {
        return;
    }

    spx_thashx4_batch_stats[region].scalar_fallback += calls;
}

void spx_thashx4_batch_get(spx_thashx4_batch_region_t region,
                           spx_thashx4_batch_stats_t *stats)
{
    if (stats == NULL) {
        return;
    }

    if (region >= SPX_THASHX4_BATCH_REGION_COUNT) {
        memset(stats, 0, sizeof(*stats));
        return;
    }

    *stats = spx_thashx4_batch_stats[region];
}

const char *spx_thashx4_batch_region_name(spx_thashx4_batch_region_t region)
{
    if (region >= SPX_THASHX4_BATCH_REGION_COUNT) {
        return "unknown";
    }

    return spx_thashx4_batch_region_names[region];
}

void spx_thashx4_batch_print(FILE *out)
{
    if (out == NULL) {
        return;
    }

    fprintf(out,
            "Region              thashx4_calls   scalar_fallback   replaced_scalar_thash\n");
    fprintf(out,
            "----------------------------------------------------------------------------\n");
    for (size_t i = 0; i < SPX_THASHX4_BATCH_REGION_COUNT; i++) {
        const spx_thashx4_batch_stats_t *stats = &spx_thashx4_batch_stats[i];
        fprintf(out, "%-19s %13" PRIu64 "   %15" PRIu64 "   %21" PRIu64 "\n",
                spx_thashx4_batch_region_names[i],
                stats->thashx4_calls,
                stats->scalar_fallback,
                stats->replaced_scalar_thash);
    }
}
