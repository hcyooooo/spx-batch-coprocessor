# Phase 5 End-to-End SPHINCS+ Sign Scheduling Model

Phase 5 builds a software/model-level end-to-end scheduling estimate for
SPHINCS+-SHAKE-128f-simple signing. It reuses the accelerator primitives that
already passed earlier phases and intentionally does not add RTL datapath.

This is a scheduling and accounting model, not a new hardware integration.

## Phase 5 Goal

The goal is to estimate complete sign-path impact from the current accelerator
surface:

- keep the existing `THASHX4` descriptor path for independent 1-block and
  2-block thash jobs;
- use the Phase 4.4 WOTS public-key grouping model for WOTS chain generation;
- account for descriptor/control traffic at sign level;
- expose wait-state sensitivity;
- identify the remaining software bottlenecks before choosing any Phase 6 RTL.

The model targets the checked-in SPHINCS+-SHAKE-128f-simple parameters:

| Parameter | Value |
| --- | ---: |
| `SPX_N` | 16 |
| `SPX_FULL_HEIGHT` | 66 |
| `SPX_D` | 22 |
| `SPX_TREE_HEIGHT` | 3 |
| `SPX_FORS_HEIGHT` | 6 |
| `SPX_FORS_TREES` | 33 |
| `SPX_WOTS_LEN` | 35 |
| WOTS chain steps per pk chain | 15 |

## Existing Accelerator Primitives

Phase 5 assumes these existing primitives only:

- `THASHX4`: four-lane thash engine through the descriptor path. The model uses
  57 wall cycles per descriptor and four lanes.
- `WOTS_CHAINX4` uniform: one descriptor schedules four chains with the same
  `start_step` and `num_steps`.
- `WOTS_CHAINX4` mixed: one descriptor schedules four chains with per-lane
  start/step counts, including zero-step tail lanes.
- `descriptor_4w` memory-side path: descriptor bulk data moves through the
  128-bit memory-side path, not CV-X-IF bulk movement.

The routed Phase 4.3C mixed descriptor result remains the area baseline:

| Metric | Result |
| --- | ---: |
| LUT | 18340 / 20800 |
| FF | 14233 |
| Estimated Fmax | 101.03 MHz |
| Remaining LUT headroom | 2460 |

## Accelerator Mapping

The following sign portions map to the current accelerator model:

| Sign work | Accelerator model |
| --- | --- |
| WOTS pk generation chain part | Phase 4.4 WOTS pk grouping using `WOTS_CHAINX4` uniform/mixed descriptors |
| FORS leaf thash | `THASHX4`, `inblocks=1` |
| FORS internal node thash | `THASHX4`, `inblocks=2` |
| Merkle/treehash internal node thash | `THASHX4`, `inblocks=2` |

The following sign portions remain software/model estimates:

- WOTS pk compression (`thash(..., inblocks=SPX_WOTS_LEN)`);
- FORS pk compression (`thash(..., inblocks=SPX_FORS_TREES)`);
- WOTS/FORS PRF address work;
- address generation and tree scheduler control;
- `gen_message_random` and `hash_message`;
- WOTS signature extraction and signature serialization.

## Cycle Model Assumptions

Measured or carried-forward accelerator constants:

| Constant | Value |
| --- | ---: |
| THASHX4 descriptor wall cycles | 57 cycles/descriptor |
| WOTS_CHAINX4 grouped descriptor cycles | 444 cycles per 15-step group |
| WOTS pk grouped descriptors | 9 per WOTS pk chain-generation |
| WOTS pk grouped cycles | 3996 per WOTS pk chain-generation |
| THASHX4 lanes | 4 |
| XIF instructions | 9 per descriptor |
| Status polls | 5 per descriptor |
| 4w bus reads, `inblocks=1` / WOTS chain descriptor | 15 per descriptor |
| 4w bus reads, `inblocks=2` | 19 per descriptor |
| 4w bus writes | 5 per descriptor |

Software placeholders are deliberately explicit:

- PRF_ADDR is modeled as 57 cycle-equivalent units per call.
- Long WOTS/FORS pk compression is modeled as 5 SHAKE-rate/permutation
  equivalent units, or 285 cycles per call.
- `gen_message_random` and `hash_message` are modeled as two small top-level
  control/hash calls at 57 cycles each.

These software placeholders are not measured CV32E40X software cycles. They are
kept equal between baseline and accelerated columns so the model does not claim
accelerator benefit for uncovered work.

## Sign Work Counts

The sign model derives:

| Work item | Count | Source |
| --- | ---: | --- |
| WOTS pk generations | 176 | `SPX_D * 2^SPX_TREE_HEIGHT = 22 * 8` |
| WOTS useful chain steps | 92400 | `176 * 35 * 15` |
| WOTS descriptor-per-step descriptors | 23760 | `176 * 135` |
| WOTS grouped descriptors | 1584 | `176 * 9` |
| WOTS pk compression calls | 176 | one per generated WOTS pk |
| FORS leaf thash jobs | 2112 | `33 * 2^6` |
| FORS internal thash jobs | 2079 | `33 * (2^6 - 1)` |
| Merkle internal thash jobs | 154 | `22 * (2^3 - 1)` |
| PRF_ADDR calls | 8305 | `176 * 35 + 2112 + 33` |
| FORS pk compression calls | 1 | final FORS roots compression |

## End-to-End Breakdown

Observed model command:

```sh
make -C sim test-sign-schedule-model
```

Current zero-wait result:

| Component | Baseline model cycles | Accelerated model cycles | Speedup | Notes |
| --- | ---: | ---: | ---: | --- |
| WOTS chain generation | 1354320 | 703296 | 1.93x | 176 WOTS pk generations; 135 THASHX4 descriptors/pk -> 9 grouped descriptors/pk |
| WOTS pk compression | 50160 | 50160 | 1.00x | software estimate; current accelerator does not cover `inblocks=SPX_WOTS_LEN` |
| FORS leaf/internal | 59736 | 59736 | 1.00x | THASHX4 descriptor estimate for FORS leaves and `inblocks=2` internal nodes |
| Merkle/treehash | 2223 | 2223 | 1.00x | THASHX4 descriptor estimate for sign-time treehash internal nodes |
| PRF/address/control | 473784 | 473784 | 1.00x | software estimate for PRF_ADDR, message hashing/control, and FORS pk compression |
| Total sign estimate | 1940223 | 1289199 | 1.50x | model total |

The accelerator-covered descriptor portion alone improves from 1416279 cycles
to 765255 cycles, or 1.85x. Including unchanged software placeholders, the
sign-level estimate is 1.50x.

WOTS_CHAINX4 grouping saves 651024 cycles in the zero-wait model. That is
33.55% of the full baseline model and about 45.97% of the accelerator-covered
descriptor portion.

## Descriptor And Control Traffic

The descriptor-per-step row keeps the Phase 4.4 WOTS-chain reference scope. The
two full-sign rows add FORS and Merkle THASHX4 descriptor work.

| Model | Scope | total descriptors | XIF instructions | status polls | bus reads | bus writes |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| descriptor-per-step baseline | WOTS chain generation only | 23760 | 213840 | 118800 | 356400 | 118800 |
| THASHX4-only descriptor model | Full sign 1/2-block THASH work | 24847 | 223623 | 124235 | 374941 | 124235 |
| WOTS_CHAINX4 grouped model | Full sign with grouped WOTS chains | 2671 | 24039 | 13355 | 42301 | 13355 |

For WOTS chain generation alone, descriptor/control traffic still drops by
15x: 23760 descriptors become 1584 grouped descriptors. At full sign scope,
descriptors drop from 24847 to 2671, a 9.30x reduction, because the FORS and
Merkle THASHX4 descriptors remain unchanged.

## Wait-State Sensitivity

Sensitivity uses the Phase 3.9 average descriptor accounting modes. Bus
transaction counts stay fixed; wait and backpressure inflate cycles and polling.

| Mode | Baseline total cycles | Grouped total cycles | Speedup | baseline polls | grouped polls | baseline traffic | grouped traffic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| zero wait | 1940223 | 1289199 | 1.50x | 124235 | 13355 | 499176 | 55656 |
| wait1 | 2623516 | 1362652 | 1.93x | 186353 | 20033 | 499176 | 55656 |
| wait2 | 3170150 | 1421414 | 2.23x | 236047 | 25375 | 499176 | 55656 |
| split read2/write4 | 3443467 | 1450795 | 2.37x | 260894 | 28046 | 499176 | 55656 |
| random ready 50% | 2538042 | 1353463 | 1.88x | 178650 | 19204 | 499176 | 55656 |
| random ready 75% | 2162355 | 1313078 | 1.65x | 144361 | 15519 | 499176 | 55656 |

The relative benefit of WOTS grouping increases when memory latency grows
because the grouped model pays far fewer descriptor memory/control envelopes.

## Alignment With Earlier Profiling

The Phase 5 counts align with the earlier profiling data:

- Sign profiling reported `wots_gen_pk = 176`; this model uses 176 WOTS pk
  generations.
- Sign WOTS chain thash count is `176 * 35 * 15 = 92400`. The earlier aggregate
  keygen+sign+verify WOTS-chain count was 102405; the difference is keygen
  (`8 * 525 = 4200`) plus message-dependent verify chains (`5805` in the sample
  run).
- Sign FORS leaf count is 2112. The earlier aggregate FORS leaf count was 2145
  because verify contributes 33 FORS leaf hashes.
- Sign FORS internal count is 2079. The earlier aggregate was 2277 because
  verify contributes `33 * 6 = 198` `compute_root` hashes.
- Sign Merkle internal count is 154. The earlier aggregate 227 includes keygen
  top-tree work (`7`) and verify authentication-root work (`22 * 3 = 66`).
  The batch-utilization `merkle_internal = 161` row covered keygen+sign
  treehash regions only, which is `7 + 154`.
- Sign PRF_ADDR count is 8305, matching the sign profile: WOTS chain seeds
  (`176 * 35 = 6160`) plus FORS leaf/tree selected-secret PRFs (`2112 + 33`).

No model count was forced to match by hard adjustment; the differences come
from sign-only versus keygen+sign+verify profiling scope and from verify's
message-dependent WOTS chain lengths.

## Explicit Non-Scope For Phase 5

Phase 5 does not add or modify RTL. In particular, it does not do:

- WOTS pk compression hardware;
- FORS scheduler RTL;
- full SPHINCS sign hardware;
- an extra THASHX4 datapath;
- an extra KeccakX4 datapath;
- full SoC integration;
- AXI, AHB, or APB attachment;
- Keccak or thash algorithm semantic changes.

## Conclusion

Current accelerator benefit for full sign is estimated at 1.50x in zero-wait
mode when unchanged software placeholders are included. The accelerator-covered
descriptor work alone is estimated at 1.85x.

WOTS_CHAINX4 grouping is the dominant Phase 5 contributor. It saves 651024
cycles and cuts full-sign descriptor traffic from 24847 descriptors to 2671
descriptors.

The remaining bottlenecks are WOTS chain work that still runs through one shared
hash datapath, plus uncovered PRF/address/control and WOTS/FORS pk compression.
After grouping, the model still spends 703296 cycles in WOTS chain generation
and 523944 cycles in software placeholder work.

A FORS scheduler may be useful as a controller/traffic optimization, especially
under wait states, but it is not the first zero-wait bottleneck: FORS
leaf/internal hashing is only 59736 cycles in this sign model. WOTS pk
compression or PRF support is more likely to move end-to-end sign time, provided
it can be done without a large datapath expansion.

The current Artix-7 target is tight at 18340 LUTs out of 20800. Larger FPGA or
ASIC evaluation is worth considering before adding long-input compression
support or another hash datapath. On the current FPGA, the safer next step is
small scheduler/control modeling and PPA-gated RTL only after the software
model shows enough sign-level value.
