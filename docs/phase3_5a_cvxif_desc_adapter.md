# Phase 3.5A CV-X-IF Descriptor-Control Adapter

Phase 3.5A adds a standalone CV-X-IF-facing descriptor-control shell for the
existing descriptor path. It does not connect CV32E40PX, AXI, AHB, APB, or a
full SoC fabric. It also does not change Keccak, thash, `spx_thashx4_core`, or
`spx_descriptor_adapter`.

The performance path remains descriptor driven:

```text
software prepares descriptor and buffers in memory
CV-X-IF shell receives descriptor address/start/status/clear instructions
spx_descriptor_adapter reads and writes bulk data through its memory-side path
spx_thashx4_core runs unchanged
software observes status and reads the output buffer from memory
```

New RTL:

```text
rtl/cvxif/spx_cvxif_desc_adapter.sv
```

New testbench:

```text
sim/tb/tb_spx_cvxif_desc_adapter.sv
```

Updated build targets:

```sh
make -C sim sim-cvxif-desc-adapter
make -C sim test
make -C sim lint
```

## Adapter Architecture

`spx_cvxif_desc_adapter` is intentionally thin. It only decodes the simplified
instruction request and drives the descriptor adapter control pins:

```text
instr_valid/instr_ready/instr_op/instr_rs1
        |
        v
spx_cvxif_desc_adapter
  - descriptor address register
  - start pulse generation
  - sticky done/error capture
  - status and illegal-instruction response
        |
        v
spx_descriptor_adapter
  - descriptor fetch
  - pub_seed/address/input memory loads
  - unchanged thashx4 core control
  - output and descriptor-status memory stores
```

The CV-X-IF-facing shell has no ports for `pub_seed`, address words, input
blocks, or output blocks. All bulk data remains behind the descriptor adapter's
memory-side interface.

## Instruction Definition

The opcodes are standalone simulation opcodes, not final ISA encodings.

| Instruction | Opcode | Operand/result | Meaning |
| --- | ---: | --- | --- |
| `SPX_SET_DESC rs1` | `0x10` | `rs1 = descriptor base address` | Store the descriptor base address register. |
| `SPX_START` | `0x11` | response = status | If the descriptor adapter is not busy, issue a one-cycle `desc_start` pulse using the stored descriptor address. |
| `SPX_STATUS rd` | `0x12` | `rd = status` | Return current busy plus sticky done/error state. |
| `SPX_CLEAR` | `0x13` | response = status after clear | Clear sticky done/error in the CV-X-IF shell. |
| `SPX_WAIT rd` | `0x14` | `rd = status` | Polling-style helper for Phase 3.5A; it does not block internally yet. |

Unsupported opcodes return `instr_resp_valid=1` with `instr_illegal=1`.

`SPX_START` while busy does not launch a second operation. The response reports
the current status, including `busy=1`.

## Status Definition

The CV-X-IF shell returns a compact 32-bit status word:

| Bit(s) | Name | Meaning |
| ---: | --- | --- |
| `0` | `busy` | Descriptor adapter is active. |
| `1` | `done` | Sticky completion observed by the CV-X-IF shell. |
| `2` | `error` | Sticky error observed by the CV-X-IF shell. |
| `7:4` | `error_code` | Descriptor adapter error code captured when `error=1`. |

`SPX_CLEAR` clears the shell's sticky `done/error/error_code`. A later
`SPX_START` also clears sticky state before launching the next descriptor.

## Standalone Testbench

`tb_spx_cvxif_desc_adapter` instantiates:

- `spx_cvxif_desc_adapter`;
- `spx_descriptor_adapter` with `MEM_WORDS_PER_CYCLE=4`;
- a zero-wait-state 128-bit mock memory.

The testbench CPU stream is:

```text
SPX_SET_DESC descriptor_base
SPX_START
repeat SPX_STATUS until done/error
read output buffer from mock memory
SPX_WAIT smoke check
SPX_CLEAR
```

The mock memory is word-addressed internally and presents the descriptor
adapter's existing simplified memory interface:

```text
mem_valid
mem_ready = 1
mem_we
mem_addr
mem_wdata[127:0]
mem_rdata[127:0]
```

Descriptors and buffers are 16-byte aligned. The descriptor layout and compact
input/output buffer layout match Phase 3.2. The test uses the same C-generated
golden vectors as the standalone core and descriptor-adapter regressions:

- 100 vectors for `inblocks=1`;
- 100 vectors for `inblocks=2`;
- the first vector in each phase also runs an inline-`pub_seed` smoke check;
- an illegal-opcode smoke check verifies the illegal response path.

## Test Result

Run on 2026-05-13:

```sh
make -C sim sim-cvxif-desc-adapter
make -C sim lint
```

Correctness:

```text
PASS spx_cvxif_desc_adapter width=4words_per_cycle inblocks=1,2 (200 cases)
PASS rtl lint
```

Measured pointer-mode stats:

| `inblocks` | instruction count | status polls | descriptor adapter total cycles | memory load cycles | core cycles | memory store cycles | total cycles | active share |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 53 | 50 | 50 | 15 | 27 | 5 | 51 | 52.9% |
| 2 | 57 | 54 | 54 | 19 | 27 | 5 | 55 | 49.1% |

The instruction count includes `SPX_SET_DESC`, `SPX_START`, every `SPX_STATUS`
poll, and `SPX_CLEAR`. `SPX_WAIT` is tested as a helper but is not included in
the per-operation count. The test polls status every cycle, so these are
worst-case polling instruction counts for this zero-wait standalone setup.

`descriptor_adapter_total_cycles` is the existing descriptor adapter
`perf_total_cycles` counter. `total_cycles` is the CPU-visible start-to-done
status observation window in the standalone instruction stream.

## Overhead Versus Phase 3.1A Scalar Mapping

Phase 3.1A used scalar `SPX_WR` and `SPX_RD` instructions to move all 32-bit
pub seed, address, input, status, and output words through the custom
instruction interface.

| Protocol | `inblocks` | instruction count | total cycles | core cycles | active share |
| --- | ---: | ---: | ---: | ---: | ---: |
| Phase 3.1A scalar | 1 | 84 | 168 | 27 | 16.1% |
| Phase 3.5A descriptor-control | 1 | 53 | 51 | 27 | 52.9% |
| Phase 3.1A scalar | 2 | 100 | 200 | 27 | 13.5% |
| Phase 3.5A descriptor-control | 2 | 57 | 55 | 27 | 49.1% |

The important change is not only the lower instruction count. The Phase 3.5A
CV-X-IF shell no longer carries any bulk thash data. Even with one status poll
per cycle, instruction traffic is reduced by 31 instructions for `inblocks=1`
and 43 instructions for `inblocks=2`. With a less aggressive polling policy,
interrupt, or future blocking wait semantics, the control instruction count can
fall closer to `SET_DESC + START + CLEAR + a few status checks`.

The scalar/debug path should remain available for bring-up and diagnostics, but
it is not the performance path.

## Phase 3.5B Direction

Phase 3.5B should add memory wait-state and backpressure modeling without
changing the CV-X-IF descriptor-control contract:

- keep `spx_cvxif_desc_adapter` limited to descriptor address, start, status,
  clear, and optional wait;
- keep `spx_descriptor_adapter` as the descriptor parser and core driver;
- place wait-state behavior on the memory side by driving `mem_ready` low;
- model read latency, write response latency, and backpressure in a memory
  master shim or enhanced mock memory;
- add alignment and bus-error tests for descriptor, pub seed, address, input,
  output, and descriptor-status writeback;
- keep `descriptor_4w` as the main 128-bit path and `descriptor_2w` as the
  fallback if a future target cannot support 128-bit memory beats.

Do not use Phase 3.5B to connect a full CV32E40PX SoC or to move bulk data back
through CV-X-IF instructions.
