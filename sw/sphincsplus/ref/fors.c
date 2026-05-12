#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "fors.h"
#include "utils.h"
#include "utilsx1.h"
#include "hash.h"
#include "thash.h"
#include "address.h"
#include "profile.h"
#include "batch_scheduler.h"

#ifdef SPX_USE_THASHX4_BATCH
#include "thashx4_shake_simple.h"
#endif

static void fors_gen_sk(unsigned char *sk, const spx_ctx *ctx,
                        uint32_t fors_leaf_addr[8])
{
    prf_addr(sk, ctx, fors_leaf_addr);
}

static void fors_sk_to_leaf(unsigned char *leaf, const unsigned char *sk,
                            const spx_ctx *ctx,
                            uint32_t fors_leaf_addr[8])
{
    thash(leaf, sk, 1, ctx, fors_leaf_addr);
}

#ifndef SPX_USE_THASHX4_BATCH
struct fors_gen_leaf_info {
    uint32_t leaf_addrx[8];
};

static void fors_gen_leafx1(unsigned char *leaf,
                            const spx_ctx *ctx,
                            uint32_t addr_idx, void *info)
{
    SPX_PROFILE_FN_BEGIN();
    spx_batch_region_t spx_batch_previous_region =
        SPX_BATCH_REGION_PUSH(SPX_BATCH_REGION_FORS_GEN_LEAF);
    struct fors_gen_leaf_info *fors_info = info;
    uint32_t *fors_leaf_addr = fors_info->leaf_addrx;

    /* Only set the parts that the caller doesn't set */
    set_tree_index(fors_leaf_addr, addr_idx);
    set_type(fors_leaf_addr, SPX_ADDR_TYPE_FORSPRF);
    fors_gen_sk(leaf, ctx, fors_leaf_addr);

    set_type(fors_leaf_addr, SPX_ADDR_TYPE_FORSTREE);
    fors_sk_to_leaf(leaf, leaf,
                    ctx, fors_leaf_addr);
    SPX_BATCH_REGION_POP(spx_batch_previous_region);
    SPX_PROFILE_FN_END(SPX_PROFILE_FN_FORS_GEN_LEAF);
}
#endif

/**
 * Interprets m as SPX_FORS_HEIGHT-bit unsigned integers.
 * Assumes m contains at least SPX_FORS_HEIGHT * SPX_FORS_TREES bits.
 * Assumes indices has space for SPX_FORS_TREES integers.
 */
static void message_to_indices(uint32_t *indices, const unsigned char *m)
{
    unsigned int i, j;
    unsigned int offset = 0;

    for (i = 0; i < SPX_FORS_TREES; i++) {
        indices[i] = 0;
        for (j = 0; j < SPX_FORS_HEIGHT; j++) {
            indices[i] ^= ((m[offset >> 3] >> (offset & 0x7)) & 1u) << j;
            offset++;
        }
    }
}

#ifdef SPX_USE_THASHX4_BATCH
static void fors_gen_leaf_batch(unsigned char *leaf,
                                unsigned int count,
                                uint32_t first_idx,
                                const spx_ctx *ctx,
                                const uint32_t tree_addr[8])
{
    unsigned int i;
    uint32_t addr[4][8];
    unsigned char sk[4][SPX_N];

    for (i = 0; i < count; i++) {
        memset(addr[i], 0, sizeof(addr[i]));
        copy_keypair_addr(addr[i], tree_addr);
        set_tree_height(addr[i], 0);
        set_tree_index(addr[i], first_idx + i);
        set_type(addr[i], SPX_ADDR_TYPE_FORSPRF);
        fors_gen_sk(sk[i], ctx, addr[i]);
        set_type(addr[i], SPX_ADDR_TYPE_FORSTREE);
    }

    if (count == 4) {
        thashx4(leaf + 0 * SPX_N,
                leaf + 1 * SPX_N,
                leaf + 2 * SPX_N,
                leaf + 3 * SPX_N,
                sk[0], sk[1], sk[2], sk[3],
                1, ctx, addr[0], addr[1], addr[2], addr[3]);
        spx_thashx4_batch_record_x4(SPX_THASHX4_BATCH_FORS_LEAF);
    } else {
        for (i = 0; i < count; i++) {
            thash(leaf + i * SPX_N, sk[i], 1, ctx, addr[i]);
        }
        spx_thashx4_batch_record_scalar(SPX_THASHX4_BATCH_FORS_LEAF, count);
    }
}

static void fors_treehashx4_sign(unsigned char *root,
                                 unsigned char *auth_path,
                                 const spx_ctx *ctx,
                                 uint32_t leaf_idx,
                                 uint32_t idx_offset,
                                 uint32_t tree_height,
                                 const uint32_t tree_addr[8])
{
    const uint32_t leaf_count = (uint32_t)1 << tree_height;
    SPX_VLA(unsigned char, nodes_a, leaf_count * SPX_N);
    SPX_VLA(unsigned char, nodes_b, leaf_count * SPX_N);
    unsigned char *current = nodes_a;
    unsigned char *next = nodes_b;
    uint32_t idx;

    for (idx = 0; idx + 3 < leaf_count; idx += 4) {
        fors_gen_leaf_batch(current + idx * SPX_N, 4,
                            idx_offset + idx, ctx, tree_addr);
    }
    if (idx < leaf_count) {
        fors_gen_leaf_batch(current + idx * SPX_N, leaf_count - idx,
                            idx_offset + idx, ctx, tree_addr);
    }

    for (uint32_t h = 0; h < tree_height; h++) {
        const uint32_t node_count = (uint32_t)1 << (tree_height - h);
        const uint32_t parent_count = node_count >> 1;
        const uint32_t auth_idx = (leaf_idx >> h) ^ 1U;
        uint32_t parent;

        memcpy(auth_path + h * SPX_N, current + auth_idx * SPX_N, SPX_N);

        for (parent = 0; parent + 3 < parent_count; parent += 4) {
            uint32_t addr[4][8];

            for (uint32_t lane = 0; lane < 4; lane++) {
                memset(addr[lane], 0, sizeof(addr[lane]));
                copy_keypair_addr(addr[lane], tree_addr);
                set_type(addr[lane], SPX_ADDR_TYPE_FORSTREE);
                set_tree_height(addr[lane], h + 1);
                set_tree_index(addr[lane],
                               (idx_offset >> (h + 1)) + parent + lane);
            }

            thashx4(next + (parent + 0) * SPX_N,
                    next + (parent + 1) * SPX_N,
                    next + (parent + 2) * SPX_N,
                    next + (parent + 3) * SPX_N,
                    current + (2 * (parent + 0)) * SPX_N,
                    current + (2 * (parent + 1)) * SPX_N,
                    current + (2 * (parent + 2)) * SPX_N,
                    current + (2 * (parent + 3)) * SPX_N,
                    2, ctx, addr[0], addr[1], addr[2], addr[3]);
            spx_thashx4_batch_record_x4(SPX_THASHX4_BATCH_FORS_INTERNAL);
        }

        for (; parent < parent_count; parent++) {
            uint32_t addr[8];

            memset(addr, 0, sizeof(addr));
            copy_keypair_addr(addr, tree_addr);
            set_type(addr, SPX_ADDR_TYPE_FORSTREE);
            set_tree_height(addr, h + 1);
            set_tree_index(addr, (idx_offset >> (h + 1)) + parent);
            thash(next + parent * SPX_N,
                  current + (2 * parent) * SPX_N,
                  2, ctx, addr);
            spx_thashx4_batch_record_scalar(SPX_THASHX4_BATCH_FORS_INTERNAL,
                                            1);
        }

        {
            unsigned char *tmp = current;
            current = next;
            next = tmp;
        }
    }

    memcpy(root, current, SPX_N);
}
#endif

/**
 * Signs a message m, deriving the secret key from sk_seed and the FTS address.
 * Assumes m contains at least SPX_FORS_HEIGHT * SPX_FORS_TREES bits.
 */
void fors_sign(unsigned char *sig, unsigned char *pk,
               const unsigned char *m,
               const spx_ctx *ctx,
               const uint32_t fors_addr[8])
{
    SPX_PROFILE_FN_BEGIN();
    uint32_t indices[SPX_FORS_TREES];
    unsigned char roots[SPX_FORS_TREES * SPX_N];
    uint32_t fors_tree_addr[8] = {0};
    uint32_t fors_pk_addr[8] = {0};
    uint32_t idx_offset;
    unsigned int i;
#ifndef SPX_USE_THASHX4_BATCH
    struct fors_gen_leaf_info fors_info = {0};
    uint32_t *fors_leaf_addr = fors_info.leaf_addrx;
#endif

    copy_keypair_addr(fors_tree_addr, fors_addr);
#ifndef SPX_USE_THASHX4_BATCH
    copy_keypair_addr(fors_leaf_addr, fors_addr);
#endif

    copy_keypair_addr(fors_pk_addr, fors_addr);
    set_type(fors_pk_addr, SPX_ADDR_TYPE_FORSPK);

    message_to_indices(indices, m);

    for (i = 0; i < SPX_FORS_TREES; i++) {
        idx_offset = i * (1 << SPX_FORS_HEIGHT);

        set_tree_height(fors_tree_addr, 0);
        set_tree_index(fors_tree_addr, indices[i] + idx_offset);
        set_type(fors_tree_addr, SPX_ADDR_TYPE_FORSPRF);

        /* Include the secret key part that produces the selected leaf node. */
        fors_gen_sk(sig, ctx, fors_tree_addr);
        set_type(fors_tree_addr, SPX_ADDR_TYPE_FORSTREE);
        sig += SPX_N;

        /* Compute the authentication path for this leaf node. */
        spx_batch_region_t spx_batch_previous_region =
            SPX_BATCH_REGION_PUSH(SPX_BATCH_REGION_FORS_TREEHASH);
#ifdef SPX_USE_THASHX4_BATCH
        SPX_PROFILE_TIME(SPX_PROFILE_FN_FORS_TREEHASH,
            fors_treehashx4_sign(roots + i*SPX_N, sig, ctx,
                     indices[i], idx_offset, SPX_FORS_HEIGHT,
                     fors_tree_addr));
#else
        SPX_PROFILE_TIME(SPX_PROFILE_FN_FORS_TREEHASH,
            treehashx1(roots + i*SPX_N, sig, ctx,
                     indices[i], idx_offset, SPX_FORS_HEIGHT, fors_gen_leafx1,
                     fors_tree_addr, &fors_info));
#endif
        SPX_BATCH_REGION_POP(spx_batch_previous_region);

        sig += SPX_N * SPX_FORS_HEIGHT;
    }

    /* Hash horizontally across all tree roots to derive the public key. */
    thash(pk, roots, SPX_FORS_TREES, ctx, fors_pk_addr);
    SPX_PROFILE_FN_END(SPX_PROFILE_FN_FORS_SIGN);
}

/**
 * Derives the FORS public key from a signature.
 * This can be used for verification by comparing to a known public key, or to
 * subsequently verify a signature on the derived public key. The latter is the
 * typical use-case when used as an FTS below an OTS in a hypertree.
 * Assumes m contains at least SPX_FORS_HEIGHT * SPX_FORS_TREES bits.
 */
void fors_pk_from_sig(unsigned char *pk,
                      const unsigned char *sig, const unsigned char *m,
                      const spx_ctx* ctx,
                      const uint32_t fors_addr[8])
{
    SPX_PROFILE_FN_BEGIN();
    uint32_t indices[SPX_FORS_TREES];
    unsigned char roots[SPX_FORS_TREES * SPX_N];
    unsigned char leaf[SPX_N];
    uint32_t fors_tree_addr[8] = {0};
    uint32_t fors_pk_addr[8] = {0};
    uint32_t idx_offset;
    unsigned int i;

    copy_keypair_addr(fors_tree_addr, fors_addr);
    copy_keypair_addr(fors_pk_addr, fors_addr);

    set_type(fors_tree_addr, SPX_ADDR_TYPE_FORSTREE);
    set_type(fors_pk_addr, SPX_ADDR_TYPE_FORSPK);

    message_to_indices(indices, m);

    for (i = 0; i < SPX_FORS_TREES; i++) {
        idx_offset = i * (1 << SPX_FORS_HEIGHT);

        set_tree_height(fors_tree_addr, 0);
        set_tree_index(fors_tree_addr, indices[i] + idx_offset);

        /* Derive the leaf from the included secret key part. */
        fors_sk_to_leaf(leaf, sig, ctx, fors_tree_addr);
        sig += SPX_N;

        /* Derive the corresponding root node of this tree. */
        compute_root(roots + i*SPX_N, leaf, indices[i], idx_offset,
                     sig, SPX_FORS_HEIGHT, ctx, fors_tree_addr);
        sig += SPX_N * SPX_FORS_HEIGHT;
    }

    /* Hash horizontally across all tree roots to derive the public key. */
    thash(pk, roots, SPX_FORS_TREES, ctx, fors_pk_addr);
    SPX_PROFILE_FN_END(SPX_PROFILE_FN_FORS_PK_FROM_SIG);
}
