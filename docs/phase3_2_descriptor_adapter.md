# Phase 3.2 Descriptor / Bulk-Load Adapter RTL Prototype

This phase moves the Phase 3.1B descriptor/bulk-load performance model into a
standalone synthesizable RTL prototype. It still does not connect CV32E40PX,
AXI, AHB, APB, or a full SoC fabric, and it does not change
`spx_thashx4_core`, `spx_cop_wrapper`, Keccak, or thash semantics.

New RTL:

```text
rtl/cvxif/spx_descriptor_adapter.sv
```

New testbench:

```text
sim/tb/tb_spx_descriptor_adapter.sv
```

Updated build targets:

```sh
make -C sim sim-descriptor-adapter
make -C sim test
make -C sim lint
```

## Descriptor Format

The prototype supports only:

- SPHINCS+-SHAKE-128f-simple
- `lanes = 4`
- `inblocks = 1` or `inblocks = 2`
- output = `4 x 16 bytes`

All fields are 32-bit little-endian words. Multiword buffers use word 0 as
bits `[31:0]` of the RTL vector, matching the existing standalone thashx4
testbenches.

| Byte offset | Word | Name | Meaning |
| ---: | ---: | --- | --- |
| `0x00` | 0 | `flags/status` | bit 0: inline `pub_seed`; bit 1: done; bit 2: error; bits `[7:4]`: error code |
| `0x04` | 1 | `config` | bits `[1:0]`: `inblocks`; bits `[7:4]`: lanes, must be 4; bits `[15:8]`: variant, must be 1 for SHAKE-128f-simple |
| `0x08` | 2 | `pub_seed_ptr` | pointer to 4 words, ignored when inline seed flag is set |
| `0x0c` | 3 | `addr_base_ptr` | pointer to 32 words: lane0 8 words, lane1 8 words, lane2 8 words, lane3 8 words |
| `0x10` | 4 | `input_base_ptr` | pointer to compact lane input words |
| `0x14` | 5 | `output_base_ptr` | pointer to 16 output words |
| `0x18` | 6 | `descriptor_len_words` | software-visible length hint, 8 for pointer seed or 12 for inline seed |
| `0x1c` | 7 | reserved | reserved, preserved only when included in status write beat |
| `0x20` | 8 | `inline_pub_seed[0]` | optional inline seed word 0 |
| `0x24` | 9 | `inline_pub_seed[1]` | optional inline seed word 1 |
| `0x28` | 10 | `inline_pub_seed[2]` | optional inline seed word 2 |
| `0x2c` | 11 | `inline_pub_seed[3]` | optional inline seed word 3 |

Input buffers are compact rather than wrapper-register strided:

| `inblocks` | Words per lane | Total input words |
| ---: | ---: | ---: |
| 1 | 4 | 16 |
| 2 | 8 | 32 |

The adapter requires descriptor and buffer pointers to be aligned to the active
memory beat width: 4, 8, or 16 bytes for `MEM_WORDS_PER_CYCLE = 1, 2, 4`.
The simplified interface has no byte write strobes, so descriptor status
writeback writes one full memory beat at descriptor offset `0x00`.

## Memory Interface

The RTL exposes a minimal memory-side interface:

```systemverilog
mem_valid
mem_ready
mem_we
mem_addr
mem_wdata
mem_rdata
mem_error
```

`MEM_WORDS_PER_CYCLE` selects the beat width:

| Parameter | Data width | Model |
| ---: | ---: | --- |
| 1 | 32-bit | 1 word per cycle |
| 2 | 64-bit | 2 words per cycle |
| 4 | 128-bit | 4 words per cycle |

The standalone testbench memory model is zero-wait-state:

- reads sample `mem_rdata` in the cycle where `mem_valid && mem_ready && !mem_we`;
- writes commit `mem_wdata` in the cycle where `mem_valid && mem_ready && mem_we`;
- samples `mem_error` on accepted beats to model standalone read/write response
  errors;
- all transfers are whole beats.

This is intentionally not AXI/AHB/APB. It is only a compact RTL prototype for
the memory-side descriptor movement.

## State Machine

The adapter drives `spx_thashx4_core` directly:

```text
IDLE
  -> READ_DESC
  -> PARSE_DESC
  -> READ_PUB_SEED
  -> READ_ADDR
  -> READ_INPUT
  -> START_CORE
  -> WAIT_CORE
  -> WRITE_OUTPUT
  -> WRITE_STATUS
  -> IDLE
```

Error cases detected during descriptor parsing skip the core and go directly to
`WRITE_STATUS`. Current checks cover bad config and bad alignment. Phase 3.5B
also models accepted read/write beats with `mem_error=1` as memory response
errors.

## Test Result

Run on 2026-05-13:

```sh
make -C sim sim-descriptor-adapter
make -C sim test
make -C sim lint
```

Correctness:

```text
PASS spx_descriptor_adapter width=1words_per_cycle inblocks=1,2 (200 cases)
PASS spx_descriptor_adapter width=2words_per_cycle inblocks=1,2 (200 cases)
PASS spx_descriptor_adapter width=4words_per_cycle inblocks=1,2 (200 cases)
PASS rtl lint
```

The main regression uses pointer-mode `pub_seed` for all 100 C golden vectors
per `inblocks` value and per memory width. The first case for each `inblocks`
value also runs an inline-`pub_seed` smoke check.

## Performance

Pointer-mode measured RTL stats:

| Width | `inblocks` | descriptor setup instr | memory load cycles | core active cycles | memory store cycles | total cycles | overhead cycles | active share |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1w | 1 | 1 | 60 | 27 | 17 | 107 | 80 | 25.2% |
| 1w | 2 | 1 | 76 | 27 | 17 | 123 | 96 | 22.0% |
| 2w | 1 | 1 | 30 | 27 | 9 | 69 | 42 | 39.1% |
| 2w | 2 | 1 | 38 | 27 | 9 | 77 | 50 | 35.1% |
| 4w | 1 | 1 | 15 | 27 | 5 | 50 | 23 | 54.0% |
| 4w | 2 | 1 | 19 | 27 | 5 | 54 | 27 | 50.0% |

The load cycles include:

```text
descriptor header: 8 words
pub_seed:          4 words
addr0..3:          32 words
input0..3:         16 words for inblocks=1, 32 words for inblocks=2
```

The store cycles include:

```text
output0..3:        16 words
descriptor status: 1 full memory beat
```

The total cycle counter includes the descriptor-start cycle, descriptor parse
cycle, and the core-done handoff cycle. The core active counter remains aligned
with the existing `spx_thashx4_core` latency: 27 cycles.

## Difference From Phase 3.1B Model

Phase 3.1B modeled only payload movement plus a custom-instruction status-poll
envelope. It did not implement real descriptor fetch or status writeback.

| Protocol | `inblocks` | total cycles | core cycles | overhead | active share |
| --- | ---: | ---: | ---: | ---: | ---: |
| 3.1B bulk_1w model | 1 | 97 | 27 | 70 | 27.8% |
| 3.2 RTL 1w adapter | 1 | 107 | 27 | 80 | 25.2% |
| 3.1B bulk_1w model | 2 | 113 | 27 | 86 | 23.9% |
| 3.2 RTL 1w adapter | 2 | 123 | 27 | 96 | 22.0% |
| 3.1B bulk_2w model | 1 | 63 | 27 | 36 | 42.9% |
| 3.2 RTL 2w adapter | 1 | 69 | 27 | 42 | 39.1% |
| 3.1B bulk_2w model | 2 | 71 | 27 | 44 | 38.0% |
| 3.2 RTL 2w adapter | 2 | 77 | 27 | 50 | 35.1% |
| 3.1B bulk_4w model | 1 | 45 | 27 | 18 | 60.0% |
| 3.2 RTL 4w adapter | 1 | 50 | 27 | 23 | 54.0% |
| 3.1B bulk_4w model | 2 | 49 | 27 | 22 | 55.1% |
| 3.2 RTL 4w adapter | 2 | 54 | 27 | 27 | 50.0% |

The RTL adapter is close to the Phase 3.1B model after accounting for concrete
hardware work that the model skipped:

- descriptor header fetch: `ceil(8 / MEM_WORDS_PER_CYCLE)` cycles;
- descriptor status writeback: 1 cycle;
- descriptor parse and core-done handoff: 2 cycles.

The useful payload movement matches the model: pub seed, addresses, compact
input lanes, and four 128-bit outputs are moved in the expected number of
memory beats.

## Recommendation

The descriptor path should move forward as the performance-oriented integration
path. Even with real descriptor overhead, the standalone RTL adapter is
materially better than scalar and auto-increment mappings, and the 128-bit
memory-side version keeps the core active for about half of the operation.

Recommended next step: integrate this descriptor adapter behind a real
CV-X-IF command path and a realistic memory master shim. Keep the scope bounded:
decide real bus latency/backpressure behavior, byte-strobe or read-modify-write
policy for descriptor status, and completion signaling before attempting a full
SoC integration.
