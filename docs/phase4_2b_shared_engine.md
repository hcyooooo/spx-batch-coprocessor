# Phase 4.2B Shared THASHX4 Engine

Phase 4.2B removes the static THASHX4/KeccakX4 duplication found in Phase 4.2
while preserving the descriptor ABI and the existing THASHX4 and WOTS_CHAINX4
descriptor operations.

## Why Shared Engine

Phase 4.2 made the WOTS_CHAINX4 descriptor path functional, but the
WOTS-inclusive descriptor adapter failed xc7a35tcpg236-1 PPA:

| Build | LUT | FF | Result |
| --- | ---: | ---: | --- |
| Phase 3.3 descriptor_4w baseline | 14801 | 11870 | Routed |
| Phase 4.2 descriptor_4w with WOTS_CHAINX4 | 28412 | 22657 | Placement failed |

The xc7a35t device has 20800 LUTs, so the Phase 4.2 4w build was about 36.6%
over capacity.

## Old Structure

Phase 4.2 had two independent thash-containing branches:

```text
spx_descriptor_adapter
  u_thashx4_core
    u_keccakx4
  u_wots_chainx4_core
    u_thashx4_core
      u_keccakx4
```

The runtime starts were mutually exclusive, but the RTL hierarchy still
contained two physical `spx_thashx4_core` instances and therefore two physical
`spx_keccakx4_core` instances. Vivado hierarchy showed the two KeccakX4
instances alone accounted for about 23970 LUT / 12814 FF.

## New Structure

Phase 4.2B changes `spx_wots_chainx4_core` into a scheduler/controller. It no
longer instantiates `spx_thashx4_core`; instead it emits one request per WOTS
chain step and consumes the response from an external engine.

```text
spx_descriptor_adapter
  u_thashx4_core                  # single shared THASHX4/KeccakX4 engine
    u_keccakx4
  u_wots_chainx4_core             # controller only
    wots_req_* / wots_rsp_*
```

The standalone WOTS testbench now connects the controller to a real
`spx_thashx4_core`, so the standalone WOTS regression still covers the full
WOTS+thash data path.

## Arbitration

The descriptor adapter still accepts one descriptor at a time. Therefore the
direct THASHX4 operation and the WOTS_CHAINX4 operation are mutually exclusive
at descriptor granularity.

- THASHX4: `ST_START_CORE` directly pulses the shared thash engine start.
- WOTS_CHAINX4: `ST_START_CORE` starts the WOTS controller. The controller
  drives `wots_req_valid` for each chain step.
- `wots_req_ready` is high when the shared thash engine is not busy.
- `wots_rsp_valid` is the shared thash `done` pulse routed back to the WOTS
  controller.
- WOTS requests always use `inblocks=1`; direct THASHX4 keeps the descriptor
  `inblocks=1/2` behavior.

No Keccak/thash algorithm logic changed, and no AXI/AHB/APB/X-HEEP/SoC wiring
was added.

## Correctness Regression

Run on the Linux VM:

| Command | Result |
| --- | --- |
| `make -C sim sim-descriptor-adapter` | PASS |
| `make -C sim sim-wots-chain-descriptor` | PASS |
| `make -C sim sim-cv32e40x-wots-chain-smoke` | PASS |
| `make -C sim sim-cv32e40x-wots-chain-smoke-regress` | PASS |
| `make -C sim sim-cv32e40x-wots-chain-error` | PASS |
| `make -C sim test` | PASS |
| `./scripts/lint_rtl.sh` | PASS |

Direct THASHX4 descriptor timing remained unchanged in 4w mode:

| inblocks | load | core | store | total |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 15 | 27 | 5 | 50 |
| 2 | 19 | 27 | 5 | 54 |

## Latency Comparison

Zero-wait WOTS_CHAINX4 results:

| num_steps | WOTS controller cycles | descriptor perf_total | CV32E40X visible cycles | Delta vs Phase 4.2 |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 29 | 52 | 55 | 0 |
| 2 | 57 | 80 | 88 | 0 |
| 4 | 113 | 136 | 143 | 0 |
| 8 | 225 | 248 | 253 | 0 |
| 15 | 421 | 444 | 451 | 0 |

The shared-engine handshake did not add measurable latency in the zero-wait
regression. The WOTS controller starts the shared engine on the same cycle that
the old internal scheduler would have pulsed its private thash core.

## Expected PPA Improvement

The expected area reduction is the removal of the WOTS-private thash/keccak
branch:

| Removed Phase 4.2 hierarchy | LUT | FF |
| --- | ---: | ---: |
| `u_wots_chainx4_core/u_thashx4_core` | 12899 | 8573 |
| nested `u_keccakx4` within that branch | 11855 | 6407 |

The new descriptor should retain one `u_thashx4_core/u_keccakx4`, the WOTS
controller local state, and small request mux/ready logic. The 4w descriptor is
therefore expected to move back below the 20800 LUT device capacity, but the
actual number must be confirmed with Vivado.

## PPA Flow Status

This VM does not have `vivado` on `PATH`, so routed PPA was not run locally.
The 4w flow command path was checked with `make -n`:

```text
cd synth/fpga
vivado -mode batch -source synth_vivado.tcl \
  -tclargs spx_descriptor_adapter xc7a35tcpg236-1 10.0 4
```

The synthesis file list still includes:

- `rtl/core/spx_thashx4_core.sv`
- `rtl/core/spx_wots_chainx4_core.sv`
- `rtl/cvxif/spx_descriptor_adapter.sv`

## Windows Vivado Next Step

Run the 4w descriptor build on the Windows Vivado host:

```text
cd synth\fpga
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 4
```

Collect:

- `synth/fpga/build/spx_descriptor_adapter_4w/reports/ppa_summary.txt`
- `synth/fpga/build/spx_descriptor_adapter_4w/reports/utilization.rpt`
- `synth/fpga/build/spx_descriptor_adapter_4w/reports/utilization_hier.rpt`
- `synth/fpga/build/spx_descriptor_adapter_4w/reports/timing_summary.rpt`

The hierarchy check should show only one large
`spx_descriptor_adapter/u_thashx4_core/u_keccakx4` path. There should be no
`u_wots_chainx4_core/u_thashx4_core/u_keccakx4` path in the descriptor adapter
build.
