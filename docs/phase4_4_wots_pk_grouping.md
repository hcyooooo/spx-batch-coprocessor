# Phase 4.4 WOTS Public-Key Chain Grouping

Phase 4.4 explores a software/controller scheduling change for WOTS public-key
generation. It reuses the Phase 4.3 shared-engine `WOTS_CHAINX4` descriptor and
groups WOTS chains into descriptor-driven x4 chain operations so software does
not issue one descriptor for every chain step.

This phase intentionally does not add a second `thashx4_core`, does not add a
second `keccakx4_core`, does not connect a complete SoC, and does not implement
WOTS public-key compression hardware.

## WOTS pk Chain Structure

WOTS public-key generation builds one WOTS chain per WOTS element:

```text
sk_i = PRF(sk_seed, addr(chain=i, hash=0, type=WOTSPRF))
pk_i = F^15(sk_i, addr(chain=i, hash=0..14, type=WOTS))
```

For `w = 16`, each WOTS chain has `w - 1 = 15` `thash(..., inblocks=1)`
steps. The WOTS public key is the concatenation of all final chain values
`pk_i`, followed by the WOTS-pk compression hash in the SPHINCS+ reference
algorithm. Phase 4.4 only groups the chain-generation portion. The compression
hash is left in software/model analysis because the current THASHX4 datapath is
optimized around `inblocks=1` and `inblocks=2`, while WOTS pk compression uses
`inblocks=SPX_WOTS_LEN`.

## Parameters

The checked-in SPHINCS+-SHAKE-128f-simple reference parameters are:

| Parameter | Value |
| --- | ---: |
| `SPX_N` | 16 |
| `SPX_WOTS_W` | 16 |
| `SPX_WOTS_LOGW` | 4 |
| `SPX_WOTS_LEN1 = 8 * N / log2(w)` | 32 |
| `SPX_WOTS_LEN2` | 3 |
| `SPX_WOTS_LEN` | 35 |
| Chain steps per pk chain | 15 |
| Total useful chain steps per WOTS pk | 525 |

The software model also covers a 67-chain stress case because it is a common
WOTS length for larger `N=32` parameter sets and was requested as part of this
experiment. The grouping code is parameterized by chain count, so `35`, `67`,
or another WOTS length can be passed by software.

## Current Descriptor-Per-Step Cost

Without grouping at the WOTS-chain descriptor level, software can batch four
chains for one hash step with `THASHX4`, then repeat that process for every
step:

```text
for group in chains / 4:
  for step in 0..14:
    issue THASHX4 descriptor for this group and step
```

This keeps the four-lane hash datapath useful, but it pays descriptor/control
overhead 15 times per chain group:

- `SPX_SET_DESC`, `SPX_START`, `SPX_STATUS`, and `SPX_CLEAR` instruction flow;
- descriptor fetch and status writeback;
- public seed, address, input, and output bus traffic;
- software polling loop and status reads.

Phase 4.3 measured the zero-wait descriptor baseline at 57 core-visible cycles
per descriptor step, with the model accounting constants:

| Cost item | Per descriptor |
| --- | ---: |
| XIF instructions | 9 |
| Status polls | 5 |
| Bus reads | 15 |
| Bus writes | 5 |
| Baseline wall cycles | 57 |

## Grouping Into WOTS_CHAINX4 Descriptors

Phase 4.4 groups chains in order, four at a time:

```text
descriptor 0: chain 0, chain 1, chain 2, chain 3
descriptor 1: chain 4, chain 5, chain 6, chain 7
...
tail descriptor: remaining 1..3 chains, inactive lanes num_steps=0
```

For normal WOTS pk generation, active lanes use:

```text
start_step = 0
num_steps  = 15
```

Each full group can therefore use the existing uniform `WOTS_CHAINX4`
descriptor. The tail group uses the existing mixed descriptor encoding so the
unused lanes have `num_steps=0` and their outputs are ignored. No new RTL
datapath is needed.

The model records:

```text
useful_lane_ops   = sum(active lane num_steps)
physical_lane_ops = 4 * max(lane num_steps) per descriptor group
lane_utilization  = useful_lane_ops / physical_lane_ops
```

## Uniform Mode

Uniform mode is the best fit for full WOTS pk groups:

- four active lanes;
- same `start_step` on every lane;
- same `num_steps` on every lane;
- all lanes advance each physical step.

For SHAKE-128f-simple WOTS pk generation, every full group is uniform:
`start_step=0`, `num_steps=15`. This gives one `WOTS_CHAINX4` descriptor for
the 15 internal thash steps of four chains.

## Mixed Mode

Mixed mode is used when a group cannot be expressed by one uniform control word:

- the tail group has only 1 to 3 real WOTS chains;
- some lanes have already been advanced in software and have different starts;
- a future scheduler groups verification-style chains with different remaining
  lengths;
- software wants to pass through a lane with `num_steps=0`.

For WOTS pk generation, mixed mode is mostly a tail-lane mechanism. It is still
valuable because it avoids a scalar fallback path and keeps all WOTS chain work
using the same descriptor ABI.

## Performance Estimate

The grouped estimate uses the Phase 4.3 observed WOTS descriptor timing:

```text
grouped_cycles = 24 + 28 * max_num_steps
```

For WOTS pk generation each non-empty descriptor has `max_num_steps=15`, so the
grouped descriptor cost is `444` cycles. The descriptor-per-step baseline uses
one `THASHX4` descriptor per physical step and group: `15 * 57 = 855` cycles.

### Current SHAKE-128f-simple len=35

| Metric | Scalar descriptor-per-step | WOTS_CHAINX4 grouped |
| --- | ---: | ---: |
| descriptor_count | 135 | 9 |
| XIF instructions | 1215 | 81 |
| status polls | 675 | 45 |
| bus reads | 2025 | 135 |
| bus writes | 675 | 45 |
| useful lane ops | 525 | 525 |
| physical lane ops | 540 | 540 |
| lane utilization | 97.22% | 97.22% |
| total cycles | 7695 | 3996 |
| cycles per WOTS pk | 7695 | 3996 |
| estimated speedup | 1.00x | 1.93x |

### 67-chain stress case

| Metric | Scalar descriptor-per-step | WOTS_CHAINX4 grouped |
| --- | ---: | ---: |
| descriptor_count | 255 | 17 |
| XIF instructions | 2295 | 153 |
| status polls | 1275 | 85 |
| bus reads | 3825 | 255 |
| bus writes | 1275 | 85 |
| useful lane ops | 1005 | 1005 |
| physical lane ops | 1020 | 1020 |
| lane utilization | 98.53% | 98.53% |
| total cycles | 14535 | 7548 |
| cycles per WOTS pk | 14535 | 7548 |
| estimated speedup | 1.00x | 1.93x |

The control traffic drops by exactly `15x` for full-length WOTS pk groups:
descriptor count, XIF instructions, status polls, bus reads, and bus writes all
scale with descriptor count. Total cycle speedup is smaller than the control
reduction because the shared KeccakX4 datapath still performs the same physical
hash work.

## Software Model

Phase 4.4 adds:

- `sw/spx_model/wots_pk_grouping_model.h`
- `sw/spx_model/wots_pk_grouping_model.c`
- `sw/tests/test_wots_pk_grouping.c`

The model takes an array of `spx_wots_pk_chain_t` records. Each record contains
the chain input, address, `start_step`, and `num_steps`. It emits descriptor
groups with four logical lanes, chooses uniform descriptors when possible, and
uses mixed descriptors for tails or divergent lane windows.

The host test checks:

- grouped outputs against scalar WOTS `gen_chain` behavior;
- 67-chain full grouping with tail lanes;
- current SHAKE-128f-simple `SPX_WOTS_LEN=35`;
- tail counts of 1, 2, and 3 chains;
- mixed windows with zero-step lanes;
- invalid chain-window rejection.

Observed model result:

```text
PASS wots_pk_grouping_model
```

## Why Not Add Datapath

The routed Phase 4.3C result is already tight on the target FPGA:

| Metric | Phase 4.3C descriptor_4w result |
| --- | ---: |
| FPGA | `xc7a35tcpg236-1` |
| LUT | 18340 / 20800, 88.17% |
| FF | 14233 |
| BRAM | 0 |
| DSP | 0 |
| WNS | +0.102 ns |
| Estimated Fmax | 101.03 MHz |
| Remaining LUT headroom | 2460 |

The hierarchy still has one shared hash datapath:

```text
spx_descriptor_adapter
  u_thashx4_core
    u_keccakx4
  u_wots_chainx4_core
```

Adding another THASHX4 or KeccakX4 instance would repeat the Phase 4.2 area
failure mode. Phase 4.4 therefore focuses on descriptor scheduling and software
grouping. Any later RTL expansion should be small controller logic only and
must be followed by Vivado PPA because the remaining LUT margin is narrow.

## CV32E40X Smoke Decision

The useful Phase 4.4 question is whether WOTS pk chains should be grouped into
existing descriptors, not whether a new instruction or bus path works. A
CV32E40X smoke would require a new vector table and bare-metal program that
mostly repeats the already-passing Phase 4.3 mixed `WOTS_CHAINX4` descriptor
path. For this phase, the lower-cost C/model regression gives the scheduling
answer without increasing RTL scope. A CV32E40X smoke can be added later if
Phase 5 needs an end-to-end software driver demonstration.

## Conclusion

WOTS pk grouping is worth doing. It cuts descriptor/control traffic by about
`15x` for full-length WOTS pk chain groups and gives an estimated `1.93x`
cycle speedup versus issuing one descriptor per chain step.

The improvement comes from reusing the existing shared-engine
`WOTS_CHAINX4` path, not from adding hash hardware. That is the right tradeoff
while Phase 4.3C uses 88.17% of the `xc7a35tcpg236-1` LUT budget.

A complete WOTS pk generation hardware engine is not recommended yet. The chain
generation portion benefits from descriptor grouping, but WOTS pk compression
has different `inblocks=SPX_WOTS_LEN` behavior and would add more control and
datapath pressure. The better next step is Phase 5: build an end-to-end
SPHINCS sign integration model that schedules existing THASHX4, mixed
WOTS_CHAINX4, FORS, and Merkle work before committing to more RTL.
