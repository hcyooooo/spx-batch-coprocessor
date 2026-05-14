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

## Next RTL Direction

No RTL restructuring is done in Phase 4.2A. If the Windows reports confirm
duplication, a later area-reduction phase should evaluate sharing a single
`spx_thashx4_core` between the direct `THASHX4` operation and the WOTS chain
scheduler, or moving WOTS chain sequencing outside the descriptor adapter so the
adapter does not statically contain two Keccak x4 datapaths.
