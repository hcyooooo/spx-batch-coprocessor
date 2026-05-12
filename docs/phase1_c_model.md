# Phase 1 / 1.5 C Reference Model: Keccak-f1600x4 / thashx4

This phase adds a correctness-first C model for 4-lane batch hashing in the
`ref/` implementation. Phase 1 added `keccak_f1600x4`; Phase 1.5 replaces the
initial `thashx4` wrapper for SHAKE-simple `inblocks=1` and `inblocks=2` with a
true SHAKE256 x4 path that calls `keccak_f1600x4()`. It does not add RTL,
RISC-V integration, CV32E40PX changes, custom instructions, AVX2, or
performance optimizations.

Target configuration:

- `PARAMS=sphincs-shake-128f`
- `THASH=simple`
- Interpreted as SPHINCS+-SHAKE-128f-simple

## Added Files

- `ref/keccakx4.h`
- `ref/keccakx4.c`
- `ref/thashx4_shake_simple.h`
- `ref/thashx4_shake_simple.c`
- `ref/test/test_keccakx4.c`
- `ref/test/test_thashx4.c`

Small support changes:

- `ref/fips202.h` now declares `keccak_f1600()`.
- `ref/fips202.c` exposes `keccak_f1600()` as a thin wrapper around the
  existing scalar `KeccakF1600_StatePermute()`, so tests can compare the x4
  model against the original scalar permutation.
- `ref/Makefile` includes the x4 C model for SHAKE parameter sets and enables
  the simple `thashx4` test when `THASH=simple`.

## Build Commands

Build both x4 tests:

```sh
make -C ref PARAMS=sphincs-shake-128f THASH=simple x4-tests
```

Build and run both x4 tests:

```sh
make -C ref PARAMS=sphincs-shake-128f THASH=simple x4-test
```

Build individual tests:

```sh
make -C ref PARAMS=sphincs-shake-128f THASH=simple test/test_keccakx4
make -C ref PARAMS=sphincs-shake-128f THASH=simple test/test_thashx4
```

## Run Commands

```sh
./ref/test/test_keccakx4
./ref/test/test_thashx4
```

Original keygen/sign/verify smoke test:

```sh
make -C ref PARAMS=sphincs-shake-128f THASH=simple test/spx.exec
```

## Correctness Results

Run locally on 2026-05-12 after Phase 1.5:

```text
PASS keccak_f1600x4 correctness (1024 random rounds)
PASS thashx4 true Keccakx4 correctness for inblocks=1,2 (1000 rounds each)
```

The original SPHINCS+ smoke test still passes:

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

## Current Model Status

`keccak_f1600x4(uint64_t state[4][25])` is a real 4-lane C reference model.
It executes the Keccak theta, rho, pi, chi, and iota steps over four independent
states using ordinary C arrays and no SIMD intrinsics. The test compares each
lane against `keccak_f1600()` on the same input state.

`thashx4()` now uses a true x4 SHAKE256 path for SHAKE-simple `inblocks=1` and
`inblocks=2`:

```text
for each lane:
    absorb pub_seed || addr_bytes || input
    apply SHAKE256 domain byte 0x1F and rate-end padding 0x80

keccak_f1600x4(state4)

for each lane:
    squeeze SPX_N bytes
```

For SPHINCS+-SHAKE-128f-simple, `SPX_N=16`, so the supported thash inputs are
single-rate-block SHAKE256 absorbs:

- `inblocks=1`: `16 + 32 + 16 = 64` bytes
- `inblocks=2`: `16 + 32 + 32 = 80` bytes

Both are below `SHAKE256_RATE=136`, so Phase 1.5 implements single-block absorb,
one x4 Keccak permutation, and direct squeeze.

## Fallback

`thashx4()` keeps a scalar fallback for `inblocks > 2`:

```text
fallback thashx4 = thash lane0 + thash lane1 + thash lane2 + thash lane3
```

This preserves correctness for larger thash calls while keeping the true x4
model focused on the hot SHAKE-128f-simple `inblocks=1` and `inblocks=2` cases.

## Current Limits

- The true x4 path assumes the input fits within one SHAKE256 rate block.
- It currently targets SHAKE-simple thash only.
- It is a C reference/golden model, not an optimized implementation.
- It is not yet wired into WOTS/FORS/Merkle batch scheduling.

## Next Step

Hook the true `thashx4()` model into batch scheduler experiments:

1. Add x4 call sites around WOTS chain thash groups where four lanes have the
   same `inblocks=1` shape.
2. Add x4 call sites around FORS and Merkle internal-node groups where four
   lanes have the same `inblocks=2` shape.
3. Preserve scalar cleanup paths for tails of 1-3 jobs.
4. Keep comparing x4 outputs against the scalar thash path during scheduler
   bring-up.
5. Only after the C scheduler is functionally stable, use this model as the RTL
   golden reference.
