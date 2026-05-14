# Phase 4 WOTS-Chain x4 Micro-Scheduler Prototype

Phase 4 adds a small WOTS-chain x4 hot-loop prototype on top of the existing
`spx_thashx4_core`. It is intentionally core-level only. It does not connect a
full SoC, AXI, AHB, APB, X-HEEP, or any new CV-X-IF bulk-data path, and it does
not change Keccak or thash semantics.

The existing descriptor-thashx4 path remains intact. The new block is a
prototype for measuring whether multiple WOTS chain steps should be issued as
one hardware-scheduled operation instead of as one descriptor per thashx4 step.

## Why WOTS Chain Scheduling

Phase 3.9 showed that a single descriptor around one `thashx4` call carries a
fixed control envelope: clear, set descriptor, start, repeated status polling,
and final clear. In zero-wait mode, five of nine accepted CV-X-IF control
instructions are status polls. That polling share rises under memory wait
states.

WOTS chains are a good Phase 4 target because each chain is a repeated sequence
of `thash(..., inblocks=1, ...)` calls where the output of one step becomes the
input of the next step and the address hash field increments. Moving that loop
inside hardware amortizes descriptor setup and polling without turning Phase 4
into a full WOTS public-key engine.

## Phase 3.9 Baseline

The baseline is the zero-wait CV32E40X core-level descriptor path:

| Metric | `inblocks=1` | `inblocks=2` |
| --- | ---: | ---: |
| Wall cycles per descriptor | 57 | 57 |
| Descriptor `perf_total` | 50 | 54 |
| Bus reads, 4-word descriptor adapter | 15 | 19 |
| Bus writes, 4-word descriptor adapter | 5 | 5 |
| XIF control instructions | 9 | 9 |
| Status polls | 5 | 5 |
| Polling share of XIF control | 55.6% | 55.6% |
| Wall cycles per thash-equivalent | 14.25 | 14.25 |

For a WOTS chain hot loop, the relevant descriptor baseline is repeated
`inblocks=1` thashx4 descriptors. The comparison below uses 57 wall cycles,
9 XIF instructions, 5 status polls, 15 bus reads, and 5 bus writes per step.

## WOTS Chain Dataflow

For each of four lanes:

1. Software provides a chain input value `in[lane]`, one SPHINCS+ `N=16` byte
   value.
2. Software provides the lane's 32-byte SPHINCS+ address.
3. Hardware sets the SHAKE-simple WOTS hash-address byte to
   `start_step + step`.
4. Hardware runs `thashx4(..., inblocks=1, ...)`.
5. The 16-byte output is fed back as the next step input.
6. After `num_steps`, hardware exposes the final four 16-byte chain outputs.

The prototype uses the SHAKE address layout from the reference implementation:
the WOTS hash-address field is byte offset 31. The chain-address and keypair
fields are passed through from software.

## Hardware And Software Split

Hardware does:

- store four current chain values;
- update the address hash field for every step;
- start and wait for the existing `spx_thashx4_core`;
- feed each step output into the next step input;
- report `start`, `busy`, `done`, and `error`;
- support `inblocks=1` only.

Software still does:

- choose which chains to group into the four lanes;
- prepare `pub_seed`, base addresses, and initial chain inputs;
- handle WOTS chain-length divergence in a later phase;
- perform WOTS public-key compression outside this prototype;
- move bulk data through the existing descriptor-side memory path once a
  descriptor adapter is added.

## First Prototype Limits

- All four lanes use the same `num_steps`.
- No lane drop-off for WOTS verify divergence.
- No `inblocks=2`.
- No WOTS public-key compression.
- No full WOTS public-key hardware.
- No SoC, bus fabric, X-HEEP, AXI, AHB, or APB integration.
- No CV-X-IF bulk-data movement.
- Valid chain windows must satisfy `start_step + num_steps <= 16`.

## Implemented Files

- `sw/spx_model/wots_chainx4_model.c`
- `sw/spx_model/wots_chainx4_model.h`
- `sw/spx_model/descriptor_ext_model.c`
- `sw/spx_model/descriptor_ext_model.h`
- `rtl/core/spx_wots_chainx4_core.sv`
- `sim/tb/tb_wots_chainx4_core.sv`

The vector generator now emits `sim/vectors/wots_chainx4_vectors.hex` for
`num_steps = 1, 2, 4, 8, 15`.

## C Model Correctness

The C model internally loops over WOTS chain steps and calls the true
Keccakx4-based `spx_thashx4_model(..., inblocks=1, ...)` for each step.

Before writing each golden vector, the generator compares:

- x4 WOTS-chain model output;
- scalar per-lane `gen_chain` style reference that updates the same hash
  address field and applies one scalar thash step at a time.

`make -C sim sim-wots-chainx4` rebuilds the generator and therefore reruns this
C model self-check before RTL simulation.

## RTL Correctness

`spx_wots_chainx4_core` instantiates the unchanged `spx_thashx4_core`.

The standalone testbench checks five vector groups:

| Case | `start_step` | `num_steps` |
| ---: | ---: | ---: |
| 0 | 14 | 1 |
| 1 | 9 | 2 |
| 2 | 5 | 4 |
| 3 | 3 | 8 |
| 4 | 0 | 15 |

Each case uses different addresses and inputs per lane. RTL outputs matched the
C golden model for all lanes.

Observed command:

```sh
make -C sim sim-wots-chainx4
```

Observed result:

```text
PASS wots_chainx4_core (5 cases)
```

## Latency

Standalone core-level latency:

| `num_steps` | Cycles | Cycles per chain step | Cycles per thash-equivalent |
| ---: | ---: | ---: | ---: |
| 1 | 29 | 29.00 | 7.25 |
| 2 | 57 | 28.50 | 7.12 |
| 4 | 113 | 28.25 | 7.06 |
| 8 | 225 | 28.12 | 7.03 |
| 15 | 421 | 28.07 | 7.02 |

The measured prototype follows `cycles = 28 * num_steps + 1`. The underlying
`spx_thashx4_core` still measures 27 cycles for a single `thashx4`; the wrapper
adds one scheduling cycle per internal step plus the final observation cycle.

## Descriptor Extension Model

The descriptor extension model is C-only for now. It defines:

- `op_type = THASHX4`
- `op_type = WOTS_CHAINX4`
- `pub_seed_ptr`
- `addr_base_ptr`
- `input_base_ptr`
- `output_base_ptr`
- `start_step`
- `num_steps`
- `lanes = 4`
- `variant = SHAKE-128f-simple`

It can execute either one normal thashx4 descriptor shape or one WOTS-chain x4
descriptor shape against byte arrays. It also provides estimates for comparing:

- A: software issues `num_steps` separate thashx4 descriptors;
- B: software issues one WOTS_CHAINX4 descriptor and hardware runs the internal
  chain loop.

This is not wired to CV32E40X yet.

## Descriptor Baseline Comparison

This table compares repeated zero-wait descriptor-thashx4 scheduling against
the standalone WOTS-chain scheduler cycles measured above. Bus reductions assume
a future 4-word descriptor adapter reads the WOTS descriptor inputs once and
writes the final outputs once, while the baseline repeats the same descriptor
traffic every step.

| num_steps | baseline descriptors | baseline wall cycles | chain scheduler cycles | speedup | XIF instr reduction | bus_rd reduction | bus_wr reduction |
| ---------: | -------------------: | -------------------: | ---------------------: | ------: | ------------------: | ---------------: | ---------------: |
| 1 | 1 | 57 | 29 | 1.97x | 0 (0.0%) | 0 (0.0%) | 0 (0.0%) |
| 2 | 2 | 114 | 57 | 2.00x | 9 (50.0%) | 15 (50.0%) | 5 (50.0%) |
| 4 | 4 | 228 | 113 | 2.02x | 27 (75.0%) | 45 (75.0%) | 15 (75.0%) |
| 8 | 8 | 456 | 225 | 2.03x | 63 (87.5%) | 105 (87.5%) | 35 (87.5%) |
| 15 | 15 | 855 | 421 | 2.03x | 126 (93.3%) | 210 (93.3%) | 70 (93.3%) |

For `num_steps=15`, descriptor-at-a-time software would pay 15 descriptor
envelopes and 75 status polls. A WOTS_CHAINX4 descriptor would pay one envelope
and one completion polling sequence while the chain loop runs internally.

## Build And Regression

Observed passing commands:

```sh
make -C sim sim-wots-chainx4
make -C sim lint
make -C sim test
```

`make -C sim test` includes `sim-wots-chainx4` and the existing CV32E40X
core-level smoke regression. The existing descriptor-thashx4 path remains in the
test suite and still passes.

## Recommendation

The WOTS-chain scheduler is worth continuing. Even this minimal wrapper cuts
core-level cycles per thash-equivalent from the Phase 3.9 wall-clock baseline of
14.25 to about 7.02 for long chains, while the descriptor-level control,
polling, and bus traffic reductions approach one descriptor envelope per chain
instead of one envelope per step.

The next useful step is a WOTS_CHAINX4 descriptor adapter at the existing
descriptor boundary. That adapter should keep bulk data on the descriptor-side
memory path and keep CV-X-IF as control/status only. After that, it is worth
connecting the adapter to the CV32E40X descriptor-control path for direct
core-level measurements.
