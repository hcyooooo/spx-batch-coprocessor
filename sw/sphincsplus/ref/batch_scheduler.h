#ifndef SPX_BATCH_SCHEDULER_H
#define SPX_BATCH_SCHEDULER_H

#include <stdint.h>
#include <stdio.h>

#include "params.h"

typedef enum {
    SPX_THASHX4_BATCH_WOTS_GEN_PK = 0,
    SPX_THASHX4_BATCH_FORS_LEAF,
    SPX_THASHX4_BATCH_FORS_INTERNAL,
    SPX_THASHX4_BATCH_REGION_COUNT
} spx_thashx4_batch_region_t;

typedef struct {
    uint64_t thashx4_calls;
    uint64_t scalar_fallback;
    uint64_t replaced_scalar_thash;
} spx_thashx4_batch_stats_t;

#define spx_thashx4_batch_reset SPX_NAMESPACE(spx_thashx4_batch_reset)
void spx_thashx4_batch_reset(void);

#define spx_thashx4_batch_record_x4 SPX_NAMESPACE(spx_thashx4_batch_record_x4)
void spx_thashx4_batch_record_x4(spx_thashx4_batch_region_t region);

#define spx_thashx4_batch_record_scalar SPX_NAMESPACE(spx_thashx4_batch_record_scalar)
void spx_thashx4_batch_record_scalar(spx_thashx4_batch_region_t region,
                                     uint64_t calls);

#define spx_thashx4_batch_get SPX_NAMESPACE(spx_thashx4_batch_get)
void spx_thashx4_batch_get(spx_thashx4_batch_region_t region,
                           spx_thashx4_batch_stats_t *stats);

#define spx_thashx4_batch_region_name SPX_NAMESPACE(spx_thashx4_batch_region_name)
const char *spx_thashx4_batch_region_name(spx_thashx4_batch_region_t region);

#define spx_thashx4_batch_print SPX_NAMESPACE(spx_thashx4_batch_print)
void spx_thashx4_batch_print(FILE *out);

#endif
