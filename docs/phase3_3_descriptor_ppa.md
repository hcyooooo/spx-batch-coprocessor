# Phase 3.3 Descriptor Adapter OOC Vivado PPA

This phase keeps the design as a standalone accelerator-only Vivado
out-of-context target. It does not connect CV32E40PX, CV-X-IF, AXI, AHB, APB,
or any SoC fabric, and it does not change Keccak, thash, or
`spx_thashx4_core` semantics.

## Scope

Top module:

```text
spx_descriptor_adapter
```

RTL included in the Vivado OOC build:

```text
rtl/common/spx_thashx4_pkg.sv
rtl/core/spx_keccak_round.sv
rtl/core/spx_keccakx4_core.sv
rtl/core/spx_thashx4_core.sv
rtl/cvxif/spx_descriptor_adapter.sv
```

The descriptor adapter is synthesized in three memory-side width
configurations:

| Config | `MEM_WORDS_PER_CYCLE` | Memory-side data width |
| --- | ---: | ---: |
| `descriptor_1w` | 1 | 32 bits |
| `descriptor_2w` | 2 | 64 bits |
| `descriptor_4w` | 4 | 128 bits |

## Vivado Commands

Default FPGA part:

```text
xc7a35tcpg236-1
```

Target clock:

```text
10.0 ns
```

Windows Vivado host:

```bat
cd synth\fpga
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 1
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 2
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 4
```

The generic `run_vivado.bat` helper also accepts the fourth argument:

```bat
run_vivado.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 4
```

Linux or Git Bash with Vivado in `PATH`:

```sh
make -C synth/fpga synth-descriptor-adapter-1w PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
make -C synth/fpga synth-descriptor-adapter-2w PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
make -C synth/fpga synth-descriptor-adapter-4w PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
```

Expected report directories:

```text
synth/fpga/build/spx_descriptor_adapter_1w/reports/
synth/fpga/build/spx_descriptor_adapter_2w/reports/
synth/fpga/build/spx_descriptor_adapter_4w/reports/
```

Each run emits:

```text
ppa_summary.txt
utilization.rpt
utilization_hier.rpt
timing_summary.rpt
```

`ppa_summary.txt` records `MEM_WORDS_PER_CYCLE`, LUT, FF, BRAM, DSP, WNS,
critical path delay, timing-met status, and estimated Fmax.

## PPA Results

Vivado host run status: pending in this workspace. The local Linux environment
used for this edit does not have Vivado in `PATH`, so the PPA values below must
be filled from the Windows host reports.

| Top/config | LUT | FF | BRAM | DSP | WNS | Fmax | inb1 cycles | inb2 cycles | thash/s inb1 | thash/s inb2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `descriptor_1w` | TBD | TBD | TBD | TBD | TBD | TBD | 107 | 123 | `Fmax_MHz * 0.037383 M` | `Fmax_MHz * 0.032520 M` |
| `descriptor_2w` | TBD | TBD | TBD | TBD | TBD | TBD | 69 | 77 | `Fmax_MHz * 0.057971 M` | `Fmax_MHz * 0.051948 M` |
| `descriptor_4w` | TBD | TBD | TBD | TBD | TBD | TBD | 50 | 54 | `Fmax_MHz * 0.080000 M` | `Fmax_MHz * 0.074074 M` |

## Throughput Method

Each descriptor operation returns four thash outputs.

```text
equiv_thash_per_second = Fmax_MHz * 1e6 * 4 / total_cycles
cycles_per_thash_equiv = total_cycles / 4
```

| Config | `inblocks` | Total cycles | Cycles/thash equiv | Mthash/s per MHz |
| --- | ---: | ---: | ---: | ---: |
| `descriptor_1w` | 1 | 107 | 26.75 | 0.037383 |
| `descriptor_1w` | 2 | 123 | 30.75 | 0.032520 |
| `descriptor_2w` | 1 | 69 | 17.25 | 0.057971 |
| `descriptor_2w` | 2 | 77 | 19.25 | 0.051948 |
| `descriptor_4w` | 1 | 50 | 12.50 | 0.080000 |
| `descriptor_4w` | 2 | 54 | 13.50 | 0.074074 |

## Baseline Area

Known routed accelerator-only baselines on `xc7a35tcpg236-1` with a 10.0 ns
target:

| Top | LUT | FF | BRAM | DSP | Fmax |
| --- | ---: | ---: | ---: | ---: | ---: |
| `spx_thashx4_core` | 11797 | 9105 | 0 | 0 | 116.58 MHz |
| `spx_cop_wrapper` | 13473 | 11835 | 0 | 0 | 116.93 MHz |

Descriptor adapter area deltas should be computed against both baselines after
the three Vivado reports are available:

```text
delta_vs_core = descriptor_metric - spx_thashx4_core_metric
delta_vs_wrapper = descriptor_metric - spx_cop_wrapper_metric
```

## Phase 3.4 Recommendation Criteria

The Phase 3.2 latency data strongly favors wider memory-side movement:

| Config | `inblocks=1` speedup vs 1w | `inblocks=2` speedup vs 1w |
| --- | ---: | ---: |
| `descriptor_2w` | 1.55x | 1.60x |
| `descriptor_4w` | 2.14x | 2.28x |

Use `descriptor_4w` for Phase 3.4 if it still meets timing and its LUT/FF
increase is acceptable, because it gives the best throughput per operation and
keeps the core active for about half of the operation. If `descriptor_4w` fails
timing or has a disproportionate area cost, use `descriptor_2w` as the
integration compromise. `descriptor_1w` is the lowest-risk fallback but is not
the preferred performance path.
