# Phase 4.3 Mixed-Length WOTS_CHAINX4 Verify Chains

Phase 4.3 extends the Phase 4.2C shared-engine `WOTS_CHAINX4` path so the four
lanes may run different WOTS chain lengths in one descriptor. The change is
intended for WOTS verify workloads, where each chain starts from a signature
element and only needs to run the remaining number of steps to reach the public
key point.

This phase remains inside the standalone descriptor accelerator boundary. It
does not add SoC integration, AXI, AHB, APB, X-HEEP wiring, or any second hash
datapath.

## Why Mixed-Length Chains

The uniform Phase 4.2C scheduler handled one `start_step` and one `num_steps`
for all four lanes. That works for grouped WOTS chains with equal work, but WOTS
verify naturally has divergent per-lane work:

```text
lane_steps = [15 - digit0, 15 - digit1, 15 - digit2, 15 - digit3]
```

Issuing one descriptor per scalar chain preserves work efficiency but pays the
descriptor load/store and software polling overhead repeatedly. Mixed-length
`WOTS_CHAINX4` keeps one descriptor and one shared THASHX4 datapath while
allowing inactive lanes to drop out logically.

## Uniform vs Mixed Mode

Uniform mode is unchanged:

- op type `1 = WOTS_CHAINX4`;
- descriptor word 7 encodes one `start_step` and one `num_steps`;
- all four lanes update every physical chain step;
- `num_steps` remains valid in the old descriptor range `1..15`.

Mixed mode adds:

- op type `2 = WOTS_CHAINX4_MIXED`;
- descriptor word 6 carries packed lane start steps;
- descriptor word 7 carries packed lane step counts;
- each lane has independent `remaining_steps`;
- inactive lanes hold their current chain value and ignore the shared thash
  output for that lane.

The shared thash engine still runs all four lanes for each physical step up to
`max(lane_num_steps)`. The controller counts useful lane work separately from
physical lane slots:

```text
useful_lane_ops   = sum(lane_num_steps)
physical_lane_ops = 4 * max(lane_num_steps)
lane_utilization  = useful_lane_ops / physical_lane_ops
```

## Descriptor ABI Extension

The descriptor remains eight 32-bit words. The old `THASHX4` and uniform
`WOTS_CHAINX4` interpretations are kept.

| Word | Offset | Uniform WOTS | Mixed WOTS |
| ---: | ---: | --- | --- |
| 1 | `0x04` | op type `1` | op type `2` |
| 6 | `0x18` | descriptor length hint | `start_steps_packed` |
| 7 | `0x1c` | `{num_steps, start_step}` | `num_steps_packed` |

Packed mixed fields use one byte per lane:

| Bits | Field |
| ---: | --- |
| `7:0` | lane 0 |
| `15:8` | lane 1 |
| `23:16` | lane 2 |
| `31:24` | lane 3 |

Each lane is accepted when:

```text
lane_num_steps <= 15
lane_start_step <= 16
lane_start_step + lane_num_steps <= 16
```

The mixed descriptor allows a lane with `lane_num_steps = 0`; that lane simply
passes its input value through. A fully zero mixed descriptor is treated as an
immediate pass-through by the RTL controller, though the generated tests keep at
least one useful lane active.

## C Model Correctness

`sw/spx_model/wots_chainx4_model.c` now provides:

- the original uniform `spx_wots_chainx4_model`;
- `spx_wots_chainx4_mixed_model`;
- mixed scalar reference and compare helpers;
- `spx_wots_chainx4_stats_t` with useful ops, physical ops, max steps, and lane
  utilization.

The mixed model iterates `max_num_steps` physical steps. For each lane, it only
updates the hash address and commits `thashx4` output while `step <
lane_num_steps`; otherwise the lane's chain value is held. The generated vector
program compares the mixed x4 model against four scalar chains before emitting
each mixed vector.

## RTL Correctness

`rtl/core/spx_wots_chainx4_core.sv` remains a controller around the external
shared THASHX4 engine. It does not instantiate `spx_thashx4_core`.

Implemented controller state:

- per-lane `step_q`;
- per-lane `steps_left_q`;
- per-lane `chain_q`;
- `active_mask = steps_left_q != 0`;
- `done` when every lane's next `steps_left` is zero.

On each thash response, active lanes take the corresponding thash output,
increment their step, and decrement `steps_left`. Inactive lanes keep their
current chain value. The request side still drives four lanes into the shared
thash engine every physical step, so no Keccak/thash algorithm semantics are
changed.

The descriptor adapter still contains one shared hash datapath:

```text
spx_descriptor_adapter
  u_thashx4_core
    u_keccakx4
  u_wots_chainx4_core
```

No `u_wots_chainx4_core/u_thashx4_core` or second `u_keccakx4` instance is
introduced.

## Standalone Mixed RTL Test

New target:

```sh
make -C sim sim-wots-chainx4-mixed
```

The testbench reads `sim/vectors/wots_chainx4_mixed_vectors.hex`, compares every
lane against C golden output, checks the `[1,1,1,1]` case against uniform mode,
and prints utilization and latency.

Covered fixed cases:

| Case | lane steps |
| ---: | --- |
| 0 | `[1,1,1,1]` |
| 1 | `[1,2,3,4]` |
| 2 | `[0,1,8,15]` |
| 3 | `[15,0,0,0]` |
| 4 | `[3,7,11,15]` |

The vector set also includes 32 deterministic random mixed cases.

Observed standalone result:

```text
PASS wots_chainx4_mixed (37 cases)
```

## Descriptor Test

`sim/tb/tb_wots_chain_descriptor.sv` now checks:

- uniform `WOTS_CHAINX4`;
- mixed `WOTS_CHAINX4_MIXED`;
- bad mixed chain windows;
- invalid mixed `num_steps > 15`;
- unaligned descriptor;
- invalid op type;
- original `THASHX4` descriptor path.

Observed result:

```text
PASS wots_chain_descriptor (uniform=5 mixed=37)
THASHX4_DESCRIPTOR_PATH_PASS inblocks=1 cycles=50 load=15 core=27 store=5
```

## CV32E40X Smoke

`sw/tests/spx_cvxif_wots_chain_smoke.c` now consumes a vector table containing
both uniform and mixed WOTS cases. The program builds either a uniform or mixed
descriptor, issues `SPX_SET_DESC`, `SPX_START`, polls `SPX_STATUS`, checks all
four output lanes, and accumulates useful/physical lane operation counters.

The core-level testbench still fatals if `xif.mem_valid` is asserted; descriptor
bulk data stays on the descriptor memory-side path.

Observed zero-wait smoke result:

```text
Loaded CV32E40X WOTS chain vector table: uniform=5 mixed=37 total=42
PASS cv32e40x_spx_core_smoke mode=zero_wait ... cases_passed=42 cases_failed=0
```

The required fixed mixed cases `[1,2,3,4]`, `[0,1,8,15]`, and `[3,7,11,15]` all
run as `op_type=2`.

## Lane Utilization and Performance

Baseline for this table is repeated scalar-useful `THASHX4` descriptors at 57
cycles per useful thash. The `cycles` column is descriptor-adapter
`perf_total`.

| case | lane_steps | max_steps | useful_lane_ops | physical_lane_ops | lane_utilization | cycles | cycles/useful_thash | speedup_vs_scalar_descriptors |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | `[1,1,1,1]` | 1 | 4 | 4 | 1.00 | 52 | 13.00 | 4.38x |
| 1 | `[1,2,3,4]` | 4 | 10 | 16 | 0.62 | 136 | 13.60 | 4.19x |
| 2 | `[0,1,8,15]` | 15 | 24 | 60 | 0.40 | 444 | 18.50 | 3.08x |
| 3 | `[15,0,0,0]` | 15 | 15 | 60 | 0.25 | 444 | 29.60 | 1.93x |
| 4 | `[3,7,11,15]` | 15 | 36 | 60 | 0.60 | 444 | 12.33 | 4.62x |

The benefit is strongest when useful work is reasonably balanced across the
four lanes. Low-utilization groups still save descriptor overhead, but they pay
for dummy physical lane slots until the longest lane completes.

## Area Risk

Phase 4.3 intentionally adds controller logic only:

- per-lane counters;
- active mask;
- per-lane hold/update muxing;
- descriptor decode for the mixed packed words;
- performance accounting in tests.

No new datapath is added. The descriptor adapter still has one
`u_thashx4_core/u_keccakx4` hierarchy. The expected area delta should be small
relative to the Phase 4.2C routed result:

| Phase 4.2C shared-engine descriptor_4w | Result |
| --- | ---: |
| LUT | 17079 |
| FF | 14049 |
| BRAM | 0 |
| DSP | 0 |
| Fmax | 107.67 MHz |

Vivado PPA is intentionally deferred to the Phase 4.3 PPA pass.

## Vivado PPA Result

Phase 4.3C refreshed the descriptor-adapter out-of-context Vivado PPA on the
Windows Vivado host with the 4-word memory-side adapter configuration:

```bat
cd synth\fpga
run_vivado_descriptor.bat spx_descriptor_adapter xc7a35tcpg236-1 10.0 4
```

Reports were written under:

```text
synth/fpga/build/spx_descriptor_adapter_4w/reports/
```

Configuration and routed PPA:

| Item | Result |
| --- | ---: |
| FPGA part | `xc7a35tcpg236-1` |
| Target clock | 10.0 ns |
| LUT | 18340 |
| FF | 14233 |
| BRAM | 0 |
| DSP | 0 |
| WNS | 0.102 ns |
| Critical delay (`period - WNS`) | 9.898 ns |
| Critical data path delay | 9.609 ns |
| Estimated Fmax | 101.03 MHz |

Vivado completed placement and routing successfully. The final routed timing
summary reports all user-specified timing constraints met, with 0 setup failing
endpoints. No `UTLZ-1`, `CRITICAL WARNING:`, `ERROR:`, or timing failure marker
was observed in the refreshed run logs.

Comparison against the Phase 4.2C shared-engine uniform WOTS baseline:

| Build | LUT | FF | BRAM | DSP | Fmax | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Phase 4.2C shared-engine uniform WOTS | 17079 | 14049 | 0 | 0 | 107.67 MHz | routed |
| Phase 4.3 mixed-length WOTS | 18340 | 14233 | 0 | 0 | 101.03 MHz | routed, timing met |

Delta:

| Metric | Delta |
| --- | ---: |
| LUT | +1261 (+7.38%) |
| FF | +184 (+1.31%) |
| Fmax | -6.64 MHz (-6.17%) |
| LUT utilization | 88.17% of 20800 |
| Remaining LUT headroom | 2460 LUTs (11.83%) |

The routed hierarchy still contains only one shared hash datapath:

```text
spx_descriptor_adapter
  u_thashx4_core
    u_keccakx4
  u_wots_chainx4_core
```

The hierarchical utilization report shows no
`u_wots_chainx4_core/u_thashx4_core` instance and no second `keccakx4_core`.
The mixed-length logic remains concentrated in the descriptor decode and the
`spx_wots_chainx4_core` lane controller: packed per-lane start/step decode,
per-lane `steps_left_q`, `active_mask`, and hold/update muxing.

Phase 4.3 fits `xc7a35tcpg236-1` at the 10.0 ns target with a narrow but
positive timing margin. The controller area increment is acceptable because it
preserves the single shared THASHX4/KeccakX4 datapath and leaves 2460 LUTs of
device headroom. Phase 4.4 WOTS public-key generation grouping is recommended,
with the same constraint that grouping should continue reusing this shared
hash engine unless a later PPA run justifies a different area tradeoff.

## Regression Status

Observed passing commands in this workspace:

```sh
make -C sim sim-wots-chainx4
make -C sim sim-wots-chainx4-mixed
make -C sim sim-wots-chain-descriptor
make -C sim sim-cv32e40x-wots-chain-smoke
make -C sim sim-cv32e40x-wots-chain-smoke-regress
make -C sim sim-cv32e40x-wots-chain-error
make -C sim test
./scripts/lint_rtl.sh
```

## Recommendation

Phase 4.3 is functionally ready to enter a PPA refresh. If the small controller
delta keeps the descriptor adapter inside the Artix-7 budget, the next useful
architectural step is Phase 4.4 exploration of WOTS public-key generation
grouping. The key constraint should remain unchanged: group scheduling may
improve descriptor amortization, but it should continue to reuse the single
shared THASHX4/KeccakX4 datapath unless PPA shows substantial spare area.
