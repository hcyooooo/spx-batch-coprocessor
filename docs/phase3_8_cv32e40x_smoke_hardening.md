# Phase 3.8 CV32E40X Core-Level Smoke Hardening

Phase 3.8 hardens the Phase 3.7 `cv32e40x_core` smoke harness into a small
regression for the SPHINCS descriptor accelerator control path.

The integration boundary is unchanged:

- real `cv32e40x_core`
- real CV32E40X CV-X-IF issue, commit, and result channels
- `custom-0` bare-metal SPX instructions
- `spx_cvxif_real_adapter`
- `spx_cvxif_desc_adapter`
- `spx_descriptor_adapter`
- `spx_thashx4_core`
- descriptor-side memory path only for bulk data

This phase still does not instantiate a full SoC, AXI, AHB, APB, X-HEEP, or
`core-v-verif`. Keccak, thash, `spx_thashx4_core`,
`spx_descriptor_adapter`, and `spx_cvxif_real_adapter` semantics are unchanged.

## Golden Vectors

The core-level smoke program now runs a table-driven mini regression:

| Shape | Cases |
| --- | ---: |
| `inblocks=1` | 8 |
| `inblocks=2` | 8 |
| Total descriptors | 16 |

The vectors are loaded by the testbench from the existing generated files:

```text
sim/vectors/thashx4_inblocks1.hex
sim/vectors/thashx4_inblocks2.hex
sim/vectors/thashx4_expected.hex
```

The testbench writes the selected vectors into a fixed bare-metal table at
`0x00008000`. The C program reads that table, loops over the descriptors, and
checks all four output lanes (`out0` to `out3`) for every case. Any mismatch or
unexpected status error writes `0x0000dead` to the smoke magic word. Full
success writes `0x00000001`.

## Memory Wait States

The descriptor-side memory bus model now supports:

| Mode | Read latency | Write latency | Request ready |
| --- | ---: | ---: | ---: |
| zero wait | 0 | 0 | 100% |
| wait1 | 1 | 1 | 100% |
| wait2 | 2 | 2 | 100% |
| split | 2 | 4 | 100% |
| random50 | 0 | 0 | 50% |
| random75 | 0 | 0 | 75% |

These stalls sit behind `spx_mem_master_shim_mock` on the descriptor-side path.
The CV-X-IF memory channel remains unused; the testbench still fatals if
`xif.mem_valid` is asserted.

## Error-Path Smoke

A separate bare-metal program covers descriptor error status propagation:

```text
sw/tests/spx_cvxif_error_smoke.c
```

It checks at least these cases through `SPX_STATUS`:

| Case | Expected code |
| --- | ---: |
| invalid descriptor config, `inblocks=3` | `ERR_BAD_CONFIG = 0x1` |
| unaligned descriptor address | `ERR_BAD_ALIGN = 0x2` |
| memory read error | `ERR_MEM_READ = 0x3` |
| memory write error | `ERR_MEM_WRITE = 0x4` |

The error-path program writes a distinct PASS magic, `0x0000e55e`, so the
testbench prints `PASS cv32e40x_spx_core_smoke_error`.

## Commands

Build and run the normal core smoke:

```sh
make -C sim sim-cv32e40x-core-smoke
```

Run fixed wait-state smoke:

```sh
make -C sim sim-cv32e40x-core-smoke-wait1
make -C sim sim-cv32e40x-core-smoke-wait2
```

Run the full Phase 3.8 core smoke matrix:

```sh
make -C sim sim-cv32e40x-core-smoke-regress
```

Run error-path smoke:

```sh
make -C sim sim-cv32e40x-core-smoke-error
```

Run the full simulator test suite, now including the core smoke regression:

```sh
make -C sim test
```

## Results

Observed Phase 3.8 core smoke results:

| Target mode | PASS | cases_passed | error_cases_passed | status_poll_count | cycles |
| --- | --- | ---: | ---: | ---: | ---: |
| zero wait | normal | 16 | 0 | 80 | 14688 |
| wait1 | normal | 16 | 0 | 120 | 15128 |
| wait2 | normal | 16 | 0 | 152 | 15480 |
| split read2/write4 | normal | 16 | 0 | 168 | 15656 |
| random ready 50% | normal | 16 | 0 | 115 | 15073 |
| random ready 75% | normal | 16 | 0 | 93 | 14831 |
| error smoke | error-path | 0 | 4 | 8 | 3270 |

Regression commands completed:

```text
make -C sim lint
make -C sim test
```

`make -C sim test` now includes `sim-cv32e40x-core-smoke-regress`.

The zero-wait normal smoke printed:

```text
PASS cv32e40x_spx_core_smoke read_latency=0 write_latency=0 req_ready_pct=100 cycles=14688 instr_fetch=11495 data_rd=1700 data_wr=1676 xif_issue=144 xif_accept=144 xif_result=144 desc_ctrl=144 bus_rd=272 bus_wr=80 perf_load=19 perf_core=27 perf_store=5 perf_total=54 cases_passed=16 cases_failed=0 status_poll_count=80 error_cases_passed=0
```

The error-path smoke printed:

```text
PASS cv32e40x_spx_core_smoke_error read_latency=0 write_latency=0 req_ready_pct=100 cycles=3270 instr_fetch=2751 data_rd=20 data_wr=446 xif_issue=24 xif_accept=24 xif_result=24 desc_ctrl=24 bus_rd=18 bus_wr=5 perf_load=15 perf_core=27 perf_store=2 perf_total=47 cases_passed=0 cases_failed=0 status_poll_count=8 error_cases_passed=4
```

## Counters

The testbench continues to print:

```text
cycles
instr_fetch
data_rd
data_wr
xif_issue
xif_accept
xif_result
desc_ctrl
bus_rd
bus_wr
perf_load
perf_core
perf_store
perf_total
```

Phase 3.8 adds:

```text
cases_passed
cases_failed
status_poll_count
error_cases_passed
```

The C programs publish those counters through a tiny smoke stats block at
`0x0000ffe0`.

## Current Limits

- The harness is still a smoke/regression test, not a full CV32E40X
  verification environment.
- Instruction and data memory remain simple always-grant one-cycle memories.
- Wait states and request backpressure are modeled only on the descriptor-side
  memory path.
- Random ready modes use a deterministic xorshift generator, not constrained
  random verification.
- Error injection is one-shot and targeted at descriptor memory read/write
  response errors.
- No cache, coherency, interrupt, debug, PMP/PMA, atomics, or full bus fabric
  behavior is modeled.
- Verilator uses `-Wno-fatal` for the core smoke because standalone third-party
  CV32E40X RTL emits known warnings such as missing timescales and unoptimized
  combinational logic.

## Recommendation

Phase 3.8 makes the core-level smoke stable enough to keep in regression. It is
reasonable to proceed to Phase 3.9 if the next step is deeper core-side
observability, or to Phase 4 if the next milestone is a larger system
integration boundary. The accelerator datapath and CV-X-IF bulk-data exclusion
remain intact.
