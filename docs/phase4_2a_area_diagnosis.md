# Phase 4.2A WOTS-Inclusive Area Diagnosis

This note captures the Linux/VM-side diagnosis for the Phase 4.2
WOTS-inclusive descriptor adapter area failure. Vivado is not available on this
VM, so this phase does not run implementation locally. The goal is to prepare
the Windows Vivado host to collect hierarchy reports that explain the area jump.

## Phase 4.2 PPA Failure Background

Phase 4.2 added the `WOTS_CHAINX4` descriptor operation to the existing
`THASHX4` descriptor adapter. Functionally, this lets software submit one
descriptor for multiple WOTS chain steps and amortize descriptor load/store and
polling overhead.

The Windows Vivado 2020.2 refresh for `xc7a35tcpg236-1` failed PPA for the
WOTS-inclusive `spx_descriptor_adapter`:

- Phase 3.3 `descriptor_4w` baseline: 14801 LUT, 11870 FF, routed at
  about 103 MHz.
- Phase 4.2 `spx_descriptor_adapter`, `MEM_WORDS_PER_CYCLE=4`: 28412 LUT,
  22657 FF, placement failed before timing.
- Phase 4.2 1w/2w variants were also above the 20800 LUT device capacity.

The area increase is therefore not mainly a memory bus width artifact. The
1w/2w/4w sweep only changes LUTs by about 1.3k, while all variants are roughly
12k to 13.6k LUT above the Phase 3.3 descriptor baseline.

## Current RTL Findings

`spx_wots_chainx4_core` internally instantiates an independent
`spx_thashx4_core`:

```text
rtl/core/spx_wots_chainx4_core.sv:85
  spx_thashx4_core u_thashx4_core (...)
```

That internal thash is hard-wired to `inblocks=1` and is used once per WOTS
chain step.

`spx_descriptor_adapter` also instantiates its own direct `THASHX4` path:

```text
rtl/cvxif/spx_descriptor_adapter.sv:333
  spx_thashx4_core u_thashx4_core (...)

rtl/cvxif/spx_descriptor_adapter.sv:354
  spx_wots_chainx4_core u_wots_chainx4_core (...)
```

Each `spx_thashx4_core` contains a `spx_keccakx4_core`:

```text
rtl/core/spx_thashx4_core.sv:91
  spx_keccakx4_core u_keccakx4 (...)
```

The descriptor adapter therefore has two static thash/keccak paths:

```text
spx_descriptor_adapter
  u_thashx4_core
    u_keccakx4
  u_wots_chainx4_core
    u_thashx4_core
      u_keccakx4
```

The runtime starts are mutually exclusive:

```text
thash_core_start = ST_START_CORE && op_type_q == OP_TYPE_THASHX4
wots_core_start  = ST_START_CORE && op_type_q == OP_TYPE_WOTS_CHAINX4
```

However, mutual exclusion of start signals does not imply physical resource
sharing. With the current RTL hierarchy, synthesis sees two independent
`spx_thashx4_core` instances and can legally keep two independent
`spx_keccakx4_core` datapaths.

## Current Suspects

High confidence: Keccak/thash core duplication.

The `WOTS_CHAINX4` path brings in a second thashx4, and each thashx4 includes a
wide Keccak x4 core. This directly matches the observed near-doubling of LUT and
FF area versus the Phase 3.3 descriptor adapter.

Medium confidence: register replication.

`spx_keccakx4_core` stores four 1600-bit lane states per instance. Two thash
instances imply two copies of those state registers, plus two copies of thash
absorb-state registers and WOTS chain staging registers. The roughly 10.8k FF
increase is consistent with duplicated wide hash state plus local control.

Lower confidence: large mux/control growth.

`spx_descriptor_adapter` adds op-type selection on `done`, `error`, and
four 128-bit output buses, plus existing load/store packing muxes. This is real
logic, but the small difference between 1w/2w/4w Phase 4.2 runs suggests mux and
memory-width effects are secondary to the second thash/keccak datapath.

## Vivado Report Flow Prepared

`synth/fpga/synth_vivado.tcl` now emits synthesis-stage utilization reports
immediately after `synth_design`:

```text
synth_utilization.rpt
synth_utilization_hier.rpt
```

It also emits `utilization.rpt` and `utilization_hier.rpt` immediately after
`opt_design`, before `place_design`. If placement fails with an overutilization
DRC, the post-opt hierarchy reports should still be present for diagnosis. If
placement and routing succeed, the normal final reports overwrite those paths
with routed-design utilization.

The flow also supports standalone synthesis of `spx_wots_chainx4_core` through:

```sh
make -C synth/fpga synth-wots-chainx4 PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
```

On Windows without `make`, use:

```text
cd synth\fpga
run_vivado.bat spx_wots_chainx4_core xc7a35tcpg236-1 10.0
```

## Reports Needed From Windows Vivado Host

Primary failing build:

```text
cd synth\fpga
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 4
```

Collect these files from:

```text
synth/fpga/build/spx_descriptor_adapter_4w/reports/
```

- `synth_utilization.rpt`
- `synth_utilization_hier.rpt`
- `utilization.rpt`
- `utilization_hier.rpt`
- `timing_summary.rpt`, if place/route succeeds
- `clock_utilization.rpt`, if place/route succeeds
- the Vivado console log showing any DRC failure

Useful comparison builds:

```text
cd synth\fpga
run_vivado.bat spx_thashx4_core xc7a35tcpg236-1 10.0
run_vivado.bat spx_wots_chainx4_core xc7a35tcpg236-1 10.0
run_vivado.bat spx_keccakx4_core xc7a35tcpg236-1 10.0
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 1
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 2
```

The key check in `utilization_hier.rpt` is whether the two branches below are
both large:

```text
spx_descriptor_adapter/u_thashx4_core/u_keccakx4
spx_descriptor_adapter/u_wots_chainx4_core/u_thashx4_core/u_keccakx4
```

If both branches account for roughly one thashx4/keccakx4 each, the Phase 4.2
area failure is primarily architectural duplication. If the hierarchy report
instead shows unexpectedly large adapter-local logic, then the next pass should
inspect output muxing, memory packing, and synthesized register replication in
the descriptor adapter.

## Windows Vivado Hierarchical Utilization

Windows Vivado 2020.2 was run on May 14, 2026 with target
`xc7a35tcpg236-1` and a 10.0 ns clock. The main failing command was:

```text
cd synth\fpga
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 4
```

Placement failed, but `synth_design` and `opt_design` completed and produced
the intended reports:

```text
synth/fpga/build/spx_descriptor_adapter_4w/reports/synth_utilization.rpt
synth/fpga/build/spx_descriptor_adapter_4w/reports/synth_utilization_hier.rpt
synth/fpga/build/spx_descriptor_adapter_4w/reports/utilization.rpt
synth/fpga/build/spx_descriptor_adapter_4w/reports/utilization_hier.rpt
synth/fpga/build/spx_descriptor_adapter_4w/reports/vivado_descriptor_adapter_4w.log
```

The failed 4w descriptor adapter post-opt utilization was:

| Block / hierarchy instance | LUT | FF | Notes |
| --- | ---: | ---: | --- |
| `spx_descriptor_adapter` | 28412 | 22657 | Top total, 136.60% of 20800 LUTs |
| `(spx_descriptor_adapter)` | 2013 | 2797 | Adapter-local descriptor/load/store/control logic |
| `u_thashx4_core` | 12762 | 9108 | Direct `THASHX4` branch |
| `u_thashx4_core/u_keccakx4` | 12115 | 6407 | Keccak datapath inside direct branch |
| `u_wots_chainx4_core` | 13637 | 10752 | WOTS branch total |
| `u_wots_chainx4_core/(local)` | 738 | 2179 | WOTS scheduler/local chain state |
| `u_wots_chainx4_core/u_thashx4_core` | 12899 | 8573 | Thash branch inside WOTS scheduler |
| `u_wots_chainx4_core/u_thashx4_core/u_keccakx4` | 11855 | 6407 | Keccak datapath inside WOTS branch |

The hierarchy confirms that the direct `THASHX4` path and the WOTS-internal
thash path are both physically present. Together the two thash-containing
branches account for 25661 LUT and 17681 FF, or about 90.3% of total LUT and
78.0% of total FF. The two Keccak x4 instances alone account for 23970 LUT and
12814 FF, or about 84.4% of total LUT and 56.6% of total FF. Adapter-local
logic is only 2013 LUT / 2797 FF, so large descriptor muxing and memory packing
are secondary, not the primary area driver.

The comparison top runs were:

```text
cd synth\fpga
run_vivado.bat spx_keccakx4_core xc7a35tcpg236-1 10.0
run_vivado.bat spx_thashx4_core xc7a35tcpg236-1 10.0
run_vivado.bat spx_wots_chainx4_core xc7a35tcpg236-1 10.0
```

Their routed `ppa_summary.txt` and `utilization_hier.rpt` results were:

| Top | LUT | FF | WNS ns | Est. Fmax MHz | Key hierarchy |
| --- | ---: | ---: | ---: | ---: | --- |
| `spx_keccakx4_core` | 13578 | 6415 | 1.187 | 113.47 | Top-level Keccak x4 datapath |
| `spx_thashx4_core` | 11797 | 9105 | 1.422 | 116.58 | `u_keccakx4`: 11539 LUT / 6407 FF |
| `spx_wots_chainx4_core` | 12857 | 10752 | 0.844 | 109.22 | `u_thashx4_core`: 12319 LUT / 8573 FF; nested `u_keccakx4`: 11280 LUT / 6407 FF |

Small differences between standalone and adapter-embedded hierarchy numbers
come from OOC top-port effects and cross-hierarchy optimization, but the shape
is consistent: each WOTS or thash path is dominated by a Keccak x4 datapath.

The Vivado DRC error was captured in:

```text
synth/fpga/build/spx_descriptor_adapter_4w/reports/vivado_descriptor_adapter_4w.log
```

The relevant failure summary is:

```text
ERROR: [DRC UTLZ-1] Resource utilization: LUT as Logic over-utilized in Top Level Design
This design requires 28412 LUT as Logic cells but only 20800 compatible sites are available.
ERROR: [DRC UTLZ-1] Resource utilization: Slice LUTs over-utilized in Top Level Design
This design requires 28412 Slice LUTs cells but only 20800 compatible sites are available.
ERROR: [Vivado_Tcl 4-23] Error(s) found during DRC. Placer not run.
```

Conclusion: Phase 4.2A confirms the VM-side hypothesis. The Phase 4.2
WOTS-inclusive descriptor adapter area growth is primarily caused by static
duplication of thashx4/keccakx4 datapaths, not by memory bus width, large muxes,
or local descriptor control.

## Next RTL Direction

No RTL restructuring is done in Phase 4.2A. The Windows reports confirm
duplication, so Phase 4.2B should use a shared-thashx4-engine structure:

- `spx_descriptor_adapter` instantiates only one `spx_thashx4_core`.
- The direct `THASHX4` descriptor operation drives that shared engine directly.
- The WOTS scheduler becomes a controller and no longer internally
  instantiates `spx_thashx4_core`.
- The WOTS scheduler reuses the shared engine through a request/response
  interface owned by the descriptor adapter.

That Phase 4.2B work should preserve the descriptor ABI and core semantics, and
should not include SoC, AXI, AHB, APB, or X-HEEP integration.
