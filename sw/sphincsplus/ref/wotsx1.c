#include <stdint.h>
#include <string.h>

#include "utils.h"
#include "hash.h"
#include "thash.h"
#include "wots.h"
#include "wotsx1.h"
#include "address.h"
#include "params.h"
#include "profile.h"
#include "batch_scheduler.h"

#ifdef SPX_USE_THASHX4_BATCH
#include "thashx4_shake_simple.h"
#endif

/*
 * This generates a WOTS public key
 * It also generates the WOTS signature if leaf_info indicates
 * that we're signing with this WOTS key
 */
void wots_gen_leafx1_scalar_ref(unsigned char *dest,
                   const spx_ctx *ctx,
                   uint32_t leaf_idx, void *v_info) {
    SPX_PROFILE_FN_BEGIN();
    spx_batch_region_t spx_batch_previous_region =
        SPX_BATCH_REGION_PUSH(SPX_BATCH_REGION_WOTS_GEN_PK);
    struct leaf_info_x1 *info = v_info;
    uint32_t *leaf_addr = info->leaf_addr;
    uint32_t *pk_addr = info->pk_addr;
    unsigned int i, k;
    unsigned char pk_buffer[ SPX_WOTS_BYTES ];
    unsigned char *buffer;
    uint32_t wots_k_mask;

    if (leaf_idx == info->wots_sign_leaf) {
        /* We're traversing the leaf that's signing; generate the WOTS */
        /* signature */
        wots_k_mask = 0;
    } else {
        /* Nope, we're just generating pk's; turn off the signature logic */
        wots_k_mask = (uint32_t)~0;
    }

    set_keypair_addr( leaf_addr, leaf_idx );
    set_keypair_addr( pk_addr, leaf_idx );

    for (i = 0, buffer = pk_buffer; i < SPX_WOTS_LEN; i++, buffer += SPX_N) {
        uint32_t wots_k = info->wots_steps[i] | wots_k_mask; /* Set wots_k to */
            /* the step if we're generating a signature, ~0 if we're not */

        /* Start with the secret seed */
        set_chain_addr(leaf_addr, i);
        set_hash_addr(leaf_addr, 0);
        set_type(leaf_addr, SPX_ADDR_TYPE_WOTSPRF);

        prf_addr(buffer, ctx, leaf_addr);

        set_type(leaf_addr, SPX_ADDR_TYPE_WOTS);

        /* Iterate down the WOTS chain */
        for (k=0;; k++) {
            /* Check if this is the value that needs to be saved as a */
            /* part of the WOTS signature */
            if (k == wots_k) {
                memcpy( info->wots_sig + i * SPX_N, buffer, SPX_N );
            }

            /* Check if we hit the top of the chain */
            if (k == SPX_WOTS_W - 1) break;

            /* Iterate one step on the chain */
            set_hash_addr(leaf_addr, k);

            thash(buffer, buffer, 1, ctx, leaf_addr);
        }
    }

    /* Do the final thash to generate the public keys */
    thash(dest, pk_buffer, SPX_WOTS_LEN, ctx, pk_addr);
    SPX_BATCH_REGION_POP(spx_batch_previous_region);
    SPX_PROFILE_FN_END(SPX_PROFILE_FN_WOTS_GEN_PK);
}

#ifdef SPX_USE_THASHX4_BATCH
void wots_gen_leafx1_batch_ref(unsigned char *dest,
                   const spx_ctx *ctx,
                   uint32_t leaf_idx, void *v_info) {
    SPX_PROFILE_FN_BEGIN();
    spx_batch_region_t spx_batch_previous_region =
        SPX_BATCH_REGION_PUSH(SPX_BATCH_REGION_WOTS_GEN_PK);
    struct leaf_info_x1 *info = v_info;
    uint32_t *leaf_addr = info->leaf_addr;
    uint32_t *pk_addr = info->pk_addr;
    unsigned int i, j, k;
    unsigned char pk_buffer[SPX_WOTS_BYTES];
    uint32_t wots_k_mask;

    if (leaf_idx == info->wots_sign_leaf) {
        wots_k_mask = 0;
    } else {
        wots_k_mask = (uint32_t)~0;
    }

    set_keypair_addr(leaf_addr, leaf_idx);
    set_keypair_addr(pk_addr, leaf_idx);

    for (i = 0; i + 3 < SPX_WOTS_LEN; i += 4) {
        unsigned char *buf0 = pk_buffer + (i + 0) * SPX_N;
        unsigned char *buf1 = pk_buffer + (i + 1) * SPX_N;
        unsigned char *buf2 = pk_buffer + (i + 2) * SPX_N;
        unsigned char *buf3 = pk_buffer + (i + 3) * SPX_N;
        unsigned char *buf[4] = {buf0, buf1, buf2, buf3};
        uint32_t addr[4][8];
        uint32_t wots_k[4];

        for (j = 0; j < 4; j++) {
            wots_k[j] = info->wots_steps[i + j] | wots_k_mask;

            set_chain_addr(leaf_addr, i + j);
            set_hash_addr(leaf_addr, 0);
            set_type(leaf_addr, SPX_ADDR_TYPE_WOTSPRF);
            prf_addr(buf[j], ctx, leaf_addr);

            memcpy(addr[j], leaf_addr, sizeof(addr[j]));
            set_type(addr[j], SPX_ADDR_TYPE_WOTS);
        }

        for (k = 0;; k++) {
            for (j = 0; j < 4; j++) {
                if (k == wots_k[j] && info->wots_sig != NULL) {
                    memcpy(info->wots_sig + (i + j) * SPX_N,
                           buf[j], SPX_N);
                }
            }

            if (k == SPX_WOTS_W - 1) {
                break;
            }

            for (j = 0; j < 4; j++) {
                set_hash_addr(addr[j], k);
            }

            thashx4(buf0, buf1, buf2, buf3,
                    buf0, buf1, buf2, buf3,
                    1, ctx, addr[0], addr[1], addr[2], addr[3]);
            spx_thashx4_batch_record_x4(SPX_THASHX4_BATCH_WOTS_GEN_PK);
        }
    }

    for (; i < SPX_WOTS_LEN; i++) {
        unsigned char *buffer = pk_buffer + i * SPX_N;
        uint32_t wots_k = info->wots_steps[i] | wots_k_mask;

        set_chain_addr(leaf_addr, i);
        set_hash_addr(leaf_addr, 0);
        set_type(leaf_addr, SPX_ADDR_TYPE_WOTSPRF);
        prf_addr(buffer, ctx, leaf_addr);

        set_type(leaf_addr, SPX_ADDR_TYPE_WOTS);

        for (k = 0;; k++) {
            if (k == wots_k && info->wots_sig != NULL) {
                memcpy(info->wots_sig + i * SPX_N, buffer, SPX_N);
            }

            if (k == SPX_WOTS_W - 1) {
                break;
            }

            set_hash_addr(leaf_addr, k);
            thash(buffer, buffer, 1, ctx, leaf_addr);
            spx_thashx4_batch_record_scalar(SPX_THASHX4_BATCH_WOTS_GEN_PK, 1);
        }
    }

    thash(dest, pk_buffer, SPX_WOTS_LEN, ctx, pk_addr);
    SPX_BATCH_REGION_POP(spx_batch_previous_region);
    SPX_PROFILE_FN_END(SPX_PROFILE_FN_WOTS_GEN_PK);
}
#endif

void wots_gen_leafx1(unsigned char *dest,
                   const spx_ctx *ctx,
                   uint32_t leaf_idx, void *v_info) {
#ifdef SPX_USE_THASHX4_BATCH
    wots_gen_leafx1_batch_ref(dest, ctx, leaf_idx, v_info);
#else
    wots_gen_leafx1_scalar_ref(dest, ctx, leaf_idx, v_info);
#endif
}
