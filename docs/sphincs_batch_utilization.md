# SPHINCS+ Reference Batch Utilization Profiling

This is Phase 0.5 batch-utilization profiling for the `ref/` implementation.
It estimates x4 packing opportunities for the native reference code path only.
It does not execute a vectorized Keccak/thash, does not change SPHINCS+ outputs,
does not use AVX2, and does not include RTL, RISC-V, or CV32E40PX work.

The current target is:

- `PARAMS=sphincs-shake-128f`
- `THASH=simple`
- Interpreted as SPHINCS+-SHAKE-128f-simple
- Main parameters: `n=16`, `h=66`, `d=22`, `fors_height=6`,
  `fors_trees=33`, `wots_w=16`

## Build and Run

Batch-only profiling:

```sh
make -C sw/sphincsplus/ref clean
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple EXTRA_CFLAGS=-DSPX_BATCH_PROFILE test/profile
./sw/sphincsplus/ref/test/profile
```

Timing plus batch profiling:

```sh
make -C sw/sphincsplus/ref clean
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple \
  EXTRA_CFLAGS="-DSPX_PROFILE -DSPX_BATCH_PROFILE" test/profile
./sw/sphincsplus/ref/test/profile
```

One-shot target:

```sh
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple profile
```

## Counting Method

`thash` calls are classified from the SPHINCS+ address type and `inblocks`:

- `SPX_ADDR_TYPE_WOTS`: WOTS chain thash
- `SPX_ADDR_TYPE_WOTSPK`: WOTS pk compression thash
- `SPX_ADDR_TYPE_FORSTREE`, `inblocks=1`: FORS leaf thash
- `SPX_ADDR_TYPE_FORSTREE`, `inblocks=2`: FORS internal node thash
- `SPX_ADDR_TYPE_HASHTREE`, `inblocks=2`: Merkle internal node thash
- All other `thash` calls: other thash

Region utilization is computed over compatible primitive jobs. `prf_addr` is
kept as its own job kind, and `thash` jobs are split by type and block-count
bucket before x4 packing. A region row sums those per-kind histograms, so unlike
jobs are not treated as if they could share the same x4 batch.

For each compatible job kind:

```text
allocated_lanes = ceil(total_jobs / 4) * 4
useful_lanes    = total_jobs
utilization     = useful_lanes / allocated_lanes
```

The output is aggregate across one keygen, one sign, and one verify in
`ref/test/profile`. Counts involving verification WOTS chains can vary between
runs because signing uses randomized message randomness.

## Sample Output

Run date: 2026-05-12 on the local PC/native environment.

```text
thash type and input-block distribution
Type                                 inblocks=1   inblocks=2   inblocks>2        total
--------------------------------------------------------------------------------
WOTS chain thash                         102405            0            0       102405
WOTS pk compression thash                     0            0          206          206
FORS leaf thash                            2145            0            0         2145
FORS internal node thash                      0         2277            0         2277
Merkle internal node thash                    0          227            0          227
other thash                                   0            0            2            2

x4 batch lane occupancy by region
Region                    full_x4     x3     x2     x1   total_jobs  utilization
-------------------------------------------------------------------------------
wots_gen_pk                 25806      0      0      0       103224      100.00%
fors_gen_leaf                1056      0      0      0         4224      100.00%
fors_treehash                 519      1      0      0         2079       99.95%
merkle_internal                40      0      0      1          161       98.17%
verify_gen_chain             1451      0      0      1         5805       99.95%
```

## Best Initial x4 Targets

- WOTS chain thash inside `wots_gen_pk`: highest count, regular `inblocks=1`,
  and excellent x4 packing.
- FORS leaf generation: regular `prf_addr + inblocks=1 thash`, naturally many
  independent leaves.
- FORS internal nodes: all `inblocks=2`, many nodes across 33 FORS trees.
- Verification WOTS `gen_chain`: high count and good aggregate packing, but
  chain lengths vary; a real x4 scheduler should measure lane drop-off within
  grouped chains before committing to a lockstep design.

## Lower-Priority or Poor Batch Targets

- `gen_message_random` and `hash_message`: one call per sign/verify path and not
  enough volume for the proposed coprocessor.
- FORS pk compression and verification FORS pk compression: only two `other`
  multi-block `thash` jobs in the single-operation profile.
- Merkle internal nodes: clean `inblocks=2` jobs, but only 161 jobs in the
  keygen+sign treehash regions for this single-operation 128f profile.
- Single-signature `compute_root` authentication-path verification has limited
  local parallelism; it may become interesting only when batching multiple
  signatures at a higher level.
