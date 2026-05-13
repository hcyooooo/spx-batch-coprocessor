# Phase 3.1A CV-X-IF-style Adapter Plan and Standalone Simulation

This phase adds a standalone CV-X-IF-style shell above the existing
`spx_cop_wrapper`. It intentionally does not connect CV32E40PX, AXI, AHB, APB,
or a full SoC fabric. The goal is to validate a custom-instruction access model
and quantify instruction/data movement overhead before binding to real CV-X-IF
signals.

The Phase 2 `spx_thashx4_core` algorithm semantics and the Phase 3.0 wrapper
register map are unchanged.

## Scope

New RTL:

```text
rtl/cvxif/spx_cvxif_adapter.sv
```

New testbench:

```text
sim/tb/tb_spx_cvxif_adapter.sv
```

Updated build targets:

```sh
make -C sim sim-cvxif-adapter
make -C sim test
make -C sim lint
```

## Provisional Instruction Mapping

The adapter uses an 8-bit `instr_op` field as a stand-in for future RISC-V
custom opcode/funct decoding. These are adapter simulation opcodes, not final
ISA encodings.

| Instruction | `instr_op` | Operand use | Wrapper command mapping | Response |
| --- | ---: | --- | --- | --- |
| `SPX_WR addr, rs1` | `0x01` | `instr_addr=addr`, `instr_rs1=data` | `cmd_op=CMD_WRITE`, `cmd_addr=addr`, `cmd_wdata=rs1` | `instr_resp_data=0` |
| `SPX_RD rd, addr` | `0x02` | `instr_addr=addr`, `instr_rd=rd` | `cmd_op=CMD_READ`, `cmd_addr=addr`, `cmd_wdata=0` | `instr_resp_data=rsp_rdata` |
| `SPX_START` | `0x03` | operands ignored | `cmd_op=CMD_START`, `cmd_addr=0`, `cmd_wdata=0` | `instr_resp_data=0` |
| `SPX_STATUS rd` | `0x04` | `instr_rd=rd` | `cmd_op=CMD_READ`, `cmd_addr=0x51`, `cmd_wdata=0` | `instr_resp_data=status` |
| `SPX_CLR` | `0x05` | operands ignored | `cmd_op=CMD_WRITE`, `cmd_addr=0x51`, `cmd_wdata=0x00000006` | `instr_resp_data=0` |

Wrapper command constants are inherited from `spx_cop_wrapper`:

| Wrapper opcode | Value |
| --- | ---: |
| `CMD_WRITE` | `0x01` |
| `CMD_READ` | `0x02` |
| `CMD_START` | `0x03` |

`SPX_STATUS` reads the existing status register at `0x51`:

| Bit(s) | Meaning |
| ---: | --- |
| `0` | `busy` |
| `1` | sticky `done` |
| `2` | sticky `error` |
| `9:8` | `inblocks` |
| `19:16` | wrapper error code |

`SPX_CLR` writes the wrapper's W1C bits for `done` and `error`. It is optional
for the current flow because `CMD_START` already clears sticky `done` and clears
sticky `error` on a valid start.

## Handshake Semantics

The simplified adapter request interface is:

```text
instr_valid
instr_ready
instr_op
instr_addr
instr_rs1
instr_rd
```

The simplified adapter response/status interface is:

```text
instr_resp_valid
instr_resp_data
instr_resp_rd
instr_illegal
instr_busy
instr_done
instr_error
```

Instruction handling:

1. The adapter accepts one instruction when `instr_valid && instr_ready`.
2. For legal instructions, it drives one wrapper command using
   `cmd_valid/cmd_ready/cmd_op/cmd_addr/cmd_wdata`.
3. It waits for wrapper `rsp_valid`, then returns `instr_resp_valid`.
4. For `SPX_RD` and `SPX_STATUS`, `instr_resp_data` carries wrapper
   `rsp_rdata`.
5. For `SPX_WR`, `SPX_START`, and `SPX_CLR`, `instr_resp_data` is zero.
6. Unsupported `instr_op` values produce `instr_resp_valid` with
   `instr_illegal=1` and do not issue a wrapper command.

This first shell is deliberately one-inflight: it does not accept the next
instruction until the previous instruction response has returned. In the
standalone testbench this makes the external custom-instruction cost exactly
two cycles per instruction. Reads and `SPX_STATUS` can still be issued while the
accelerator is busy because the underlying wrapper accepts reads during busy.

## Adapter Architecture

```text
custom instruction request
        |
        v
  spx_cvxif_adapter
    - instruction decoder
    - one-inflight request/response FSM
    - illegal instruction response path
        |
        v
  spx_cop_wrapper
    - unchanged 32-bit command/register protocol
    - unchanged register map
        |
        v
  spx_thashx4_core
    - unchanged thashx4 algorithm RTL
```

The adapter does not understand the thash datapath layout directly. It only
uses the wrapper command protocol and documented register addresses.

## Testbench Flow

`tb_spx_cvxif_adapter` reads the same C-generated golden vectors as the
standalone core and wrapper tests:

```text
sim/vectors/thashx4_inblocks1.hex
sim/vectors/thashx4_inblocks2.hex
sim/vectors/thashx4_expected.hex
```

Per operation, the testbench performs:

1. `SPX_WR` pub seed words `0x00..0x03`.
2. `SPX_WR` address words for lanes 0..3 at `0x10..0x2f`.
3. `SPX_WR` input words for lanes 0..3 at `0x30..0x4f`.
   - `inblocks=1`: writes 4 words per lane.
   - `inblocks=2`: writes 8 words per lane.
4. `SPX_WR` config register `0x50`.
5. `SPX_START`.
6. Polls `SPX_STATUS` until `done=1`.
7. `SPX_RD` output words at `0x60..0x6f`.
8. Compares all four 128-bit outputs against the C golden output.

Coverage:

- 100 random vectors for `inblocks=1`.
- 100 random vectors for `inblocks=2`.

## Simulation Result

Run on 2026-05-13:

```sh
make -C sim sim-cvxif-adapter
make -C sim test
make -C sim lint
```

Adapter test output:

```text
CVXIF_ADAPTER_STATS inblocks=1:
  write_instr = 53
  read_instr = 16
  start_instr = 1
  status_instr = 14
  total_instr = 84
  total_cycles = 168
  core_cycles = 27
  overhead_cycles = 141
CVXIF_ADAPTER_STATS inblocks=2:
  write_instr = 69
  read_instr = 16
  start_instr = 1
  status_instr = 14
  total_instr = 100
  total_cycles = 200
  core_cycles = 27
  overhead_cycles = 173
PASS spx_cvxif_adapter inblocks=1,2 (200 cases)
```

Full regression also passed:

```text
PASS keccakx4_core (128 cases)
PASS thashx4_core inblocks=1,2 (200 cases)
PASS spx_cop_wrapper inblocks=1,2 (200 cases)
PASS spx_cvxif_adapter inblocks=1,2 (200 cases)
PASS rtl lint
```

## Interface Overhead

The reported `core_cycles` are measured accelerator busy cycles. For both
`inblocks=1` and `inblocks=2`, the active thashx4 operation is 27 cycles.

| Metric | `inblocks=1` | `inblocks=2` |
| --- | ---: | ---: |
| `write_instr` | 53 | 69 |
| `read_instr` | 16 | 16 |
| `start_instr` | 1 | 1 |
| `status_instr` | 14 | 14 |
| `total_instr` | 84 | 100 |
| `total_cycles` | 168 | 200 |
| `core_cycles` | 27 | 27 |
| `overhead_cycles` | 141 | 173 |
| Active-cycle share | 16.1% | 13.5% |

In this one-inflight adapter model:

```text
total_cycles = 2 * total_instr
overhead_cycles = total_cycles - core_cycles
```

The scalar instruction protocol is therefore strongly data-movement limited.
Even for `inblocks=1`, the interface spends more than five times the core
latency on command, data, polling, and output movement. For `inblocks=2`, the
extra input words push the overhead above six times the core latency.

## Optimization Direction

The scalar mapping is useful as a functional bring-up path, but it should not be
treated as the final performance interface.

Recommended next experiments:

| Candidate instruction | Intent | Caveat |
| --- | --- | --- |
| `SPX_LOAD_ADDR4` | Reduce software-visible address setup for four lanes. | A 32-bit custom instruction cannot carry all address data by itself; it needs an adapter-side sequence, packed register convention, or memory-side source. |
| `SPX_LOAD_IN4` | Reduce input setup instruction count. | Same data-source issue; true bulk load eventually needs a wider path, a queue, or memory access. |
| `SPX_START_THASHX4` | Combine config/start and possibly clear status. | Low risk and easy to model; saves only a few instructions. |
| `SPX_READ_OUT4` | Reduce output read overhead. | A single 32-bit response cannot return four 128-bit outputs, so this needs a multi-response convention or memory/store path. |

Because this phase explicitly avoids AXI/AHB/APB and a full SoC, the best next
step is a Phase 3.1B coarse-grain adapter simulation that models macro
instructions and their assumed data source before implementing real CV-X-IF
signals. Useful options include:

- an auto-increment write/read window to reduce decode/control overhead;
- a small adapter-side command FIFO so the CPU can issue back-to-back requests;
- a pseudo bulk-load model to estimate the benefit of future memory-side
  movement;
- software conventions that skip rewriting unchanged `pub_seed` or address
  words across batches.

## CV32E40PX Integration Recommendation

Proceeding to real CV32E40PX plus CV-X-IF integration is reasonable for
functional validation because the wrapper boundary is stable and the scalar
instruction mapping is now tested against golden vectors.

For performance validation, do not stop at this scalar mapping. The measured
overhead shows that the current interface is dominated by data movement rather
than Keccak/thash compute. Before spending significant effort on SoC-level
integration, run one more standalone coarse-instruction simulation to decide
whether the next interface should remain pure custom-instruction scalar access
or grow a bulk movement mechanism.
