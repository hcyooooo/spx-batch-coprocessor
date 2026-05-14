# Phase 3.6 CV32E40X CV-X-IF Bring-Up

Phase 3.6 uses CV32E40X as the first real CORE-V XIF bring-up target for the
SPHINCS+ descriptor-control path. The scope is deliberately core-level and
standalone: no full SoC, no X-HEEP, no AXI/AHB/APB attachment, and no bulk data
movement over CV-X-IF.

The path brought up in this phase is:

```text
CV32E40X-style CV-X-IF issue/commit/result transaction
        |
        v
spx_cvxif_real_adapter
        |
        v
spx_cvxif_desc_adapter
        |
        v
spx_descriptor_adapter, MEM_WORDS_PER_CYCLE = 4
        |
        v
spx_mem_master_shim_mock
        |
        v
mock memory
```

Keccak, `spx_thashx4_core`, `spx_descriptor_adapter`, the descriptor ABI, and
the scalar/debug adapters are unchanged.

## Why CV32E40X

CV32E40X is the right first bring-up core because it has a documented CORE-V XIF
port at the core boundary and can offload custom instructions without modifying
the core decoder. It is smaller than a full SoC integration and lets this phase
validate the real issue/commit/result protocol before connecting any system bus.

Current third-party revisions:

| Dependency | Path | Revision |
| --- | --- | --- |
| CV32E40X | `third_party/cv32e40x` | `d952cd63bc1b4eb58cd893c28ef8283c781e345e` (`0.10.0-20-gd952cd63`) |
| CORE-V XIF spec RTL | `third_party/core-v-xif` | `d26eeab305270dd6462126b775cdbe28fb989477` (`v1.0.0-2-gd26eeab`) |

No submodules were added or fetched for this phase.

## Interface Findings

The generic CORE-V XIF reference interface is in:

```text
third_party/core-v-xif/src/core_v_xif.sv
```

It defines `interface core_v_xif` with compressed, issue, register, commit,
memory, memory-result, and result channels. In the generic reference interface,
register operands are carried on a separate register channel.

CV32E40X uses its own compatible interface definition:

```text
third_party/cv32e40x/rtl/cv32e40x_if_xif.sv
```

This is the interface used by `cv32e40x_core`. The important difference for this
bring-up is that CV32E40X carries source operands directly in `issue_req.rs` and
`issue_req.rs_valid`; there is no separate register channel on the CV32E40X top
level.

### CV32E40X Issue Interface

CV32E40X core port:

```systemverilog
cv32e40x_if_xif.cpu_issue xif_issue_if
```

Coprocessor-facing signals used by `spx_cvxif_real_adapter`:

| Signal | Direction at coprocessor | Use in Phase 3.6 |
| --- | --- | --- |
| `issue_valid` | input | Core has an offload candidate. |
| `issue_ready` | output | Adapter can accept/reject this issue transaction. |
| `issue_req.instr[31:0]` | input | RISC-V custom instruction word. |
| `issue_req.mode[1:0]` | input | Observed only; no memory access uses it in this phase. |
| `issue_req.id` | input | Captured and returned on result. |
| `issue_req.rs[0]` | input | `rs1` value for `SPX_SET_DESC`. |
| `issue_req.rs_valid[0]` | input | Required for `SPX_SET_DESC`. |
| `issue_req.ecs`, `ecs_valid` | input | Not used by SPHINCS+ control instructions. |
| `issue_resp.accept` | output | `1` for supported SPX instructions, `0` for illegal/rejected instructions. |
| `issue_resp.writeback` | output | `1` when `rd != x0`. |
| `issue_resp.dualwrite` | output | Always `0`. |
| `issue_resp.dualread` | output | Always `0`. |
| `issue_resp.loadstore` | output | Always `0`; CV-X-IF does not move bulk data. |
| `issue_resp.ecswrite` | output | Always `0`. |
| `issue_resp.exc` | output | Always `0` for accepted encodings. |

### Commit Interface

CV32E40X core port:

```systemverilog
cv32e40x_if_xif.cpu_commit xif_commit_if
```

Signals:

| Signal | Direction at coprocessor | Use in Phase 3.6 |
| --- | --- | --- |
| `commit_valid` | input | Core says the accepted instruction is committed or killed. |
| `commit.id` | input | Matched against the captured issue id. |
| `commit.commit_kill` | input | If `1`, drop the pending instruction with no side effect and no result. |

The wrapper performs architectural side effects only after `commit_valid` with
`commit_kill=0`. This means `SPX_SET_DESC`, `SPX_START`, and `SPX_CLEAR` are not
applied speculatively.

### Result Interface

CV32E40X core port:

```systemverilog
cv32e40x_if_xif.cpu_result xif_result_if
```

Signals:

| Signal | Direction at coprocessor | Use in Phase 3.6 |
| --- | --- | --- |
| `result_valid` | output | Asserted when the descriptor-control adapter response is ready. |
| `result_ready` | input | Core accepts the result. |
| `result.id` | output | Captured issue id. |
| `result.data` | output | 32-bit SPX status/result. |
| `result.rd` | output | Encoded `rd`, for traceability. |
| `result.we` | output | `1` when `rd != x0` and no internal illegal response occurred. |
| `result.ecsdata`, `ecswe` | output | Always zero. |
| `result.exc`, `exccode` | output | Normally zero. A defensive downstream illegal response maps to exception code `2`. |
| `result.err`, `dbg` | output | Always zero. |

### Interfaces Not Used

| Interface | Phase 3.6 behavior |
| --- | --- |
| Compressed | Always ready, always `accept=0`; no compressed SPX encoding yet. |
| CV-X-IF memory request/response | `mem_valid=0`, `mem_req='0`; bulk data stays on the descriptor memory-side path. |
| CV-X-IF memory result | Ignored because no CV-X-IF memory requests are issued. |
| Generic `core_v_xif` register channel | Not present on CV32E40X top-level XIF; operands arrive in issue request. |

### Enabling XIF on CV32E40X

The CV32E40X core has these relevant parameters in
`third_party/cv32e40x/rtl/cv32e40x_core.sv`:

```systemverilog
.X_EXT(1'b1),
.X_NUM_RS(2),
.X_ID_WIDTH(4),
.X_MEM_WIDTH(32),
.X_RFR_WIDTH(32),
.X_RFW_WIDTH(32),
.X_MISA(32'h0000_0000),
.X_ECS_XS(2'b00)
```

The interface instance must use matching parameters. A future full core smoke
test should include:

```systemverilog
cv32e40x_if_xif #(
  .X_NUM_RS(2),
  .X_ID_WIDTH(4),
  .X_MEM_WIDTH(32),
  .X_RFR_WIDTH(32),
  .X_RFW_WIDTH(32)
) xif ();
```

For a full CV32E40X instantiation, include/import:

| Purpose | File |
| --- | --- |
| CV32E40X package | `third_party/cv32e40x/rtl/include/cv32e40x_pkg.sv` |
| CV32E40X XIF interface | `third_party/cv32e40x/rtl/cv32e40x_if_xif.sv` |
| Generic CORE-V XIF reference, if needed for spec-level models | `third_party/core-v-xif/src/core_v_xif.sv` |

The Phase 3.6 standalone transaction-level test only needs
`cv32e40x_if_xif.sv`; it does not instantiate `cv32e40x_core`.

### Official Examples

`third_party/core-v-xif/src/test/test.sv` only instantiates the generic
`core_v_xif` interface as a smoke/reference test. It is not a coprocessor
example.

`third_party/cv32e40x/docs/user_manual/source/integration.rst` documents the
core instantiation and XIF parameters. `third_party/cv32e40x/docs/user_manual/source/x_ext.rst`
lists the top-level XIF signal mapping. `third_party/cv32e40x/tb/README.md`
states that the CV32E40X repository itself does not contain the full simulation
environment; full verification lives in `core-v-verif`.

## Custom Instruction Encoding

Temporary Phase 3.6 encoding uses RISC-V `custom-0`:

```text
31        25 24   20 19   15 14   12 11    7 6       0
+-----------+-------+-------+-------+-------+---------+
| funct7    | rs2   | rs1   |funct3 | rd    | opcode  |
+-----------+-------+-------+-------+-------+---------+
| 0x5a      | 0     | rs1   | op    | rd    | 0x0b    |
```

| Instruction | opcode | funct7 | funct3 | rs2 | rs1 | rd |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| `SPX_SET_DESC rs1` | `0x0b` | `0x5a` | `0` | `x0` | descriptor base address register | optional status destination |
| `SPX_START` | `0x0b` | `0x5a` | `1` | `x0` | `x0` | optional status destination |
| `SPX_STATUS rd` | `0x0b` | `0x5a` | `2` | `x0` | `x0` | status destination |
| `SPX_CLEAR` | `0x0b` | `0x5a` | `3` | `x0` | `x0` | optional status destination |

`rd=x0` is legal and suppresses register writeback, but a CV-X-IF result is
still returned to complete the accepted instruction.

Draft C inline assembly:

```c
#define SPX_CUSTOM0 0x0b
#define SPX_FUNCT7  0x5a

static inline uint32_t spx_set_desc(uint32_t desc)
{
    uint32_t status;
    asm volatile (".insn r 0x0b, 0, 0x5a, %0, %1, x0"
                  : "=r"(status) : "r"(desc));
    return status;
}

static inline uint32_t spx_start(void)
{
    uint32_t status;
    asm volatile (".insn r 0x0b, 1, 0x5a, %0, x0, x0"
                  : "=r"(status));
    return status;
}

static inline uint32_t spx_status(void)
{
    uint32_t status;
    asm volatile (".insn r 0x0b, 2, 0x5a, %0, x0, x0"
                  : "=r"(status));
    return status;
}

static inline uint32_t spx_clear(void)
{
    uint32_t status;
    asm volatile (".insn r 0x0b, 3, 0x5a, %0, x0, x0"
                  : "=r"(status));
    return status;
}
```

### Status Behavior

The 32-bit status returned by the existing descriptor-control adapter is:

| Bit(s) | Meaning |
| ---: | --- |
| `0` | busy |
| `1` | sticky done |
| `2` | sticky error |
| `7:4` | sticky descriptor error code |

`SPX_START` while busy is legal. It does not issue a second `desc_start`; it
returns status with `busy=1`.

`SPX_CLEAR` clears sticky done/error/error_code in the CV-X-IF descriptor shell.
It does not stop an active descriptor operation.

Unsupported encodings are rejected at issue time with `issue_resp.accept=0`.
The CV32E40X pipeline will then treat the instruction as illegal. A defensive
path remains in `spx_cvxif_real_adapter`: if the simplified descriptor-control
adapter ever reports `instr_illegal` for an accepted instruction, the XIF result
raises `exc=1` with illegal-instruction exception code `2`.

## RTL Added

New wrapper:

```text
rtl/cvxif/spx_cvxif_real_adapter.sv
```

The wrapper:

- decodes the temporary `custom-0` SPX instructions;
- accepts only descriptor-control instructions;
- captures issue id, rd, rs1 operand, and decoded operation;
- waits for commit before applying side effects;
- maps committed operations to the existing simplified
  `instr_valid/instr_op/instr_rs1` interface;
- returns the simplified adapter response over real CV32E40X result;
- rejects illegal encodings;
- holds `issue_ready=0` for supported SPX instructions while one accepted
  instruction is pending;
- leaves CV-X-IF memory unused.

The existing `spx_cvxif_desc_adapter`, `spx_descriptor_adapter`, memory shim,
and thash core semantics were not changed.

## Testbench

New testbench:

```text
sim/tb/tb_spx_cvxif_real_adapter.sv
```

It uses a CV32E40X-style transaction driver instead of a full core:

```text
cvxif_transaction_driver
  -> cv32e40x_if_xif interface
  -> spx_cvxif_real_adapter
  -> spx_cvxif_desc_adapter
  -> spx_descriptor_adapter_4w
  -> spx_mem_master_shim_mock
  -> mock bus/memory
```

Covered behavior:

- `SPX_SET_DESC`;
- `SPX_START`;
- repeated `SPX_STATUS` polling;
- output buffer check against C-generated golden vectors;
- `inblocks=1` and `inblocks=2`;
- illegal instruction rejection;
- repeated `SPX_START` while busy;
- descriptor error propagation through status;
- assertion that `xif.mem_valid` remains zero.

The test still uses the C golden vectors generated by `sim/gen_thashx4_vectors.c`.

## Core-Level Smoke Status

This phase does not instantiate the full `cv32e40x_core`.

Reason: the CV32E40X repository states that the full simulation environment is
provided by `core-v-verif`, not by the core repository itself. Pulling that in
would turn this phase into verification-environment integration rather than
focused CV-X-IF control-path bring-up.

The transaction-level test already exercises the real CV32E40X XIF interface
shape and protocol channels used by the core. A full core smoke test is deferred
to Phase 3.7, after a minimal instruction/data memory harness or a `core-v-verif`
path is selected.

## Build Targets

Updated targets:

```sh
make -C sim sim-cvxif-real-adapter
make -C sim lint-spx-cvxif
make -C sim lint
make -C sim test
```

`lint-spx-cvxif` uses a small lint harness because linting an interface-port
module directly makes Verilator treat CPU-side XIF signals as undriven by
construction.

## Test Results

Run on 2026-05-14:

```sh
make -C sim sim-cvxif-real-adapter
make -C sim lint-spx-cvxif
make -C sim lint
make -C sim test
```

Results:

```text
PASS spx_cvxif_real_adapter CV32E40X-style CV-X-IF transaction tests
PASS rtl lint
```

Zero-latency performance:

| Mode | `inblocks` | CV-X-IF instruction count | status polls | descriptor adapter total cycles | memory load cycles | core cycles | memory store cycles | memory shim stall cycles | total cycles | active share | `xif.mem_valid` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| zero latency | 1 | 13 | 10 | 50 | 15 | 27 | 5 | 0 | 51 | 52.9% | 0 |
| zero latency | 2 | 14 | 11 | 54 | 19 | 27 | 5 | 0 | 56 | 48.2% | 0 |

Split response delay smoke:

| Mode | `inblocks` | CV-X-IF instruction count | status polls | descriptor adapter total cycles | memory load cycles | core cycles | memory store cycles | memory shim stall cycles | total cycles | active share | `xif.mem_valid` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| split response delay | 1 | 23 | 20 | 100 | 45 | 27 | 25 | 48 | 101 | 26.7% | 0 |
| split response delay | 2 | 26 | 23 | 112 | 57 | 27 | 25 | 56 | 116 | 23.3% | 0 |

Additional checks:

```text
PHASE36_REAL_CVXIF_ILLEGAL_PASS rejected_count=2
PHASE36_REAL_CVXIF_BUSY_REPEAT_PASS status_polls=16 final_status=0x00000002
PHASE36_REAL_CVXIF_DESCRIPTOR_ERROR_PASS error_code=0x1 status_polls=1 status=0x00000016
```

## Comparison With Phase 3.5C

Phase 3.5C zero-latency memory-shim results:

| `inblocks` | total cycles | descriptor adapter cycles | memory load cycles | core cycles | memory store cycles | shim stall cycles | active share |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 51 | 50 | 15 | 27 | 5 | 0 | 52.9% |
| 2 | 55 | 54 | 19 | 27 | 5 | 0 | 49.1% |

Phase 3.6 keeps the descriptor path unchanged:

| `inblocks` | Phase 3.5C descriptor cycles | Phase 3.6 descriptor cycles | Phase 3.5C load/core/store | Phase 3.6 load/core/store |
| ---: | ---: | ---: | --- | --- |
| 1 | 50 | 50 | 15 / 27 / 5 | 15 / 27 / 5 |
| 2 | 54 | 54 | 19 / 27 / 5 | 19 / 27 / 5 |

The real wrapper does not add descriptor, memory, or core datapath overhead.
The CPU-visible `total_cycles` are the same for `inblocks=1` and one cycle later
for `inblocks=2` in the transaction driver because the real issue/commit/result
handshake models a multi-cycle status instruction instead of the old one-cycle
simplified instruction pulse. This affects polling cadence, not the descriptor
adapter or memory-side performance path.

The instruction count is lower than Phase 3.5C because each real CV-X-IF status
poll consumes several transaction-driver cycles, so the test observes fewer poll
instructions before descriptor completion. The important Phase 3.6 result is
that `xif.mem_valid=0` for all tests and the 128-bit memory-side path still
matches Phase 3.5C.

## Phase 3.7 Plan

Recommended next steps:

- add a minimal CV32E40X core-level smoke harness with instruction memory, data
  memory, and the real XIF wrapper;
- compile a tiny program using the inline asm above;
- run `SET_DESC`, `START`, `STATUS` polling, and output verification from core
  software;
- decide whether to reuse `core-v-verif` or keep a local minimal core harness;
- keep AXI/AHB/APB and X-HEEP out until the core-level smoke is stable.

