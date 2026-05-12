# SPHINCS+ Reference Profiling Result

This is Phase 0 software profiling for the `ref/` reference implementation.
It does not change cryptographic logic, does not use AVX2, does not implement
Keccakx4/thashx4, and does not include any RTL, RISC-V, or CV32E40PX port.

The timings below are native PC timings from `clock_gettime(CLOCK_MONOTONIC)`.
They are not CV32E40PX cycle counts. Timings are inclusive for instrumented
logical regions, so nested rows such as `treehash`, `wots_gen_pk`, and `thash`
can overlap and percentages are not expected to sum to 100%.

## Build and Run

Correctness smoke test:

```sh
make -C sw/sphincsplus/ref clean
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple test/spx
./sw/sphincsplus/ref/test/spx
```

Profiling build and run:

```sh
make -C sw/sphincsplus/ref clean
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple EXTRA_CFLAGS=-DSPX_PROFILE test/profile
./sw/sphincsplus/ref/test/profile
```

One-shot profiling target:

```sh
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple profile
```

## Parameter Set

- Repository parameter name: `sphincs-shake-128f`
- Tweakable hash mode: `simple`
- Linked hash files: `hash_shake.c`, `thash_shake_simple.c`
- Interpreted target: SPHINCS+-SHAKE256-128f-simple / SPHINCS+-SHAKE-128f-simple
- Main parameters: `n=16`, `h=66`, `d=22`, `fors_height=6`, `fors_trees=33`, `wots_w=16`

## Native Profiling Output

Run date: 2026-05-12 on the local PC/native environment.

```text
Parameters: sphincs-shake-128f, THASH=simple
n=16 h=66 d=22 fors_height=6 fors_trees=33 wots_w=16

keygen profile (total: 2080733 ns, 2.081 ms)
Function                      Calls         Time(ns)    Percent
---------------------------------------------------------------
thash                          4215          1867150     89.74%
prf_addr                        280           109528      5.26%
gen_message_random                0                0      0.00%
hash_message                      0                0      0.00%
gen_chain                         0                0      0.00%
wots_gen_pk                       8          2075112     99.73%
wots_pk_from_sig                  0                0      0.00%
fors_gen_leaf                     0                0      0.00%
fors_sign                         0                0      0.00%
fors_pk_from_sig                  0                0      0.00%
fors_treehash                     0                0      0.00%
treehash                          1          2079249     99.93%
compute_root                      0                0      0.00%

sign profile (total: 40115556 ns, 40.116 ms)
Function                      Calls         Time(ns)    Percent
---------------------------------------------------------------
thash                         96922         34893795     86.98%
prf_addr                       8305          2823860      7.04%
gen_message_random                1             1049      0.00%
hash_message                      1              463      0.00%
gen_chain                         0                0      0.00%
wots_gen_pk                     176         37696621     93.97%
wots_pk_from_sig                  0                0      0.00%
fors_gen_leaf                  2112          1507407      3.76%
fors_sign                         1          2282653      5.69%
fors_pk_from_sig                  0                0      0.00%
fors_treehash                    33          2258630      5.63%
treehash                         22         37822198     94.28%
compute_root                      0                0      0.00%

verify profile (total: 2271259 ns, 2.271 ms)
Function                      Calls         Time(ns)    Percent
---------------------------------------------------------------
thash                          6185          2103997     92.64%
prf_addr                          0                0      0.00%
gen_message_random                0                0      0.00%
hash_message                      1              848      0.04%
gen_chain                       770          2109933     92.90%
wots_gen_pk                       0                0      0.00%
wots_pk_from_sig                 22          2125688     93.59%
fors_gen_leaf                     0                0      0.00%
fors_sign                         0                0      0.00%
fors_pk_from_sig                  1            87941      3.87%
fors_treehash                     0                0      0.00%
treehash                          0                0      0.00%
compute_root                     55            97304      4.28%

Signature size: 17088 bytes
```

## Hotspot Interpretation

- Key generation is dominated by the top Merkle tree build. The `treehash`
  wrapper calls `wots_gen_pk` 8 times for `SPX_TREE_HEIGHT=3`; `thash` accounts
  for about 90% of the native time.
- Signing is dominated by the 22 Merkle `treehash` calls. These call
  `wots_gen_pk` 176 times and generate 96,922 `thash` calls in this run.
- FORS signing is smaller than WOTS/Merkle for 128f, but still naturally
  structured as 33 independent trees with 2,112 leaf generations.
- Verification is dominated by WOTS chain reconstruction via `wots_pk_from_sig`
  and `gen_chain`; the exact `thash` call count can vary with the message hash
  because WOTS chain lengths vary.

## x4 Batch Suitability

Likely good x4 batch candidates:

- `thash` with one-block WOTS/FORS leaf inputs: very high call count and regular
  input size.
- WOTS pk generation inside `wots_gen_leafx1`: many independent chains across
  WOTS elements and across leaves in `treehash`.
- FORS leaf generation: independent `prf_addr + thash` leaves inside each FORS
  tree.
- Merkle internal-node `thash` calls: good candidate when four same-height nodes
  are available.
- Verification `gen_chain`: many independent chains across WOTS elements, but
  chain lengths are message-dependent and need utilization tracking.

Lower-priority or less batch-friendly in this profile:

- `gen_message_random` and `hash_message`: called once per sign/verify and too
  small here to drive a 4-lane coprocessor.
- Top-level `fors_sign`, `treehash`, and `wots_pk_from_sig` are useful scheduling
  regions, but the primitive acceleration target is still the underlying
  `thash`/PRF work.

## Next Batch Utilization Metrics

- Number of ready independent `thash` jobs by input block count: 1-block WOTS/FORS,
  2-block Merkle internal nodes, and multi-block WOTS/FORS pk compression.
- x4 lane occupancy histogram: full 4-lane batches, partial 1/2/3-lane batches,
  and padding or idle-lane rate.
- Batch formation latency: how long work waits before four compatible jobs are
  available.
- Per-region batchability: WOTS leaf generation, FORS leaf generation, Merkle
  internal levels, and verification WOTS chain reconstruction separately.
- Address/PUB_SEED reuse rate across a batch, especially whether lanes share
  common public seed and only differ in address.
- Variable-chain divergence in verify `gen_chain`: distribution of remaining
  chain lengths per WOTS element and the resulting lane drop-off.
