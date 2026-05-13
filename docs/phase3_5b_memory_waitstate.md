# Phase 3.5B Memory Wait-State, Backpressure, and Error Modeling

Phase 3.5B extends the standalone Phase 3.5A descriptor-control integration
test. It still does not connect CV32E40PX, AXI, AHB, APB, or a full SoC fabric.
It also does not change Keccak, thash, `spx_thashx4_core`, or the descriptor
ABI. Bulk data remains on the descriptor adapter memory-side path.

The updated standalone path is:

```text
SPX_SET_DESC / SPX_START / SPX_STATUS / SPX_CLEAR
        |
        v
spx_cvxif_desc_adapter
        |
        v
spx_descriptor_adapter, MEM_WORDS_PER_CYCLE = 4
        |
        v
enhanced mock memory / memory master shim model
```

## RTL Interface Delta

The descriptor adapter memory-side interface now includes one response error
signal:

```systemverilog
mem_valid
mem_ready
mem_we
mem_addr
mem_wdata
mem_rdata
mem_error
```

`mem_error` is sampled only on an accepted beat, meaning
`mem_valid && mem_ready`. It is not AXI, AHB, APB, or a final bus protocol; it is
a compact standalone hook for modeling future memory-master response errors.

Error codes:

| Code | Name | Meaning |
| ---: | --- | --- |
| `0x0` | `ERR_NONE` | No error. |
| `0x1` | `ERR_BAD_CONFIG` | Invalid `inblocks`, lane count, or variant. |
| `0x2` | `ERR_BAD_ALIGN` | Descriptor or buffer pointer alignment error. |
| `0x3` | `ERR_MEM_READ` | Read beat accepted with `mem_error=1`. |
| `0x4` | `ERR_MEM_WRITE` | Write beat accepted with `mem_error=1`. |

The descriptor status word still uses bit 1 for done, bit 2 for error, and bits
`[7:4]` for `error_code`. CV-X-IF status mirrors the same error bit and
`error_code` in bits `[7:4]`.

## Memory Wait-State Model

The enhanced mock memory supports independent read and write wait counts:

```text
read_wait_cycles
write_wait_cycles
```

For each memory beat, the model holds `mem_ready=0` for the configured wait
cycles, then permits the beat to be accepted. A zero wait count accepts the beat
as soon as the adapter presents it.

The model covers:

- zero-wait baseline;
- fixed one-cycle wait per accepted read and write beat;
- fixed two-cycle wait per accepted read and write beat;
- fixed four-cycle wait smoke coverage;
- split latency smoke coverage with `read_wait=2` and `write_wait=4`.

The descriptor adapter performance counters now count time spent in load/store
states, including wait cycles. Zero-wait results remain unchanged because every
load/store state cycle is also an accepted memory beat.

## Backpressure Model

Random backpressure is modeled by independently gating `mem_ready` with a
deterministic xorshift32 stream:

```text
mem_ready = wait_state_ready && random_ready
random_ready = (rng % 100) < random_ready_pct
```

The regression covers:

- `random_ready_pct=50`
- `random_ready_pct=75`

The seeds are fixed, so the regression is deterministic while still exercising
nonuniform ready/valid stalls.

## Error Injection Model

The mock memory can inject one error on a selected accepted beat:

| Injection | Memory behavior | Adapter result |
| --- | --- | --- |
| read bus error | `mem_error=1` on a read beat | `ERR_MEM_READ` |
| read data error | corrupt lane 0 read data and assert `mem_error=1` | `ERR_MEM_READ` |
| write response error | `mem_error=1` on an output write beat | `ERR_MEM_WRITE` |

Silent read-data corruption without `mem_error` is not checked by the RTL. The
standalone model treats "read data error" as a memory response that carries both
bad data and an error indication.

Write response errors are injected on output writes, not on the final descriptor
status write, so the adapter can still write back the final descriptor error
status for the test.

## Alignment Error Test

The Phase 3.5B wait target checks these unaligned cases:

| Test | Expected error |
| --- | --- |
| descriptor address unaligned | `ERR_BAD_ALIGN` |
| `pub_seed_ptr` unaligned | `ERR_BAD_ALIGN` |
| `addr_base_ptr` unaligned | `ERR_BAD_ALIGN` |
| `input_base_ptr` unaligned | `ERR_BAD_ALIGN` |
| `output_base_ptr` unaligned | `ERR_BAD_ALIGN` |

Each case verifies all three observable paths:

- adapter reaches done with error set;
- descriptor status writeback has done, error, and error_code set;
- CV-X-IF `SPX_STATUS` reports error and the expected error_code.

For the descriptor-address alignment case, the standalone adapter writes error
status at the supplied descriptor address even though the address is unaligned.
This behavior is for the standalone model only; a real bus shim may later map
unaligned descriptor starts to an immediate local error or a bus error response.

## Bad Descriptor Config Test

The Phase 3.5B wait target checks:

| Test | Expected error |
| --- | --- |
| `inblocks=0` | `ERR_BAD_CONFIG` |
| `inblocks=3` | `ERR_BAD_CONFIG` |
| lanes not equal to 4 | `ERR_BAD_CONFIG` |
| variant not equal to SHAKE-128f-simple | `ERR_BAD_CONFIG` |

`descriptor_len_words` is currently not checked by the RTL. The regression
documents this by running `descriptor_len_words=1` and confirming that the
descriptor completes without error. The field remains a software-visible length
hint for now.

## Performance Statistics

Run on 2026-05-13:

```sh
make -C sim sim-cvxif-desc-adapter-wait
make -C sim lint
```

Correctness:

```text
PASS spx_cvxif_desc_adapter_wait memory wait/backpressure/error tests
PASS rtl lint
```

The table below uses one golden vector per `inblocks` value. Cycle counts are
data-independent for fixed wait-state modes; random modes use deterministic
seeds.

| Mode | `inblocks` | total cycles | memory load cycles | core cycles | memory store cycles | active share | status polls | instruction count | error count |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| zero wait | 1 | 51 | 15 | 27 | 5 | 52.9% | 50 | 53 | 0 |
| zero wait | 2 | 55 | 19 | 27 | 5 | 49.1% | 54 | 57 | 0 |
| fixed 1-cycle wait | 1 | 71 | 30 | 27 | 10 | 38.0% | 70 | 73 | 0 |
| fixed 1-cycle wait | 2 | 79 | 38 | 27 | 10 | 34.2% | 78 | 81 | 0 |
| fixed 2-cycle wait | 1 | 91 | 45 | 27 | 15 | 29.7% | 90 | 93 | 0 |
| fixed 2-cycle wait | 2 | 103 | 57 | 27 | 15 | 26.2% | 102 | 105 | 0 |
| random ready 50% | 1 | 66 | 27 | 27 | 8 | 40.9% | 65 | 68 | 0 |
| random ready 50% | 2 | 71 | 28 | 27 | 12 | 38.0% | 70 | 73 | 0 |
| random ready 75% | 1 | 58 | 22 | 27 | 5 | 46.6% | 57 | 60 | 0 |
| random ready 75% | 2 | 68 | 29 | 27 | 8 | 39.7% | 67 | 70 | 0 |

Additional smoke modes:

| Mode | `inblocks` | total cycles | memory load cycles | core cycles | memory store cycles | active share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| fixed 4-cycle wait | 1 | 131 | 75 | 27 | 25 | 20.6% |
| fixed 4-cycle wait | 2 | 151 | 95 | 27 | 25 | 17.9% |
| split read2/write4 | 1 | 101 | 45 | 27 | 25 | 26.7% |
| split read2/write4 | 2 | 113 | 57 | 27 | 25 | 23.9% |

## Latency Impact

The 4-word descriptor path is read-heavy:

| `inblocks` | Read beats | Write beats |
| ---: | ---: | ---: |
| 1 | 15 | 5 |
| 2 | 19 | 5 |

Because of this, read latency has the largest throughput impact. One fixed wait
cycle per beat adds 15 load cycles for `inblocks=1` and 19 load cycles for
`inblocks=2`, while store latency adds 5 cycles in both cases. The
`split_read2_write4` smoke test confirms that high write latency is visible, but
the read side still dominates once input size grows from `inblocks=1` to
`inblocks=2`.

The core remains 27 cycles in all successful modes. Active share drops as memory
stalls grow:

- `inblocks=1`: 52.9% at zero wait, 38.0% at fixed 1-cycle wait, 29.7% at fixed 2-cycle wait.
- `inblocks=2`: 49.1% at zero wait, 34.2% at fixed 1-cycle wait, 26.2% at fixed 2-cycle wait.

## Phase 3.5C Direction

Phase 3.5C can proceed into a memory master shim mock, but it should remain
standalone. The next boundary should model request/response sequencing,
outstanding-operation policy, byte-lane or read-modify-write behavior for
descriptor status, and bus response mapping. It should not yet connect a real
CV32E40PX core, AXI/AHB/APB fabric, or a full SoC.

Recommended Phase 3.5C scope:

- keep `spx_cvxif_desc_adapter` as descriptor-control only;
- keep `spx_descriptor_adapter_4w` as the bulk data engine;
- wrap the simple memory-side interface in a mock memory-master shim;
- preserve the new `mem_error` response hook or map it from the shim response;
- add tests for delayed responses and descriptor-status writeback policy;
- defer real bus protocol integration until the shim contract is stable.
