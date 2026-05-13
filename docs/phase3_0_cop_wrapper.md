# Phase 3.0 Standalone SPHINCS thashx4 Coprocessor Wrapper

This phase adds a standalone coprocessor-style register wrapper around the
existing `spx_thashx4_core`. It intentionally does not connect CV32E40PX,
CV-X-IF, AXI, AHB, APB, or any SoC fabric.

The wrapped algorithm remains the Phase 2 RTL:

- SPHINCS+-SHAKE-128f-simple
- `inblocks=1` and `inblocks=2`
- four lanes per operation
- `spx_thashx4_core` algorithm semantics unchanged

## RTL Scope

New wrapper:

```text
rtl/wrapper/spx_cop_wrapper.sv
```

The wrapper instantiates:

```text
rtl/core/spx_thashx4_core.sv
```

The wrapper narrows the wide standalone core ports into a 32-bit command/data
interface that can later be mapped to CV-X-IF custom instruction operands or an
instruction-driven micro-protocol.

## Architecture

```text
cmd_valid/cmd_ready/cmd_op/cmd_addr/cmd_wdata
        |
        v
  spx_cop_wrapper
    - pub_seed register, 128 bits
    - addr lane registers, 4 x 256 bits
    - input lane registers, 4 x 256 bits
    - config register, inblocks
    - output lane registers, 4 x 128 bits
    - sticky status: busy/done/error
        |
        v
  spx_thashx4_core
    - unchanged wide-port thashx4 RTL
```

`spx_cop_wrapper` issues a one-cycle `start` pulse to `spx_thashx4_core` when a
valid start command is accepted and `inblocks` is either `1` or `2`. Outputs are
latched into wrapper output registers after the core asserts `done`.

## Command Interface

Top-level ports:

| Signal | Direction | Width | Description |
| --- | --- | ---: | --- |
| `cmd_valid` | input | 1 | Command request valid. |
| `cmd_ready` | output | 1 | Wrapper can accept the command. Reads are accepted while busy; writes/start wait until idle. |
| `cmd_op` | input | 8 | Command opcode. |
| `cmd_addr` | input | 8 | Word-addressed register selector. |
| `cmd_wdata` | input | 32 | Write data. |
| `rsp_rdata` | output | 32 | Read response data. Zero for non-read responses. |
| `rsp_valid` | output | 1 | One-cycle response valid for each accepted command. |
| `busy` | output | 1 | Mirrors status bit 0. |
| `done` | output | 1 | Mirrors sticky status bit 1. |
| `error` | output | 1 | Mirrors sticky status bit 2. |

Opcodes:

| Opcode | Name | Description |
| ---: | --- | --- |
| `0x01` | `CMD_WRITE` | Write `cmd_wdata` into the selected 32-bit register word. |
| `0x02` | `CMD_READ` | Read the selected 32-bit register word into `rsp_rdata`. |
| `0x03` | `CMD_START` | Start one thashx4 operation using currently stored registers. |

Protocol:

- A command is accepted on `clk` when `cmd_valid && cmd_ready`.
- `rsp_valid` is asserted for one cycle after each accepted command.
- Read data is returned with `rsp_valid`.
- `CMD_START` clears sticky `done`; a valid start also clears sticky `error`.
- Invalid opcodes, invalid register addresses, or invalid `inblocks` on start
  set sticky `error`.
- Writing `1` to status bit 1 clears sticky `done`; writing `1` to status bit 2
  clears sticky `error`.

## Register Map

All multiword fields use little-endian word indexing:

- word 0 maps to bits `[31:0]`
- word 1 maps to bits `[63:32]`
- byte 0 is in bits `[7:0]` of word 0

| Address range | Access | Field | Word count |
| ---: | --- | --- | ---: |
| `0x00` - `0x03` | R/W | `pub_seed[127:0]` | 4 |
| `0x10` - `0x17` | R/W | `addr0[255:0]` | 8 |
| `0x18` - `0x1f` | R/W | `addr1[255:0]` | 8 |
| `0x20` - `0x27` | R/W | `addr2[255:0]` | 8 |
| `0x28` - `0x2f` | R/W | `addr3[255:0]` | 8 |
| `0x30` - `0x37` | R/W | `in0[255:0]` | 8 |
| `0x38` - `0x3f` | R/W | `in1[255:0]` | 8 |
| `0x40` - `0x47` | R/W | `in2[255:0]` | 8 |
| `0x48` - `0x4f` | R/W | `in3[255:0]` | 8 |
| `0x50` | R/W | `config.inblocks[1:0]` | 1 |
| `0x51` | R/W1C | `status` | 1 |
| `0x60` - `0x63` | R | `out0[127:0]` | 4 |
| `0x64` - `0x67` | R | `out1[127:0]` | 4 |
| `0x68` - `0x6b` | R | `out2[127:0]` | 4 |
| `0x6c` - `0x6f` | R | `out3[127:0]` | 4 |

Status register `0x51`:

| Bit(s) | Name | Description |
| ---: | --- | --- |
| `0` | `busy` | Operation in progress. |
| `1` | `done` | Sticky completion flag. Cleared by start or W1C. |
| `2` | `error` | Sticky error flag. Cleared by valid start or W1C. |
| `9:8` | `inblocks` | Current config value. |
| `19:16` | `error_code` | `0=none`, `1=bad_op`, `2=bad_addr`, `3=bad_inblocks`. |

## Data Movement Flow

For each operation:

1. Write `pub_seed` words `0..3` at `0x00..0x03`.
2. Write each lane address:
   - lane 0: `0x10..0x17`
   - lane 1: `0x18..0x1f`
   - lane 2: `0x20..0x27`
   - lane 3: `0x28..0x2f`
3. Write each lane input:
   - `inblocks=1`: write words `0..3`; words `4..7` are ignored by the core.
   - `inblocks=2`: write words `0..7`.
4. Write config register `0x50` with `1` or `2`.
5. Send `CMD_START`.
6. Poll status register `0x51` until `done=1` or `error=1`.
7. Read output lane words from `0x60..0x6f`.

The wrapper does not reinterpret the thash byte order. It only stores and
replays the same bit layout used by `spx_thashx4_core`.

## Simulation

New testbench:

```text
sim/tb/tb_spx_cop_wrapper.sv
```

Make target:

```sh
make -C sim sim-cop-wrapper
```

Full regression target:

```sh
make -C sim test
```

Result on 2026-05-13:

```text
LATENCY keccakx4_core min=25 max=25 avg=25.00 cycles
PASS keccakx4_core (128 cases)
LATENCY thashx4_core inblocks=1 min=27 max=27 avg=27.00 cycles
LATENCY thashx4_core inblocks=2 min=27 max=27 avg=27.00 cycles
PASS thashx4_core inblocks=1,2 (200 cases)
STATUS_POLLS spx_cop_wrapper inblocks=1 min=10 max=10 avg=10.00
STATUS_POLLS spx_cop_wrapper inblocks=2 min=10 max=10 avg=10.00
PASS spx_cop_wrapper inblocks=1,2 (200 cases)
```

The wrapper test writes all registers through the command interface, starts the
operation, polls status, reads all four output lanes, and compares against the C
golden vectors generated by `sim/gen_thashx4_vectors.c`. It covers 100 random
vectors for `inblocks=1` and 100 random vectors for `inblocks=2`.

Lint result on 2026-05-13:

```text
make -C sim lint
PASS rtl lint
```

## OOC PPA Flow

The Vivado OOC flow now includes the wrapper RTL and a dedicated target:

```sh
make -C synth/fpga synth-cop-wrapper \
  PART=xc7a35tcpg236-1 CLOCK_PERIOD_NS=10.0
```

Windows helper:

```bat
cd synth\fpga
run_vivado.bat spx_cop_wrapper xc7a35tcpg236-1 10.0
```

Expected report paths:

```text
synth/fpga/build/spx_cop_wrapper/reports/ppa_summary.txt
synth/fpga/build/spx_cop_wrapper/reports/utilization.rpt
synth/fpga/build/spx_cop_wrapper/reports/timing_summary.rpt
```

PPA status:

| Top | Part | LUT | FF | Fmax | Status |
| --- | --- | ---: | ---: | ---: | --- |
| `spx_thashx4_core` | `xc7a35tcpg236-1` | 11797 | 9105 | 116.58 MHz | Phase 2.5 baseline |
| `spx_cop_wrapper` | `xc7a35tcpg236-1` | TBD | TBD | TBD | Flow target added; Vivado not available in this Linux environment |

The current Linux environment used for this update does not have `vivado` in
`PATH`, so wrapper LUT/FF/Fmax must be filled in after running the target on the
Vivado host.

## CV-X-IF Mapping Notes

The wrapper is deliberately one layer above `spx_thashx4_core` and one layer
below any future CV-X-IF binding.

A future CV-X-IF adapter can map custom instructions onto this protocol:

- instruction immediate or function field -> `cmd_op`
- register operand or immediate field -> `cmd_addr`
- source register data -> `cmd_wdata`
- response register data <- `rsp_rdata`
- instruction accept/commit backpressure <- `cmd_ready`
- long-running operation state <- `busy/done/error`

The later CV-X-IF layer should only translate instruction semantics into this
command protocol. It should not need to know the internal `spx_thashx4_core`
wide-port layout beyond the register map documented here.
