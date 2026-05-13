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

Vivado host run status: complete on Windows with Vivado 2020.2. The reported
Fmax is estimated from the routed critical path delay in each OOC run.

| Top/config | LUT | FF | BRAM | DSP | WNS | Fmax | inb1 cycles | inb2 cycles | thash/s inb1 | thash/s inb2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `descriptor_1w` | 13565 | 11853 | 0 | 0 | 0.711 ns | 107.65 MHz | 107 | 123 | 4.02 Mthash/s | 3.50 Mthash/s |
| `descriptor_2w` | 14090 | 11858 | 0 | 0 | 0.672 ns | 107.20 MHz | 69 | 77 | 6.21 Mthash/s | 5.57 Mthash/s |
| `descriptor_4w` | 14801 | 11870 | 0 | 0 | 0.323 ns | 103.34 MHz | 50 | 54 | 8.27 Mthash/s | 7.65 Mthash/s |

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

Descriptor adapter area deltas are computed against both baselines in the
Vivado host result below:

```text
delta_vs_core = descriptor_metric - spx_thashx4_core_metric
delta_vs_wrapper = descriptor_metric - spx_cop_wrapper_metric
```

## Vivado Host PPA Result

Windows Vivado environment:

```text
Vivado v2020.2 (64-bit)
D:\Vivado\2020.2\bin\vivado.bat
```

Commands run from `synth\fpga`:

```bat
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 1
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 2
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 4
```

Generated report roots:

```text
synth/fpga/build/spx_descriptor_adapter_1w/reports/
synth/fpga/build/spx_descriptor_adapter_2w/reports/
synth/fpga/build/spx_descriptor_adapter_4w/reports/
```

All three configurations meet the 10.0 ns target.

| Config | `MEM_WORDS_PER_CYCLE` | Part | Target | LUT | FF | BRAM | DSP | WNS | Critical delay | Fmax | Timing |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `descriptor_1w` | 1 | `xc7a35tcpg236-1` | 10.0 ns | 13565 | 11853 | 0 | 0 | 0.711 ns | 9.289 ns | 107.65 MHz | PASS |
| `descriptor_2w` | 2 | `xc7a35tcpg236-1` | 10.0 ns | 14090 | 11858 | 0 | 0 | 0.672 ns | 9.328 ns | 107.20 MHz | PASS |
| `descriptor_4w` | 4 | `xc7a35tcpg236-1` | 10.0 ns | 14801 | 11870 | 0 | 0 | 0.323 ns | 9.677 ns | 103.34 MHz | PASS |

Equivalent throughput using the Phase 3.2 descriptor latency:

| Config | `inblocks` | Total cycles | Cycles/thash equiv | Fmax | Equivalent throughput |
| --- | ---: | ---: | ---: | ---: | ---: |
| `descriptor_1w` | 1 | 107 | 26.75 | 107.65 MHz | 4.02 Mthash/s |
| `descriptor_1w` | 2 | 123 | 30.75 | 107.65 MHz | 3.50 Mthash/s |
| `descriptor_2w` | 1 | 69 | 17.25 | 107.20 MHz | 6.21 Mthash/s |
| `descriptor_2w` | 2 | 77 | 19.25 | 107.20 MHz | 5.57 Mthash/s |
| `descriptor_4w` | 1 | 50 | 12.50 | 103.34 MHz | 8.27 Mthash/s |
| `descriptor_4w` | 2 | 54 | 13.50 | 103.34 MHz | 7.65 Mthash/s |

Area and Fmax deltas against the routed baselines:

| Config | Baseline | LUT delta | FF delta | Fmax delta |
| --- | --- | ---: | ---: | ---: |
| `descriptor_1w` | `spx_thashx4_core` | +1768 | +2748 | -8.93 MHz |
| `descriptor_1w` | `spx_cop_wrapper` | +92 | +18 | -9.28 MHz |
| `descriptor_2w` | `spx_thashx4_core` | +2293 | +2753 | -9.38 MHz |
| `descriptor_2w` | `spx_cop_wrapper` | +617 | +23 | -9.73 MHz |
| `descriptor_4w` | `spx_thashx4_core` | +3004 | +2765 | -13.24 MHz |
| `descriptor_4w` | `spx_cop_wrapper` | +1328 | +35 | -13.59 MHz |

`descriptor_4w` has the best throughput and best throughput per LUT in both
latency cases despite its lower Fmax. Its area cost versus `descriptor_2w` is
+711 LUT and +12 FF, while inblocks=1 throughput improves from 6.21 Mthash/s
to 8.27 Mthash/s and inblocks=2 throughput improves from 5.57 Mthash/s to
7.65 Mthash/s. Phase 3.4 should use the 4w / 128-bit memory-side path if the
next integration boundary can provide that width. Use 2w / 64-bit as the
fallback if the wider memory-side path is too costly or awkward to integrate.

## Phase 3.4 Recommendation Criteria

The Phase 3.2 latency data strongly favors wider memory-side movement:

| Config | `inblocks=1` speedup vs 1w | `inblocks=2` speedup vs 1w |
| --- | ---: | ---: |
| `descriptor_2w` | 1.55x | 1.60x |
| `descriptor_4w` | 2.14x | 2.28x |

Use `descriptor_4w` for Phase 3.4 because it meets timing and gives the best
throughput per operation while keeping the core active for about half of the
operation. If the 128-bit memory-side path is too costly at the next integration
boundary, use `descriptor_2w` as the 64-bit compromise. `descriptor_1w` is the
lowest-risk fallback but is not the preferred performance path.
