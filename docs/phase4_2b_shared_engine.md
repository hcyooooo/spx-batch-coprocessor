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

## Windows Vivado PPA Result

Windows Vivado 2020.2 was run on May 14, 2026 on the shared-engine
`spx_descriptor_adapter`, with the same accelerator-only OOC flow used by the
earlier descriptor PPA runs.

Command:

```text
cd synth\fpga
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 4
```

Equivalent make target:

```text
make -C synth/fpga synth-descriptor-adapter-4w PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
```

Build configuration:

| Field | Value |
| --- | --- |
| Top | `spx_descriptor_adapter` |
| Descriptor memory width | `MEM_WORDS_PER_CYCLE=4` |
| FPGA part | `xc7a35tcpg236-1` |
| Target clock | 10.0 ns |
| Flow | Vivado out-of-context accelerator-only synth/place/route |

Generated reports:

- `synth/fpga/build/spx_descriptor_adapter_4w/reports/ppa_summary.txt`
- `synth/fpga/build/spx_descriptor_adapter_4w/reports/utilization.rpt`
- `synth/fpga/build/spx_descriptor_adapter_4w/reports/utilization_hier.rpt`
- `synth/fpga/build/spx_descriptor_adapter_4w/reports/timing_summary.rpt`

Measured PPA:

| Metric | Result |
| --- | ---: |
| LUT | 17079 |
| FF | 14049 |
| BRAM | 0 |
| DSP | 0 |
| WNS | 0.712 ns |
| Critical delay | 9.288 ns |
| Estimated Fmax | 107.67 MHz |

Vivado placement and routing both completed successfully. The final router
summary reported 0 failed nets, 0 unrouted nets, 0 partially routed nets, and 0
node overlaps. DRC completed with 0 errors before implementation steps, and the
old `UTLZ-1` overutilization DRC did not reappear.

The routed utilization is 17079 / 20800 Slice LUTs, or 82.11% of the
`xc7a35tcpg236-1` LUT budget, leaving 3721 LUTs of OOC headroom. FF usage is
14049 / 41600, or 33.77%.

Hierarchy check:

| Hierarchy | LUT | FF | Interpretation |
| --- | ---: | ---: | --- |
| `spx_descriptor_adapter` | 17079 | 14049 | Top total |
| `(spx_descriptor_adapter)` | 1577 | 2764 | Adapter local control/load/store/mux logic |
| `u_thashx4_core` | 13018 | 9104 | Single shared THASHX4 engine |
| `u_thashx4_core/u_keccakx4` | 12111 | 6407 | Single KeccakX4 datapath |
| `u_wots_chainx4_core` | 2488 | 2181 | WOTS controller/local state |

The hierarchy confirms that the descriptor adapter now contains only one large
`spx_descriptor_adapter/u_thashx4_core/u_keccakx4` path. The old nested
`spx_descriptor_adapter/u_wots_chainx4_core/u_thashx4_core/u_keccakx4` path is
absent from the routed hierarchy report, and `spx_wots_chainx4_core` is no
longer a thash datapath owner in this build.

Comparison against the key 4w builds:

| Build | LUT | FF | Fmax | Result |
| --- | ---: | ---: | ---: | --- |
| Phase 3.3 descriptor_4w baseline | 14801 | 11870 | 103.34 MHz | routed |
| Phase 4.2 non-shared WOTS | 28412 | 22657 | N/A | placement failed, `UTLZ-1` |
| Phase 4.2B shared-engine WOTS | 17079 | 14049 | 107.67 MHz | routed |

Versus the Phase 3.3 descriptor_4w baseline, the shared-engine WOTS build costs
+2278 LUT and +2179 FF, while keeping routed timing above the 100 MHz target.
Versus the Phase 4.2 non-shared WOTS build, it removes 11333 LUT and 8608 FF
and restores place/route on `xc7a35tcpg236-1`.

Phase 4.2C conclusion: the shared-engine descriptor adapter fits the target
Artix-7 part again. Area is acceptable for the standalone OOC accelerator
boundary, timing is acceptable at the 10.0 ns target, and Phase 4.3 can proceed
to lane divergence / mixed-length WOTS verify chains while keeping the same
single shared KeccakX4 engine assumption.
