# Phase 1.6 C-Level thashx4 Batch Scheduler

This phase wires the true SHAKE-simple `thashx4()` C model into selected
SPHINCS+-SHAKE-128f-simple software paths. It remains a C reference experiment:
no RTL, no CV32E40PX integration, no custom instructions, no AVX2, and no
algorithm-semantic changes.

Target configuration:

- `PARAMS=sphincs-shake-128f`
- `THASH=simple`
- Batch macro: `SPX_USE_THASHX4_BATCH`

## Modified Files

- `ref/wotsx1.c`
- `ref/wotsx1.h`
- `ref/fors.c`
- `ref/batch_scheduler.c`
- `ref/batch_scheduler.h`
- `ref/test/test_wots_batch.c`
- `ref/Makefile`
- `docs/phase1_6_batch_scheduler.md`

The existing true `thashx4()` implementation remains in:

- `ref/thashx4_shake_simple.c`
- `ref/keccakx4.c`

## Build Commands

Clean the SHAKE-simple build products:

```sh
make -C ref PARAMS=sphincs-shake-128f THASH=simple clean
```

Build and run the core x4 correctness tests:

```sh
make -C ref PARAMS=sphincs-shake-128f THASH=simple x4-test
```

Build and run the scheduler experiment:

```sh
make -C ref PARAMS=sphincs-shake-128f THASH=simple batch-test
```

Run the original non-batch smoke test:

```sh
make -C ref PARAMS=sphincs-shake-128f THASH=simple test/spx.exec
```

## Connected Regions

### WOTS pk Generation

`wots_gen_leafx1()` is macro-controlled:

- Default build: calls the original scalar reference path.
- `SPX_USE_THASHX4_BATCH`: calls the x4 batch path.

The batch path groups four WOTS chains at the same hash step and replaces four
`thash(..., inblocks=1, ...)` calls with one `thashx4()`. The three-chain tail
from `SPX_WOTS_LEN=35` remains scalar.

For testability, `wots_gen_leafx1_scalar_ref()` and
`wots_gen_leafx1_batch_ref()` are both exposed, so one binary can compare scalar
and batch WOTS outputs directly.

### FORS Signing Treehash

`fors_sign()` uses a macro-controlled level-order FORS treehash when
`SPX_USE_THASHX4_BATCH` is enabled:

- FORS leaves use `thashx4(..., inblocks=1, ...)`.
- FORS internal nodes use `thashx4(..., inblocks=2, ...)`.
- Parent levels with fewer than four nodes keep scalar fallback.

This path is used for signing. Verification still uses the scalar
`fors_pk_from_sig()` / `compute_root()` path.

## Test Results

Run locally on 2026-05-12 from a clean SHAKE-simple build:

```text
PASS keccak_f1600x4 correctness (1024 random rounds)
PASS thashx4 true Keccakx4 correctness for inblocks=1,2 (1000 rounds each)
PASS WOTS scalar-vs-batch pk/signature comparison (100 rounds)
PASS full keygen/sign/verify with thashx4 batch (2 signatures)

Region              thashx4_calls   scalar_fallback   replaced_scalar_thash   correctness
-----------------------------------------------------------------------------------------
wots_gen_pk                 43200             16200                  172800   PASS
fors_leaf                    1056                 0                    4224   PASS
fors_internal                 990               198                    3960   PASS
```

The original non-batch `test/spx` smoke test still passes:

```text
Generating keypair.. successful.
Testing 1 signatures..
  - iteration #0:
    smlen as expected [17120].
    verification succeeded.
    mlen as expected [32].
    output message as expected.
    in-place verification succeeded.
    flipping a bit of m invalidates signature.
```

## Current Fallbacks

- WOTS pk generation tails of 1-3 chains use scalar `thash()`.
- FORS internal levels with fewer than four parent nodes use scalar `thash()`.
- `thashx4()` itself still falls back to four scalar `thash()` calls for
  `inblocks > 2`.

## Not Yet Connected

- WOTS verification path in `wots_pk_from_sig()`.
- Merkle internal node hashing in `treehashx1()` / `compute_root()`.
- WOTS pk compression (`inblocks=SPX_WOTS_LEN`) remains scalar by design.
- FORS pk compression (`inblocks=SPX_FORS_TREES`) remains scalar by design.
- Any multi-signature higher-level batching.

## RTL Readiness

The true `keccak_f1600x4()` and `thashx4()` C paths are now usable as a golden
model for an RTL Keccak/thash block. Before starting system-level RTL or
CV32E40PX integration, the safer next C step is to add Merkle/internal and
verification-side scheduler coverage, then keep this batch test as the
regression oracle.
