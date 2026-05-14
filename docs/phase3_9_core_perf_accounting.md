# Phase 3.9 CV32E40X Core Performance Accounting

Phase 3.9 keeps the Phase 3.8 core-level smoke boundary and adds monitor-side
performance accounting for the descriptor control path.

The integration boundary is unchanged:

- real `cv32e40x_core`
- real CV32E40X CV-X-IF issue, commit, and result channels
- `spx_cvxif_real_adapter`
- `spx_cvxif_desc_adapter`
- `spx_descriptor_adapter`
- `spx_thashx4_core`
- descriptor-side memory path for bulk data

This phase still does not instantiate a full SoC, AXI, AHB, APB, X-HEEP, or
`core-v-verif`. Keccak, thash, `spx_thashx4_core`,
`spx_descriptor_adapter`, and `spx_cvxif_real_adapter` semantics are unchanged.
CV-X-IF remains a control path only; the testbench still fails if
`xif.mem_valid` is asserted.

## Statistics

The core smoke testbench now prints one `CASE_PERF` line per descriptor:

```text
CASE_PERF id=0 inblocks=1 start_cycle=655 done_cycle=712 cycles=57 polls=5 xif=9 bus_rd=15 bus_wr=5 load=15 core=27 store=5 total=50 pass=1
```

The fields are:

| Field | Meaning |
| --- | --- |
| `id` | Testbench descriptor sequence number |
| `inblocks` | Descriptor `config[1:0]` sampled at `SPX_START` |
| `start_cycle` | Cycle when `desc_start` is accepted |
| `done_cycle` | Cycle of the first `SPX_STATUS` result with done/error set |
| `cycles` | `done_cycle - start_cycle`, including polling visibility delay |
| `polls` | Accepted `SPX_STATUS` instructions for the descriptor |
| `xif` | Accepted CV-X-IF control instructions in the descriptor window |
| `bus_rd`, `bus_wr` | Descriptor-side memory bus accepted reads/writes |
| `load`, `core`, `store`, `total` | `spx_descriptor_adapter` perf counters |
| `pass` | Done status without descriptor error |

The descriptor window starts at the pre-descriptor `SPX_CLEAR` and ends at the
post-done `SPX_CLEAR`, so `xif` includes the full software control sequence:
`clear`, `set_desc`, `start`, all `status` polls, and final `clear`.

The testbench also prints:

- `POLL_PERF`, with status count, start-to-done-status cycles, polling share of
  XIF control instructions, and estimated control-instruction savings for a
  future wait/interrupt path.
- `XIF_LATENCY`, split by `SPX_SET_DESC`, `SPX_START`, `SPX_STATUS`, and
  `SPX_CLEAR`.
- `CORE_SMOKE_PERF_SUMMARY`, one line per normal smoke mode.

## Per-Case Results

Observed zero-wait normal smoke results:

| Case ids | inblocks | cycles | polls | xif | bus_rd | bus_wr | load | core | store | perf_total | pass |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0-7 | 1 | 57 | 5 | 9 | 15 | 5 | 15 | 27 | 5 | 50 | 1 |
| 8-15 | 2 | 57 | 5 | 9 | 19 | 5 | 19 | 27 | 5 | 54 | 1 |

Representative lines:

```text
CASE_PERF id=0 inblocks=1 start_cycle=655 done_cycle=712 cycles=57 polls=5 xif=9 bus_rd=15 bus_wr=5 load=15 core=27 store=5 total=50 pass=1
CASE_PERF id=8 inblocks=2 start_cycle=7498 done_cycle=7555 cycles=57 polls=5 xif=9 bus_rd=19 bus_wr=5 load=19 core=27 store=5 total=54 pass=1
CASE_PERF id=15 inblocks=2 start_cycle=14463 done_cycle=14520 cycles=57 polls=5 xif=9 bus_rd=19 bus_wr=5 load=19 core=27 store=5 total=54 pass=1
```

Error-path smoke also emits `CASE_PERF`, but those descriptor statuses are
expected to report errors and therefore print `pass=0`. The error smoke still
passes via `MAGIC_ERROR_PASS`.

## XIF Latency

Zero-wait XIF latency is stable across all four control instruction classes:

| Type | Count | issue->commit min/max/avg | commit->result min/max/avg | issue->result min/max/avg |
| --- | ---: | --- | --- | --- |
| `SPX_SET_DESC` | 16 | 1 / 1 / 1.00 | 2 / 2 / 2.00 | 3 / 3 / 3.00 |
| `SPX_START` | 16 | 1 / 1 / 1.00 | 2 / 2 / 2.00 | 3 / 3 / 3.00 |
| `SPX_STATUS` | 80 | 1 / 1 / 1.00 | 2 / 2 / 2.00 | 3 / 3 / 3.00 |
| `SPX_CLEAR` | 32 | 1 / 1 / 1.00 | 2 / 2 / 2.00 | 3 / 3 / 3.00 |

The wait-state modes change descriptor completion time and polling count, not
the CV-X-IF instruction pipeline latency. For example, `SPX_STATUS` count
increases from 80 in zero wait to 168 in split read2/write4, but each accepted
status instruction still has issue-to-result latency of 3 cycles.

## Polling Overhead

Zero-wait polling:

```text
POLL_PERF id=0 status=5 start_to_done_cycles=57 poll_instr_pct=55.6 wait_saved_instr=4 irq_saved_instr=5
```

Each successful zero-wait descriptor uses 9 accepted XIF instructions:

| Instruction group | Count per case |
| --- | ---: |
| `SPX_CLEAR` before case | 1 |
| `SPX_SET_DESC` | 1 |
| `SPX_START` | 1 |
| `SPX_STATUS` | 5 |
| `SPX_CLEAR` after done | 1 |

So 5 of 9 control instructions, or 55.6%, are polling. A future blocking
`SPX_WAIT`-like path would reduce the repeated status sequence by about
4 control instructions per zero-wait descriptor. A future interrupt/completion
event that removes status polling entirely would reduce about 5 control
instructions per zero-wait descriptor.

Polling grows as descriptor memory latency grows:

| Mode | Avg status polls | Avg XIF instr | Polling share | Avg wait-saved instr | Avg irq-saved instr |
| --- | ---: | ---: | ---: | ---: | ---: |
| zero_wait | 5.00 | 9.00 | 55.6% | 4.00 | 5.00 |
| wait1 | 7.50 | 11.50 | 65.2% | 6.50 | 7.50 |
| wait2 | 9.50 | 13.50 | 70.4% | 8.50 | 9.50 |
| split | 10.50 | 14.50 | 72.4% | 9.50 | 10.50 |
| random50 | 7.19 | 11.19 | 64.2% | 6.19 | 7.19 |
| random75 | 5.81 | 9.81 | 59.2% | 4.81 | 5.81 |

## Wait-State Impact

Regression summary:

| Mode | Cases | Avg cycles/case | Avg polls | Avg XIF | Avg bus_rd | Avg bus_wr | Avg perf_total | Cycles/thash equiv |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| zero_wait | 16 | 57.00 | 5.00 | 9.00 | 17.00 | 5.00 | 52.00 | 14.25 |
| wait1 | 16 | 84.50 | 7.50 | 11.50 | 17.00 | 5.00 | 74.00 | 21.12 |
| wait2 | 16 | 106.50 | 9.50 | 13.50 | 17.00 | 5.00 | 96.00 | 26.62 |
| split | 16 | 117.50 | 10.50 | 14.50 | 17.00 | 5.00 | 106.00 | 29.38 |
| random50 | 16 | 81.06 | 7.19 | 11.19 | 17.00 | 5.00 | 74.44 | 20.27 |
| random75 | 16 | 65.94 | 5.81 | 9.81 | 17.00 | 5.00 | 59.31 | 16.48 |

The bus transaction count is stable because the descriptor algorithm and memory
layout are unchanged. Wait states inflate `perf_load`, `perf_store`, and the
number of status polls needed before software observes done.

## Descriptor-Thashx4 Baseline

Current zero-wait descriptor baseline:

| Shape | Descriptor perf_total | Bus reads | Bus writes | Wall cycles to done status |
| --- | ---: | ---: | ---: | ---: |
| `inblocks=1` | 50 | 15 | 5 | 57 |
| `inblocks=2` | 54 | 19 | 5 | 57 |

Each descriptor computes four thash lanes, so the zero-wait wall-clock baseline
is `57 / 4 = 14.25` cycles per thash-equivalent output at the core smoke
boundary. The descriptor adapter baseline is `50 / 4 = 12.50` cycles per
thash-equivalent for `inblocks=1` and `54 / 4 = 13.50` for `inblocks=2`.

The difference between wall cycles and descriptor `perf_total` is control-path
visibility: CV-X-IF instruction latency, software polling cadence, and the
status observation point.

## Assertions and Checks

The testbench now checks:

- every accepted CV-X-IF instruction must commit and produce a result within
  `XIF_RESULT_TIMEOUT_CYCLES`;
- every descriptor start must reach done/error within
  `DESC_DONE_TIMEOUT_CYCLES`;
- `xif.mem_valid` must remain zero;
- final XIF issue/accept/result counts must match at PASS;
- key descriptor, XIF issue, commit, and result signals must not contain
  unknown X/Z values when valid.

These checks are intentionally testbench-side monitors; they do not modify the
accelerator datapath or software algorithm.

## Phase 4 Implication

The numbers point toward moving the WOTS chain loop below the per-descriptor
software polling boundary.

Today each thashx4 descriptor pays a fixed software control envelope:
`clear`, `set_desc`, `start`, repeated `status`, and final `clear`. In zero
wait, polling alone is 55.6% of XIF control instructions. In split read2/write4,
polling rises to 72.4% of XIF control instructions. A WOTS chain contains many
repeated thash steps, so this envelope would be paid again and again if Phase 4
keeps scheduling one descriptor at a time from software.

A hardware WOTS chain scheduler can keep bulk data on the descriptor-side memory
path while reducing repeated control traffic. It can amortize descriptor setup,
avoid most status polling, and schedule back-to-back thashx4 work closer to the
accelerator. That is the useful next baseline to compare against, before any
full SoC or bus-fabric integration.

## Commands

The Phase 3.9 commands are:

```sh
make -C sim sim-cv32e40x-core-perf
make -C sim sim-cv32e40x-core-smoke-regress
make -C sim test
```

`sim-cv32e40x-core-perf` currently aliases the zero-wait normal smoke target and
prints the per-case, XIF latency, polling, and summary accounting.

Observed regression command:

```text
make -C sim sim-cv32e40x-core-smoke-regress
make -C sim test
```

All six normal wait/backpressure modes, the error-path smoke, and the full
simulator test suite passed.

## Next Steps

- Add a Phase 4 WOTS-chain micro-scheduler target that consumes the same
  descriptor-side memory model and emits comparable `CASE_PERF`-style counters.
- Keep CV-X-IF as a control/status interface; do not move bulk WOTS data through
  CV-X-IF.
- Compare descriptor-at-a-time scheduling against WOTS-chain scheduling using
  cycles per thash-equivalent, status/control instruction count, and memory bus
  reads/writes.
- Consider a blocking wait or interrupt-style completion path if software keeps
  issuing standalone descriptors.
