#ifndef SPX_PROFILE_H
#define SPX_PROFILE_H

#include <stdint.h>
#include <stdio.h>

typedef enum {
    SPX_PROFILE_PHASE_KEYGEN = 0,
    SPX_PROFILE_PHASE_SIGN,
    SPX_PROFILE_PHASE_VERIFY,
    SPX_PROFILE_PHASE_COUNT
} spx_profile_phase_t;

typedef enum {
    SPX_PROFILE_FN_THASH = 0,
    SPX_PROFILE_FN_PRF_ADDR,
    SPX_PROFILE_FN_GEN_MESSAGE_RANDOM,
    SPX_PROFILE_FN_HASH_MESSAGE,
    SPX_PROFILE_FN_GEN_CHAIN,
    SPX_PROFILE_FN_WOTS_GEN_PK,
    SPX_PROFILE_FN_WOTS_PK_FROM_SIG,
    SPX_PROFILE_FN_FORS_GEN_LEAF,
    SPX_PROFILE_FN_FORS_SIGN,
    SPX_PROFILE_FN_FORS_PK_FROM_SIG,
    SPX_PROFILE_FN_FORS_TREEHASH,
    SPX_PROFILE_FN_TREEHASH,
    SPX_PROFILE_FN_COMPUTE_ROOT,
    SPX_PROFILE_FN_COUNT
} spx_profile_fn_t;

typedef enum {
    SPX_BATCH_REGION_NONE = 0,
    SPX_BATCH_REGION_WOTS_GEN_PK,
    SPX_BATCH_REGION_FORS_GEN_LEAF,
    SPX_BATCH_REGION_FORS_TREEHASH,
    SPX_BATCH_REGION_TREEHASH_INTERNAL,
    SPX_BATCH_REGION_VERIFY_GEN_CHAIN,
    SPX_BATCH_REGION_COUNT
} spx_batch_region_t;

#if defined(SPX_PROFILE) || defined(SPX_BATCH_PROFILE)
uint64_t spx_profile_now_ns(void);
int spx_profile_phase_begin(spx_profile_phase_t phase);
void spx_profile_phase_end(spx_profile_phase_t phase, int started);
void spx_profile_event_add(spx_profile_fn_t fn, uint64_t elapsed_ns);
void spx_profile_thash_record(unsigned int inblocks, const uint32_t addr[8]);
void spx_profile_prf_addr_record(const uint32_t addr[8]);
spx_batch_region_t spx_profile_batch_region_push(spx_batch_region_t region);
void spx_profile_batch_region_pop(spx_batch_region_t previous);
void spx_profile_reset_all(void);
void spx_profile_reset_phase(spx_profile_phase_t phase);
void spx_profile_print_phase(spx_profile_phase_t phase, FILE *out);
void spx_profile_print_batch(FILE *out);
#endif

#ifdef SPX_PROFILE
#define SPX_PROFILE_FN_BEGIN() \
    const uint64_t spx_profile_fn_start_ns = spx_profile_now_ns()
#define SPX_PROFILE_FN_END(fn_id) \
    spx_profile_event_add((fn_id), \
        spx_profile_now_ns() - spx_profile_fn_start_ns)
#define SPX_PROFILE_TIME(fn_id, ...) \
    do { \
        const uint64_t spx_profile_call_start_ns = spx_profile_now_ns(); \
        __VA_ARGS__; \
        spx_profile_event_add((fn_id), \
            spx_profile_now_ns() - spx_profile_call_start_ns); \
    } while (0)
#define SPX_PROFILE_PHASE_BEGIN(phase_id) \
    spx_profile_phase_begin((phase_id))
#define SPX_PROFILE_PHASE_END(phase_id, started) \
    spx_profile_phase_end((phase_id), (started))
#else
#define SPX_PROFILE_FN_BEGIN() ((void)0)
#define SPX_PROFILE_FN_END(fn_id) ((void)0)
#define SPX_PROFILE_TIME(fn_id, ...) \
    do { \
        __VA_ARGS__; \
    } while (0)
#define SPX_PROFILE_PHASE_BEGIN(phase_id) 0
#define SPX_PROFILE_PHASE_END(phase_id, started) ((void)(started))
#endif

#if defined(SPX_PROFILE) || defined(SPX_BATCH_PROFILE)
#define SPX_BATCH_THASH(inblocks, addr) \
    spx_profile_thash_record((inblocks), (addr))
#define SPX_BATCH_PRF_ADDR(addr) \
    spx_profile_prf_addr_record((addr))
#define SPX_BATCH_REGION_PUSH(region_id) \
    spx_profile_batch_region_push((region_id))
#define SPX_BATCH_REGION_POP(previous_region) \
    spx_profile_batch_region_pop((previous_region))
#else
#define SPX_BATCH_THASH(inblocks, addr) ((void)0)
#define SPX_BATCH_PRF_ADDR(addr) ((void)0)
#define SPX_BATCH_REGION_PUSH(region_id) SPX_BATCH_REGION_NONE
#define SPX_BATCH_REGION_POP(previous_region) ((void)(previous_region))
#endif

#endif
