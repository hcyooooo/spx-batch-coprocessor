# Project Structure

This repository keeps software profiling, C reference experiments, future RTL,
and simulation scaffolding separated on purpose. The current committed work is
software-first; `rtl/` and most porting directories are placeholders until the
C model and profiling data are stable.

```text
spx-batch-coprocessor/
├── README.md
├── docs/
│   ├── project_structure.md
│   ├── sphincs_profile_result.md
│   ├── sphincs_batch_utilization.md
│   ├── phase1_c_model.md
│   └── phase1_6_batch_scheduler.md
├── sw/
│   ├── sphincsplus/
│   │   ├── ref/
│   │   ├── haraka-aesni/
│   │   ├── sha2-avx2/
│   │   ├── shake-a64/
│   │   └── shake-avx2/
│   ├── spx_model/
│   ├── spx_port/
│   │   ├── include/
│   │   └── src/
│   └── baremetal/
├── rtl/
│   ├── common/
│   ├── core/
│   ├── interface/
│   └── spx_accel/
└── sim/
    ├── tb/
    └── vectors/
```

## Top-Level Directories

`docs/`

Design notes, profiling results, and phase reports. Put architecture decisions
and reproducible command lines here rather than scattering them through source
comments.

`sw/`

All software-side work. This includes the modified SPHINCS+ reference tree,
standalone C model pieces, and future platform/porting code.

`rtl/`

Reserved for future hardware implementation. It is intentionally empty apart
from `.gitkeep` placeholders right now.

`sim/`

Reserved for future RTL/system simulation testbenches and vectors.

## Software Layout

`sw/sphincsplus/`

Vendor-style SPHINCS+ source tree with local reference-code experiments. The
nested upstream `.git` metadata was removed before importing this project into
the top-level repository, so this directory is tracked as normal source.

`sw/sphincsplus/ref/`

Main working area for the current phases:

- `profile.c`, `profile.h`: Phase 0/0.5 profiling and batch-utilization counters.
- `test/profile.c`: profiling runner for keygen/sign/verify.
- `keccakx4.c`, `keccakx4.h`: 4-lane Keccak-f1600 C reference model.
- `thashx4_shake_simple.c`, `thashx4_shake_simple.h`: SHAKE-simple thashx4 model.
- `batch_scheduler.c`, `batch_scheduler.h`: C-level batch scheduling statistics.
- `test/test_keccakx4.c`, `test/test_thashx4.c`, `test/test_wots_batch.c`:
  correctness tests for x4 model and scheduler experiments.

`sw/sphincsplus/{haraka-aesni,sha2-avx2,shake-a64,shake-avx2}/`

Upstream optimized implementation directories. They are retained for reference,
but the current profiling and C-model work should stay in `sw/sphincsplus/ref/`
unless a later phase explicitly targets another implementation.

`sw/spx_model/`

Standalone copies of the C-model support files. Treat this as a scratch/golden
model staging area when experiments should be isolated from the upstream-shaped
SPHINCS+ tree.

`sw/spx_port/`

Placeholder for future platform integration code. Keep portable headers in
`include/` and source files in `src/` once porting begins.

`sw/baremetal/`

Placeholder for future bare-metal examples or bring-up code.

## Hardware and Simulation Layout

`rtl/common/`

Shared RTL utilities or packages once hardware work begins.

`rtl/core/`

Future standalone primitive cores, such as Keccak permutation datapaths.

`rtl/interface/`

Future host/core bus or coprocessor interface wrappers.

`rtl/spx_accel/`

Future SPHINCS+-specific accelerator top-level blocks.

`sim/tb/`

Future testbenches.

`sim/vectors/`

Future generated or captured test vectors.

## Current Build Entry Points

Reference smoke test:

```sh
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple test/spx
./sw/sphincsplus/ref/test/spx
```

Phase 0 profiling:

```sh
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple \
  EXTRA_CFLAGS=-DSPX_PROFILE test/profile
./sw/sphincsplus/ref/test/profile
```

Phase 0.5 batch-utilization profiling:

```sh
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple \
  EXTRA_CFLAGS=-DSPX_BATCH_PROFILE test/profile
./sw/sphincsplus/ref/test/profile
```

Phase 1/1.5 x4 C-model tests:

```sh
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple x4-test
```

Phase 1.6 scheduler experiment:

```sh
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple batch-test
```
