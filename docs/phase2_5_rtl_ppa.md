# Phase 2.5 RTL Lint, Latency, and Accelerator-Only PPA

This phase keeps the design standalone. It does not connect CV32E40PX,
CV-X-IF, custom instructions, AXI/AHB/APB, or any SoC wrapper.

## Scope

RTL under test:

- `rtl/common/spx_thashx4_pkg.sv`
- `rtl/core/spx_keccak_round.sv`
- `rtl/core/spx_keccakx4_core.sv`
- `rtl/core/spx_thashx4_core.sv`

Top module for accelerator PPA:

- Primary: `spx_thashx4_core`
- Optional primitive-only top: `spx_keccakx4_core`

## Lint

Command:

```sh
make -C sim lint
```

This runs:

```sh
verilator -sv --lint-only --timing --Wall \
  --top-module spx_thashx4_core \
  rtl/common/spx_thashx4_pkg.sv \
  rtl/core/spx_keccak_round.sv \
  rtl/core/spx_keccakx4_core.sv \
  rtl/core/spx_thashx4_core.sv
```

Result on 2026-05-13:

```text
PASS rtl lint
```

Warnings addressed in this phase:

- width/truncation warning in Keccak round temporary indexes
- unused package constants
- intentional unused high bits of Keccak state after `thashx4` squeeze
- testbench latency accumulator width warnings

## Simulation and Correctness

Command:

```sh
make -C sim test
```

Result on 2026-05-13:

```text
LATENCY keccakx4_core min=25 max=25 avg=25.00 cycles
PASS keccakx4_core (128 cases)
LATENCY thashx4_core inblocks=1 min=27 max=27 avg=27.00 cycles
LATENCY thashx4_core inblocks=2 min=27 max=27 avg=27.00 cycles
PASS thashx4_core inblocks=1,2 (200 cases)
```

The Keccak test compares 128 C-generated x4 permutation vectors. The thashx4
test compares 100 `inblocks=1` vectors and 100 `inblocks=2` vectors against the
C golden model.

Latency is measured by the testbench from the issued `start` pulse to observed
`done`. This includes the start/control sampling cycle. The Keccak datapath
still performs one Keccak round per cycle.

## Latency Summary

| Core | Cases | Min | Max | Avg |
| --- | ---: | ---: | ---: | ---: |
| `spx_keccakx4_core` | 128 | 25 | 25 | 25.00 |
| `spx_thashx4_core`, `inblocks=1` | 100 | 27 | 27 | 27.00 |
| `spx_thashx4_core`, `inblocks=2` | 100 | 27 | 27 | 27.00 |

## Throughput Estimate

`spx_thashx4_core` returns four thash outputs per operation.

```text
thashx4_latency = 27 cycles
cycles_per_thash_equiv = 27 / 4 = 6.75 cycles
throughput = 4 / 27 = 0.148148 thash/cycle
```

At a routed clock frequency of `Fmax_MHz`, estimated throughput is:

```text
thash_per_second = Fmax_MHz * 1e6 * 4 / 27
                 = Fmax_MHz * 148148.15
```

## Vivado Synthesis Flow

Vivado is expected to run on the Windows host. The VM used for RTL lint and
simulation does not currently have Vivado, Yosys, or nextpnr in `PATH`.

Default FPGA part in the flow:

```text
xc7a35tcpg236-1
```

Override `PART` for the actual board/device.

Windows command prompt or PowerShell:

```bat
cd C:\path\to\spx-batch-coprocessor\synth\fpga
run_vivado.bat spx_thashx4_core xc7a35tcpg236-1 10.0
run_vivado.bat spx_keccakx4_core xc7a35tcpg236-1 10.0
```

Git Bash or Linux with Vivado in `PATH`:

```sh
make -C synth/fpga synth-thashx4 PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
make -C synth/fpga synth-keccakx4 PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
```

Report outputs:

```text
synth/fpga/build/spx_thashx4_core/reports/utilization.rpt
synth/fpga/build/spx_thashx4_core/reports/utilization_hier.rpt
synth/fpga/build/spx_thashx4_core/reports/timing_summary.rpt
synth/fpga/build/spx_thashx4_core/reports/ppa_summary.txt

synth/fpga/build/spx_keccakx4_core/reports/utilization.rpt
synth/fpga/build/spx_keccakx4_core/reports/utilization_hier.rpt
synth/fpga/build/spx_keccakx4_core/reports/timing_summary.rpt
synth/fpga/build/spx_keccakx4_core/reports/ppa_summary.txt
```

The Vivado flow uses out-of-context accelerator-only implementation. This keeps
the standalone wide RTL ports from being treated as package I/O pins while still
running synthesis, optimization, placement, routing, utilization reporting, and
timing reporting for the accelerator logic.

## Accelerator-Only PPA

Vivado PPA was run on the Windows host on 2026-05-13 with Vivado 2020.2 and a
10.0 ns target clock.

| Top | Part | LUT | FF | BRAM | DSP | WNS | Fmax | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `spx_thashx4_core` | `xc7a35tcpg236-1` | 11797 | 9105 | 0 | 0 | 1.422 ns | 116.58 MHz | PASS |
| `spx_keccakx4_core` | `xc7a35tcpg236-1` | 13578 | 6415 | 0 | 0 | 1.187 ns | 113.47 MHz | PASS optional |

The Vivado TCL emits `ppa_summary.txt` with routed WNS, critical path delay,
and estimated Fmax. LUT/FF/BRAM/DSP are in `utilization.rpt`.

## Vivado Host Run Result

Run environment:

- Date: 2026-05-13
- Host shell: Windows PowerShell
- Vivado: `D:\Vivado\2020.2\bin\vivado.bat`, Vivado v2020.2 64-bit
- FPGA part: `xc7a35tcpg236-1`
- Target clock period: 10.0 ns
- Flow mode: out-of-context accelerator-only implementation

Commands:

```bat
cd synth\fpga
run_vivado.bat spx_thashx4_core xc7a35tcpg236-1 10.0
run_vivado.bat spx_keccakx4_core xc7a35tcpg236-1 10.0
```

Result:

- `spx_thashx4_core`: PASS, timing met with WNS = 1.422 ns.
- `spx_keccakx4_core`: PASS optional, timing met with WNS = 1.187 ns.
- A first non-OOC full package implementation attempt for `spx_thashx4_core`
  failed at I/O placement because the bare standalone top exposes 2694 ports,
  while the selected `cpg236` package has 106 user I/O pins. This was a flow
  issue for standalone accelerator PPA, not an RTL semantic issue. The complete
  failure log is saved at
  `synth/fpga/build/spx_thashx4_core/reports/vivado_io_place_failure.log`.

Report paths:

```text
synth/fpga/build/spx_thashx4_core/reports/ppa_summary.txt
synth/fpga/build/spx_thashx4_core/reports/utilization.rpt
synth/fpga/build/spx_thashx4_core/reports/utilization_hier.rpt
synth/fpga/build/spx_thashx4_core/reports/timing_summary.rpt

synth/fpga/build/spx_keccakx4_core/reports/ppa_summary.txt
synth/fpga/build/spx_keccakx4_core/reports/utilization.rpt
synth/fpga/build/spx_keccakx4_core/reports/utilization_hier.rpt
synth/fpga/build/spx_keccakx4_core/reports/timing_summary.rpt
```

Key PPA data:

| Top | Critical path delay | Estimated Fmax | Notes |
| --- | ---: | ---: | --- |
| `spx_thashx4_core` | 8.578 ns | 116.58 MHz | Wrapper plus optimized Keccak datapath |
| `spx_keccakx4_core` | 8.813 ns | 113.47 MHz | Primitive-only comparison top |

Throughput estimate for `spx_thashx4_core`:

```text
cycles_per_thash_equiv = 27 / 4 = 6.75 cycles
thashx4_ops_per_second = 116.58e6 / 27 = 4.32 M ops/s
equivalent_scalar_thash_per_second = 116.58e6 * 4 / 27 = 17.27 M thash/s
```

The OOC timing reports include Vivado warnings about missing `HD.CLK_SRC` and
`HD.PARTPIN_LOCS`, so these numbers are suitable for accelerator-only Phase 2.5
comparison but should be rerun after a real integration wrapper exists.

## Current Limits

- Fixed to SPHINCS+-SHAKE-128f-simple.
- Supports only `inblocks=1` and `inblocks=2`.
- Single-rate-block SHAKE256 absorb only.
- One Keccak round per cycle, no area/frequency optimization.
- No CPU, SoC, CV-X-IF, custom instruction, or bus integration.
- OOC PPA numbers are not final system signoff numbers; rerun after the Phase 3
  wrapper and target integration constraints exist.

## Phase 3 Recommendation

Functionally and for accelerator-only PPA, the standalone accelerator is ready
for Phase 3 planning: correctness passes, lint is clean, latency is
deterministic, and the OOC Vivado run meets a 10.0 ns target clock on the
default `xc7a35tcpg236-1` part. Phase 3 should still rerun PPA after the real
wrapper/interface constraints are introduced.
