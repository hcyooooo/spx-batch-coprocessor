# Phase 4.2 WOTS-Chain Hardening and PPA Refresh

Phase 4.2 hardens the Phase 4.1 `WOTS_CHAINX4` descriptor integration with
core-level wait-state, backpressure, and error-path smoke coverage. It also
updates the Vivado OOC flow so `spx_descriptor_adapter` synthesis includes both
the original `spx_thashx4_core` path and the new `spx_wots_chainx4_core` path.

This phase still does not connect a full SoC, AXI, AHB, APB, X-HEEP, or a full
WOTS public-key engine. CV-X-IF remains control/status only; bulk data stays on
the descriptor-side memory path.

## Commands

WOTS wait-state/backpressure regression:

```sh
make -C sim sim-cv32e40x-wots-chain-smoke-regress
```

WOTS error-path smoke:

```sh
make -C sim sim-cv32e40x-wots-chain-error
```

Descriptor adapter OOC PPA flow:

```sh
make -C synth/fpga synth-descriptor-adapter-4w PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
make -C synth/fpga synth-descriptor-adapter-2w PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
make -C synth/fpga synth-descriptor-adapter-1w PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
```

The Linux environment used for this update has Verilator and the RISC-V GCC
toolchain, but no `vivado` executable. The PPA flow is wired, but the actual
LUT/FF/timing refresh must be run on the Windows Vivado host.

## Wait-State Results

The WOTS smoke runs the generated vector cases with:

| `num_steps` | `start_step` |
| ---: | ---: |
| 1 | 14 |
| 2 | 9 |
| 4 | 5 |
| 8 | 3 |
| 15 | 0 |

All four output lanes are compared against the vector table for every case. The
testbench still fails if `xif.mem_valid` is asserted.

Observed target result:

```text
make -C sim sim-cv32e40x-wots-chain-smoke-regress
PASS all 6 WOTS modes
```

Final smoke counters:

| Mode | cycles | cases_passed | cases_failed | status_poll_count | xif_issue | xif_accept | xif_result | bus_rd | bus_wr | perf_load | perf_core | perf_store | perf_total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| zero_wait | 4353 | 5 | 0 | 90 | 110 | 110 | 110 | 75 | 25 | 15 | 421 | 5 | 444 |
| wait1 | 4463 | 5 | 0 | 100 | 120 | 120 | 120 | 75 | 25 | 30 | 421 | 10 | 464 |
| wait2 | 4573 | 5 | 0 | 110 | 130 | 130 | 130 | 75 | 25 | 45 | 421 | 15 | 484 |
| split_read2_write4 | 4617 | 5 | 0 | 114 | 134 | 134 | 134 | 75 | 25 | 45 | 421 | 25 | 494 |
| random_ready50 | 4430 | 5 | 0 | 97 | 117 | 117 | 117 | 75 | 25 | 32 | 421 | 8 | 464 |
| random_ready75 | 4386 | 5 | 0 | 93 | 113 | 113 | 113 | 75 | 25 | 19 | 421 | 6 | 449 |

The `perf_*` values in the final PASS line are the descriptor adapter counters
for the last WOTS case, `num_steps=15`. Per-case `CASE_PERF` and
`WOTS_CHAIN_CORE_PERF` lines are printed for every vector case.

## Performance Benefit

The baseline is repeated `THASHX4 inblocks=1` descriptors under the same memory
mode. For deterministic random-ready modes, the baseline per-step values are
averages across the existing Phase 3.9 `inblocks=1` cases.

| Mode | Baseline cycles per step | Baseline XIF per step | Baseline bus_rd/bus_wr per step |
| --- | ---: | ---: | ---: |
| zero_wait | 57.00 | 9.00 | 15 / 5 |
| wait1 | 79.00 | 11.00 | 15 / 5 |
| wait2 | 101.00 | 13.00 | 15 / 5 |
| split_read2_write4 | 112.00 | 14.00 | 15 / 5 |
| random_ready50 | 77.62 | 10.88 | 15 / 5 |
| random_ready75 | 63.88 | 9.62 | 15 / 5 |

| num_steps | mode | baseline cycles | WOTS cycles | speedup | xif instr reduction | bus_rd reduction | bus_wr reduction |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | zero_wait | 57.00 | 55.00 | 1.04x | 0.00 | 0 | 0 |
| 2 | zero_wait | 114.00 | 88.00 | 1.30x | 6.00 | 15 | 5 |
| 4 | zero_wait | 228.00 | 143.00 | 1.59x | 19.00 | 45 | 15 |
| 8 | zero_wait | 456.00 | 253.00 | 1.80x | 45.00 | 105 | 35 |
| 15 | zero_wait | 855.00 | 451.00 | 1.90x | 90.00 | 210 | 70 |
| 1 | wait1 | 79.00 | 77.00 | 1.03x | 0.00 | 0 | 0 |
| 2 | wait1 | 158.00 | 110.00 | 1.44x | 8.00 | 15 | 5 |
| 4 | wait1 | 316.00 | 165.00 | 1.92x | 25.00 | 45 | 15 |
| 8 | wait1 | 632.00 | 275.00 | 2.30x | 59.00 | 105 | 35 |
| 15 | wait1 | 1185.00 | 473.00 | 2.51x | 118.00 | 210 | 70 |
| 1 | wait2 | 101.00 | 99.00 | 1.02x | 0.00 | 0 | 0 |
| 2 | wait2 | 202.00 | 132.00 | 1.53x | 10.00 | 15 | 5 |
| 4 | wait2 | 404.00 | 187.00 | 2.16x | 31.00 | 45 | 15 |
| 8 | wait2 | 808.00 | 297.00 | 2.72x | 73.00 | 105 | 35 |
| 15 | wait2 | 1515.00 | 495.00 | 3.06x | 146.00 | 210 | 70 |
| 1 | split_read2_write4 | 112.00 | 110.00 | 1.02x | 0.00 | 0 | 0 |
| 2 | split_read2_write4 | 224.00 | 132.00 | 1.70x | 12.00 | 15 | 5 |
| 4 | split_read2_write4 | 448.00 | 198.00 | 2.26x | 34.00 | 45 | 15 |
| 8 | split_read2_write4 | 896.00 | 308.00 | 2.91x | 80.00 | 105 | 35 |
| 15 | split_read2_write4 | 1680.00 | 506.00 | 3.32x | 160.00 | 210 | 70 |
| 1 | random_ready50 | 77.62 | 77.00 | 1.01x | -0.12 | 0 | 0 |
| 2 | random_ready50 | 155.24 | 99.00 | 1.57x | 8.76 | 15 | 5 |
| 4 | random_ready50 | 310.48 | 154.00 | 2.02x | 25.52 | 45 | 15 |
| 8 | random_ready50 | 620.96 | 264.00 | 2.35x | 59.04 | 105 | 35 |
| 15 | random_ready50 | 1164.30 | 473.00 | 2.46x | 116.20 | 210 | 70 |
| 1 | random_ready75 | 63.88 | 66.00 | 0.97x | -0.38 | 0 | 0 |
| 2 | random_ready75 | 127.76 | 99.00 | 1.29x | 6.24 | 15 | 5 |
| 4 | random_ready75 | 255.52 | 154.00 | 1.66x | 20.48 | 45 | 15 |
| 8 | random_ready75 | 511.04 | 253.00 | 2.02x | 49.96 | 105 | 35 |
| 15 | random_ready75 | 958.20 | 451.00 | 2.12x | 99.30 | 210 | 70 |

For `num_steps=1`, the WOTS descriptor is intentionally close to a normal
single-step descriptor; the value of `WOTS_CHAINX4` appears as the descriptor
envelope is amortized across multiple chain steps. Wait-state modes amplify the
benefit because repeated descriptor loads/stores and repeated polling are
avoided.

Compared with Phase 4.1 zero-wait, the zero-wait values are unchanged:
`num_steps=15` remains 451 core-visible cycles versus an 855-cycle repeated
descriptor baseline, or 1.90x speedup.

## Error-Path Results

New bare-metal program:

```text
sw/tests/spx_cvxif_wots_chain_error_smoke.c
```

It checks the error bit and error code through `SPX_STATUS`, then checks the
descriptor status writeback word at the descriptor address. A distinct PASS
magic, `0x0000e42e`, is used for WOTS error-path success.

Covered cases:

| Case | Expected code |
| --- | ---: |
| bad op_type | `ERR_BAD_OP_TYPE = 0x5` |
| `num_steps = 0` | `ERR_BAD_CHAIN = 0x6` |
| `num_steps = 16` | `ERR_BAD_CHAIN = 0x6` |
| `start_step + num_steps > 16` | `ERR_BAD_CHAIN = 0x6` |
| unaligned descriptor | `ERR_BAD_ALIGN = 0x2` |
| memory read error | `ERR_MEM_READ = 0x3` |
| memory write error | `ERR_MEM_WRITE = 0x4` |

Observed result:

```text
PASS cv32e40x_spx_wots_chain_error mode=wots_chain_error ... error_cases_passed=7
```

Final counters:

| cycles | cases_passed | cases_failed | status_poll_count | xif_issue | xif_accept | xif_result | bus_rd | bus_wr | perf_load | perf_core | perf_store | perf_total | error_cases_passed |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4939 | 0 | 0 | 11 | 39 | 39 | 39 | 24 | 8 | 15 | 29 | 2 | 49 | 7 |

## PPA Refresh

The OOC script now includes `rtl/core/spx_wots_chainx4_core.sv` whenever the top
is `spx_descriptor_adapter`. This means the synthesized descriptor adapter
includes:

- `THASHX4` descriptor path;
- `WOTS_CHAINX4` descriptor path;
- op-type mux/control;
- shared descriptor memory load/store and status writeback logic.

Current local status:

| Top/config | LUT | FF | BRAM | DSP | WNS | Fmax | delta vs Phase3.3 descriptor_4w |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Phase 3.3 `descriptor_4w` baseline | 14801 | 11870 | 0 | 0 | 0.323 ns | 103.34 MHz | baseline |
| Phase 4.2 `spx_descriptor_adapter`, `MEM_WORDS_PER_CYCLE=4` | TBD | TBD | TBD | TBD | TBD | TBD | TBD, requires Windows Vivado host run |
| Phase 4.2 `spx_descriptor_adapter`, `MEM_WORDS_PER_CYCLE=2` | TBD | TBD | TBD | TBD | TBD | TBD | optional host run |
| Phase 4.2 `spx_descriptor_adapter`, `MEM_WORDS_PER_CYCLE=1` | TBD | TBD | TBD | TBD | TBD | TBD | optional host run |

The required host command for the main comparison is:

```sh
make -C synth/fpga synth-descriptor-adapter-4w PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
```

Expected summary file after the host run:

```text
synth/fpga/build/spx_descriptor_adapter_4w/reports/ppa_summary.txt
```

## Recommendation

Phase 4.2 is worth carrying into Phase 4.3, with one condition: refresh the
descriptor adapter PPA on the Vivado host first. Functionally, the WOTS path is
now hardened across fixed wait states, split read/write latency, deterministic
random backpressure, and the WOTS-specific error cases.

The performance case is strongest for medium and long chains. `num_steps=15`
improves from 1.90x in zero-wait mode to 3.32x under split read2/write4 when
compared against descriptor-at-a-time scheduling in the same memory mode.

Phase 4.3 should focus on lane divergence and mixed-length WOTS verify chains,
not on a full WOTS public-key engine yet. The current fixed-length
`WOTS_CHAINX4` path has earned the next experiment; the missing question is how
much of that benefit survives when verification chain lengths diverge by lane.
