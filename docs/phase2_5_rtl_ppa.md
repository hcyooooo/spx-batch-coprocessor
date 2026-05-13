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

## Accelerator-Only PPA

Vivado PPA is pending a Windows-host run.

| Top | Part | LUT / logic | FF | BRAM | DSP | Estimated Fmax | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `spx_thashx4_core` | `xc7a35tcpg236-1` default | pending | pending | pending | pending | pending | Vivado host run needed |
| `spx_keccakx4_core` | `xc7a35tcpg236-1` default | pending | pending | pending | pending | pending | Optional Vivado host run needed |

The Vivado TCL emits `ppa_summary.txt` with routed WNS, critical path delay,
and estimated Fmax. LUT/FF/BRAM/DSP are in `utilization.rpt`.

## Current Limits

- Fixed to SPHINCS+-SHAKE-128f-simple.
- Supports only `inblocks=1` and `inblocks=2`.
- Single-rate-block SHAKE256 absorb only.
- One Keccak round per cycle, no area/frequency optimization.
- No CPU, SoC, CV-X-IF, custom instruction, or bus integration.
- PPA numbers are not final until Vivado is run on the target FPGA part.

## Phase 3 Recommendation

Functionally, the standalone accelerator is ready for Phase 3 planning:
correctness passes, lint is clean, and latency is deterministic. The remaining
gate before CV-X-IF integration is to run the Vivado accelerator-only flow on
the intended FPGA part and confirm the resource/Fmax tradeoff is acceptable.
