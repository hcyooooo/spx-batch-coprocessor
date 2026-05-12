#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../address.h"
#include "../api.h"
#include "../batch_scheduler.h"
#include "../hash.h"
#include "../params.h"
#include "../randombytes.h"
#include "../wotsx1.h"

#ifndef SPX_USE_THASHX4_BATCH
#error test_wots_batch requires SPX_USE_THASHX4_BATCH
#endif

#define WOTS_DIRECT_ROUNDS 100
#define SPX_MLEN 32
#define SPX_SIGNATURES 2

static uint64_t prng_next(uint64_t *state)
{
    uint64_t x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    return x;
}

static void fill_bytes(unsigned char *out, size_t outlen, uint64_t *seed)
{
    for (size_t i = 0; i < outlen; i++) {
        out[i] = (unsigned char)(prng_next(seed) & 0xffU);
    }
}

static void init_leaf_info(struct leaf_info_x1 *info,
                           unsigned char *sig,
                           uint32_t sign_leaf,
                           uint32_t *steps,
                           const uint32_t subtree_addr[8])
{
    memset(info, 0, sizeof(*info));
    info->wots_sig = sig;
    info->wots_sign_leaf = sign_leaf;
    info->wots_steps = steps;

    copy_subtree_addr(info->leaf_addr, subtree_addr);
    copy_subtree_addr(info->pk_addr, subtree_addr);
    set_type(info->leaf_addr, SPX_ADDR_TYPE_WOTS);
    set_type(info->pk_addr, SPX_ADDR_TYPE_WOTSPK);
}

static void print_stats_with_correctness(const char *correctness)
{
    printf("\n");
    printf("Region              thashx4_calls   scalar_fallback   replaced_scalar_thash   correctness\n");
    printf("-----------------------------------------------------------------------------------------\n");

    for (int i = 0; i < SPX_THASHX4_BATCH_REGION_COUNT; i++) {
        spx_thashx4_batch_stats_t stats;
        const spx_thashx4_batch_region_t region =
            (spx_thashx4_batch_region_t)i;

        spx_thashx4_batch_get(region, &stats);
        printf("%-19s %13" PRIu64 "   %15" PRIu64 "   %21" PRIu64 "   %s\n",
               spx_thashx4_batch_region_name(region),
               stats.thashx4_calls,
               stats.scalar_fallback,
               stats.replaced_scalar_thash,
               correctness);
    }
}

static int test_wots_scalar_vs_batch(uint64_t *seed)
{
    for (size_t round = 0; round < WOTS_DIRECT_ROUNDS; round++) {
        spx_ctx ctx;
        uint32_t subtree_addr[8] = {0};
        uint32_t steps[SPX_WOTS_LEN];
        struct leaf_info_x1 scalar_info;
        struct leaf_info_x1 batch_info;
        unsigned char scalar_pk[SPX_N];
        unsigned char batch_pk[SPX_N];
        unsigned char scalar_sig[SPX_WOTS_BYTES];
        unsigned char batch_sig[SPX_WOTS_BYTES];
        const uint32_t leaf_idx = (uint32_t)(prng_next(seed) & 0x7U);

        fill_bytes(ctx.pub_seed, sizeof(ctx.pub_seed), seed);
        fill_bytes(ctx.sk_seed, sizeof(ctx.sk_seed), seed);
        initialize_hash_function(&ctx);

        set_layer_addr(subtree_addr, (uint32_t)(round % SPX_D));
        set_tree_addr(subtree_addr, prng_next(seed));

        for (size_t i = 0; i < SPX_WOTS_LEN; i++) {
            steps[i] = (uint32_t)(prng_next(seed) % SPX_WOTS_W);
        }

        init_leaf_info(&scalar_info, scalar_sig, leaf_idx, steps, subtree_addr);
        init_leaf_info(&batch_info, batch_sig, leaf_idx, steps, subtree_addr);

        wots_gen_leafx1_scalar_ref(scalar_pk, &ctx, leaf_idx, &scalar_info);
        wots_gen_leafx1_batch_ref(batch_pk, &ctx, leaf_idx, &batch_info);

        if (memcmp(scalar_pk, batch_pk, SPX_N) != 0) {
            printf("FAIL WOTS batch pk mismatch at round %zu\n", round);
            return -1;
        }

        if (memcmp(scalar_sig, batch_sig, SPX_WOTS_BYTES) != 0) {
            printf("FAIL WOTS batch signature mismatch at round %zu\n", round);
            return -1;
        }
    }

    printf("PASS WOTS scalar-vs-batch pk/signature comparison (%u rounds)\n",
           WOTS_DIRECT_ROUNDS);
    return 0;
}

static int test_full_spx_batch(uint64_t *seed)
{
    unsigned char pk[SPX_PK_BYTES];
    unsigned char sk[SPX_SK_BYTES];
    unsigned char m[SPX_MLEN];
    unsigned char sm[SPX_BYTES + SPX_MLEN];
    unsigned char mout[SPX_BYTES + SPX_MLEN];
    unsigned long long smlen;
    unsigned long long mlen;

    if (crypto_sign_keypair(pk, sk)) {
        printf("FAIL crypto_sign_keypair\n");
        return -1;
    }

    for (size_t i = 0; i < SPX_SIGNATURES; i++) {
        fill_bytes(m, sizeof(m), seed);

        if (crypto_sign(sm, &smlen, m, sizeof(m), sk)) {
            printf("FAIL crypto_sign at signature %zu\n", i);
            return -1;
        }
        if (smlen != SPX_BYTES + SPX_MLEN) {
            printf("FAIL signature length at signature %zu\n", i);
            return -1;
        }
        if (crypto_sign_open(mout, &mlen, sm, smlen, pk)) {
            printf("FAIL crypto_sign_open at signature %zu\n", i);
            return -1;
        }
        if (mlen != SPX_MLEN || memcmp(m, mout, SPX_MLEN) != 0) {
            printf("FAIL recovered message at signature %zu\n", i);
            return -1;
        }
    }

    printf("PASS full keygen/sign/verify with thashx4 batch (%u signatures)\n",
           SPX_SIGNATURES);
    return 0;
}

int main(void)
{
    uint64_t seed = 0x5867a3d92f10c4beULL;

    setbuf(stdout, NULL);

    spx_thashx4_batch_reset();
    if (test_wots_scalar_vs_batch(&seed)) {
        print_stats_with_correctness("FAIL");
        return 1;
    }

    spx_thashx4_batch_reset();
    if (test_full_spx_batch(&seed)) {
        print_stats_with_correctness("FAIL");
        return 1;
    }

    print_stats_with_correctness("PASS");
    return 0;
}
