# Phase 3.7 CV32E40X Core-Level Smoke Harness

Phase 3.7 instantiates the real `cv32e40x_core` in a standalone testbench and
runs a minimal bare-metal program that controls the SPHINCS descriptor
accelerator through real CV32E40X CV-X-IF custom instructions.

The scope remains intentionally small:

- no complete SoC
- no AXI, AHB, or APB
- no X-HEEP
- no CV-X-IF bulk data movement
- no Keccak, thash, descriptor adapter, CV-X-IF real adapter, or accelerator
  semantic changes

## GCC Toolchain

The build target auto-detects the first available compiler from:

1. `riscv32-corev-elf-gcc`
2. `riscv32-unknown-elf-gcc`
3. `riscv64-unknown-elf-gcc`

The tool found on this machine was:

```text
riscv32-corev-elf-gcc ('corev-openhw-gcc-ubuntu2204-20240530') 14.1.0
```

The version is also recorded by the build in:

```text
sim/build/spx_cvxif_smoke.gcc.txt
```

## Build Command

Bare-metal program build:

```sh
make -C sim build-cv32e40x-smoke
```

The GCC command uses:

```text
-march=rv32imc
-mabi=ilp32
-nostdlib
-nostartfiles
-ffreestanding
-fno-builtin
-msmall-data-limit=0
-O2
```

Outputs:

```text
sim/build/spx_cvxif_smoke.elf
sim/build/spx_cvxif_smoke.dump
sim/build/spx_cvxif_smoke.hex
```

The hex file is generated with `objcopy -O verilog` and loaded by the core
smoke testbench with `$readmemh`.

## Feasibility Findings

`third_party/cv32e40x/rtl/cv32e40x_core.sv` exposes a compact standalone core
boundary suitable for a minimal harness:

- clock/reset/control: `clk_i`, `rst_ni`, `scan_cg_en_i`, `fetch_enable_i`
- boot/config: `boot_addr_i`, `mtvec_addr_i`, `mhartid_i`,
  `mimpid_patch_i`, debug module addresses
- instruction interface: `instr_req_o`, `instr_gnt_i`, `instr_rvalid_i`,
  `instr_addr_o`, `instr_rdata_i`, `instr_err_i`
- data interface: `data_req_o`, `data_gnt_i`, `data_rvalid_i`,
  `data_addr_o`, `data_be_o`, `data_we_o`, `data_wdata_o`,
  `data_rdata_i`, `data_err_i`, `data_exokay_i`
- CV-X-IF modports: compressed, issue, commit, memory, memory-result, result
- IRQ/debug/fence/sleep sideband ports that can be tied off for smoke

The instruction and data ports follow the documented OBI-style request,
grant, and response-valid protocol. The local smoke memory grants every request
immediately and returns an in-order response one cycle later.

The XIF interface instance must match the core parameters:

```systemverilog
cv32e40x_if_xif #(
  .X_NUM_RS(2),
  .X_ID_WIDTH(4),
  .X_MEM_WIDTH(32),
  .X_RFR_WIDTH(32),
  .X_RFW_WIDTH(32),
  .X_MISA(32'h0000_0000),
  .X_ECS_XS(2'b00)
) xif ();
```

No reusable simple core-level testbench was found under
`third_party/cv32e40x`. The local tree has RTL, docs, SVA, and behavioral
helpers; full verification is expected to live in `core-v-verif`, which was not
pulled for this phase.

## Harness Architecture

Implemented in:

```text
sim/tb/tb_cv32e40x_spx_core_smoke.sv
```

The instantiated path is:

```text
cv32e40x_core
  instruction memory model
  data memory model
  cv32e40x_if_xif
    -> spx_cvxif_real_adapter
    -> spx_cvxif_desc_adapter
    -> spx_descriptor_adapter, MEM_WORDS_PER_CYCLE = 4
    -> spx_mem_master_shim_mock
    -> shared smoke memory
```

Core parameters used by the smoke harness:

```text
RV32 = RV32I
A_EXT = A_NONE
B_EXT = B_NONE
M_EXT = M
DEBUG = 0
CLIC = 0
X_EXT = 1
X_NUM_RS = 2
X_ID_WIDTH = 4
X_MEM_WIDTH = 32
X_RFR_WIDTH = 32
X_RFW_WIDTH = 32
X_MISA = 0
X_ECS_XS = 0
NUM_MHPMCOUNTERS = 1
```

## Memory Model

The smoke harness uses one shared byte-addressed backing array:

```text
MEM_BYTES = 128 KiB
```

Both CV32E40X instruction and data ports access this array. The descriptor
adapter also reaches the same array through `spx_mem_master_shim_mock`.

Instruction memory:

- loads `sim/build/spx_cvxif_smoke.hex`
- grants every instruction request immediately
- returns a 32-bit little-endian word one cycle later
- reports no instruction errors

Data memory:

- grants every load/store request immediately
- returns a response one cycle later
- supports byte enables for stores
- supports word, halfword, and byte-visible data through the shared byte array
- reports no data errors and no exclusive success

Descriptor memory side path:

- `MEM_WORDS_PER_CYCLE = 4`
- 128-bit reads/writes are packed from the same byte backing array
- bus response is zero-latency after the shim request

This is a standalone smoke model, so cache and coherency are not modeled.

## Custom Instruction Encoding

The bare-metal smoke program uses the Phase 3.6 `custom-0` encoding:

```text
opcode = 0x0b
funct7 = 0x5a
funct3 = 0: SPX_SET_DESC
funct3 = 1: SPX_START
funct3 = 2: SPX_STATUS
funct3 = 3: SPX_CLEAR
rs2 = x0
```

Inline asm form:

```c
__asm__ volatile(".insn r 0x0b, 0, 0x5a, %0, %1, x0"
                 : "=r"(rd) : "r"(desc_addr) : "memory");

__asm__ volatile(".insn r 0x0b, 1, 0x5a, %0, x0, x0"
                 : "=r"(rd) : : "memory");

__asm__ volatile(".insn r 0x0b, 2, 0x5a, %0, x0, x0"
                 : "=r"(rd) : : "memory");

__asm__ volatile(".insn r 0x0b, 3, 0x5a, %0, x0, x0"
                 : "=r"(rd) : : "memory");
```

The RTL monitor fatals if `xif.mem_valid` is ever asserted.

## Smoke Program

Implemented in:

```text
sw/tests/spx_cvxif_smoke.c
sw/tests/spx_cvxif_smoke.ld
```

The program:

1. initializes descriptor, pub_seed, addr, input, and output buffers
2. runs one golden case with `inblocks=1`
3. runs one golden case with `inblocks=2`
4. for each case executes `SPX_CLEAR`, `SPX_SET_DESC`, `SPX_START`
5. polls `SPX_STATUS` until done
6. compares all four output lanes against golden words
7. writes `0x00000001` to `0x0000fffc` on PASS
8. writes `0x0000dead` to `0x0000fffc` on FAIL

Golden data is copied from the existing generated C golden vectors:

```text
sim/vectors/thashx4_inblocks1.hex
sim/vectors/thashx4_inblocks2.hex
sim/vectors/thashx4_expected.hex
```

Only one `inblocks=1` case and one `inblocks=2` case are used in this first
core smoke.

## Simulation

Run:

```sh
make -C sim sim-cv32e40x-core-smoke
```

Observed result:

```text
PASS cv32e40x_spx_core_smoke cycles=1641 instr_fetch=1340 data_rd=184 data_wr=197 xif_issue=20 xif_accept=20 xif_result=20 desc_ctrl=20 bus_rd=34 bus_wr=10 perf_load=19 perf_core=27 perf_store=5 perf_total=54
```

This confirms:

- the real CV32E40X core fetched and executed the bare-metal program
- custom instructions were offloaded through real CV32E40X issue, commit, and
  result channels
- `spx_cvxif_real_adapter` accepted the instructions and returned results
- descriptor bulk data stayed on the memory-side path
- the descriptor accelerator completed both golden cases
- the program observed correct output buffers and wrote PASS magic

## Current Limits

- This is a smoke harness, not a full CV32E40X verification environment.
- Instruction and data memory are simple always-grant, one-cycle response
  models.
- Descriptor-side bus is a zero-latency mock path after the shim.
- Interrupts, debug entry, PMP/PMA stress, bus errors, wait states, atomics,
  and fence effects are not covered.
- No cache or coherency behavior is modeled.
- The smoke uses two golden cases, not the full randomized vector set.
- Verilator is invoked with `-Wno-fatal`; third-party CV32E40X RTL emits
  expected standalone warnings such as missing timescales and unoptimized flat
  logic.

## Phase 3.8 Readiness

Phase 3.7 meets the intended milestone: a real CV32E40X core can execute a
bare-metal program and control the SPHINCS descriptor accelerator through real
CV-X-IF custom instructions, while bulk data remains on the descriptor memory
path.

It is reasonable to enter Phase 3.8 next. Good candidates are either hardening
this smoke into CI with a small matrix of memory wait states, or moving toward
the next integration boundary while still keeping the accelerator data path
unchanged.
