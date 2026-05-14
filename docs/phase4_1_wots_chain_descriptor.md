# Phase 4.1 WOTS-Chain Descriptor Integration

Phase 4.1 moves the Phase 4 WOTS-chain x4 scheduler behind the existing
descriptor-control path. Software still controls the accelerator through the
same CV-X-IF descriptor instructions, and bulk data still moves through the
descriptor adapter memory-side path. The new part is an operation type in the
descriptor ABI that lets one descriptor run several WOTS chain steps in
hardware.

This phase does not add a new bus fabric, AXI, AHB, APB, X-HEEP integration, or
CV-X-IF bulk-data movement. It keeps the Phase 3 descriptor boundary and extends
the operation executed behind it.

## Scope

Implemented:

- descriptor op type `THASHX4`;
- descriptor op type `WOTS_CHAINX4`;
- WOTS chain control word with `start_step` and `num_steps`;
- descriptor adapter muxing between `spx_thashx4_core` and
  `spx_wots_chainx4_core`;
- standalone descriptor-level WOTS chain regression;
- CV32E40X bare-metal WOTS chain smoke regression;
- performance accounting for WOTS chain descriptors in the CV32E40X smoke
  harness.

Not implemented:

- lane drop-off for divergent WOTS verify chains;
- WOTS public-key compression;
- a full WOTS public-key engine;
- interrupt-driven wait semantics;
- real SoC memory hierarchy or cache coherency;
- PPA refresh for the larger descriptor adapter.

## Descriptor ABI

The descriptor remains eight 32-bit words.

| Word | Offset | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | `0x00` | flags/status | Existing done/error writeback word |
| 1 | `0x04` | config | lanes, variant, op type, and thash inblocks |
| 2 | `0x08` | pub seed pointer | 16-byte aligned pointer unless inline seed is used |
| 3 | `0x0c` | address base pointer | 32 words, four 256-bit SPHINCS addresses |
| 4 | `0x10` | input base pointer | WOTS mode uses 16 words, four 128-bit chain inputs |
| 5 | `0x14` | output base pointer | 16 words, four 128-bit final chain outputs |
| 6 | `0x18` | descriptor length | Software-visible length hint, currently still not enforced |
| 7 | `0x1c` | chain control | WOTS `start_step` and `num_steps` |

Config word layout:

| Bits | Field | Values |
| ---: | --- | --- |
| `1:0` | thash `inblocks` | `1` or `2` for `THASHX4`; ignored by `WOTS_CHAINX4` |
| `7:4` | lanes | `4` |
| `15:8` | variant | `1`, SHAKE-128f-simple |
| `23:16` | op type | `0 = THASHX4`, `1 = WOTS_CHAINX4` |

Chain control word layout:

| Bits | Field | Values |
| ---: | --- | --- |
| `7:0` | `start_step` | `0..15` |
| `15:8` | `num_steps` | `1..15` |

For `WOTS_CHAINX4`, the valid chain window is:

```text
num_steps != 0
num_steps <= 15
start_step < 16
start_step + num_steps <= 16
```

Invalid op types return `ERR_BAD_OP_TYPE = 5`. Invalid WOTS chain windows return
`ERR_BAD_CHAIN = 6`.

## RTL Integration

`spx_descriptor_adapter` now parses `op_type` from config bits `23:16`.

For `THASHX4`, behavior is kept compatible with the previous descriptor path:

- `inblocks` comes from config bits `1:0`;
- input size is 16 words for `inblocks=1` or 32 words for `inblocks=2`;
- outputs come from `spx_thashx4_core`.

For `WOTS_CHAINX4`:

- the adapter forces the effective internal `inblocks` status field to `1`;
- input size is 16 words total, four 128-bit chain values;
- address size remains 32 words total, four 256-bit addresses;
- `start_step` and `num_steps` come from descriptor word 7;
- outputs come from `spx_wots_chainx4_core`.

Both op types share the same descriptor fetch, public-seed fetch, address fetch,
output writeback, descriptor status writeback, and performance counters.

## Software Smoke

`sw/tests/spx_cvxif_wots_chain_smoke.c` is a bare-metal CV32E40X program that:

- reads the WOTS vector table at `0x00008000`;
- prepares one descriptor per WOTS vector case;
- issues `SPX_CLEAR`, `SPX_SET_DESC`, `SPX_START`, repeated `SPX_STATUS`, and
  final `SPX_CLEAR`;
- compares all 16 output words against the golden vector case;
- reports pass/fail through the existing smoke magic address and stats block.

The WOTS vector table uses magic `0x53505857` and five generated cases:

| Case | `start_step` | `num_steps` |
| ---: | ---: | ---: |
| 0 | 14 | 1 |
| 1 | 9 | 2 |
| 2 | 5 | 4 |
| 3 | 3 | 8 |
| 4 | 0 | 15 |

## Standalone Descriptor Regression

New target:

```sh
make -C sim sim-wots-chain-descriptor
```

Observed result:

```text
PASS wots_chain_descriptor (5 WOTS cases)
```

The testbench checks:

- all five generated WOTS vector cases;
- output words for all four lanes;
- `num_steps = 0` returns `ERR_BAD_CHAIN`;
- `num_steps = 16` returns `ERR_BAD_CHAIN`;
- `start_step + num_steps > 16` returns `ERR_BAD_CHAIN`;
- unknown op type returns `ERR_BAD_OP_TYPE`.

Observed descriptor-adapter performance in the 4-word memory-side path:

| `num_steps` | Baseline repeated thash descriptors | WOTS descriptor cycles | Speedup | Load | Core | Store |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 57 | 52 | 1.10x | 15 | 29 | 5 |
| 2 | 114 | 80 | 1.43x | 15 | 57 | 5 |
| 4 | 228 | 136 | 1.68x | 15 | 113 | 5 |
| 8 | 456 | 248 | 1.84x | 15 | 225 | 5 |
| 15 | 855 | 444 | 1.93x | 15 | 421 | 5 |

The baseline uses the Phase 3.9 zero-wait descriptor-thashx4 wall-cycle value:
57 cycles per descriptor step.

## CV32E40X WOTS Smoke

New target:

```sh
make -C sim sim-cv32e40x-wots-chain-smoke
```

Observed result:

```text
PASS cv32e40x_spx_core_smoke ... cases_passed=5 cases_failed=0 status_poll_count=90
```

Observed WOTS chain performance summary:

| `num_steps` | Baseline repeated thash descriptors | Core-visible WOTS cycles | Speedup | XIF instr | Status polls | Bus rd | Bus wr | Descriptor `perf_total` |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 57 | 55 | 1.04x | 9 | 5 | 15 | 5 | 52 |
| 2 | 114 | 88 | 1.30x | 12 | 8 | 15 | 5 | 80 |
| 4 | 228 | 143 | 1.59x | 17 | 13 | 15 | 5 | 136 |
| 8 | 456 | 253 | 1.80x | 27 | 23 | 15 | 5 | 248 |
| 15 | 855 | 451 | 1.90x | 45 | 41 | 15 | 5 | 444 |

The core-visible cycle count includes CV32E40X software polling overhead. The
descriptor `perf_total` counter is the hardware-side adapter total and matches
the standalone descriptor regression for each WOTS case.

## Compatibility Checks

Observed passing commands:

```sh
./scripts/lint_rtl.sh
make -C sim sim-wots-chain-descriptor
make -C sim sim-descriptor-adapter
make -C sim sim-cv32e40x-wots-chain-smoke
make -C sim sim-cv32e40x-core-smoke
git diff --check
```

The original `THASHX4` descriptor path still passes the three-width descriptor
adapter regression:

```text
PASS spx_descriptor_adapter width=1words_per_cycle inblocks=1,2 (200 cases)
PASS spx_descriptor_adapter width=2words_per_cycle inblocks=1,2 (200 cases)
PASS spx_descriptor_adapter width=4words_per_cycle inblocks=1,2 (200 cases)
```

The original zero-wait CV32E40X thash smoke still passes:

```text
PASS cv32e40x_spx_core_smoke ... cases_passed=16 cases_failed=0
```

The CV32E40X Verilator build still emits known third-party CV32E40X warnings
such as timescale and unoptimizable-combinational warnings. The simulation
targets use `-Wno-fatal`, and the observed smoke runs complete successfully.

## Interpretation

Phase 4.1 confirms that WOTS-chain scheduling is useful at the real
descriptor-control boundary, not only as a standalone core prototype. Long
chains gain most because one descriptor fetch, one pub-seed/address/input load,
one output store, and one software polling sequence cover many internal thashx4
steps.

For `num_steps=15`, the core-visible speedup is 1.90x against issuing 15
separate zero-wait thash descriptors. The hardware-side descriptor adapter
counter shows 444 cycles versus an 855-cycle repeated-descriptor baseline.

## Next Steps

- Add wait-state and backpressure WOTS smoke modes to compare against the Phase
  3.8 hardening matrix.
- Add error-path CV32E40X coverage for bad WOTS chain descriptors.
- Refresh descriptor-adapter FPGA PPA with `spx_wots_chainx4_core` included.
- Explore lane drop-off or mixed-length WOTS verify chains before attempting a
  full WOTS public-key accelerator.
