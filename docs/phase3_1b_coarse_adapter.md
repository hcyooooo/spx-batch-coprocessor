# Phase 3.1B Coarse-Grain Adapter Simulation

This phase keeps the experiment standalone. It does not connect CV32E40PX,
AXI, AHB, APB, or a full SoC fabric, and it does not change
`spx_thashx4_core`, `spx_cop_wrapper`, Keccak, or thash algorithm semantics.

The goal is to compare coarser custom-instruction and adapter protocols before
binding the design to real CV-X-IF signals.

## Scope

New RTL:

```text
rtl/cvxif/spx_cvxif_adapter_coarse.sv
```

New testbench:

```text
sim/tb/tb_spx_cvxif_adapter_coarse.sv
```

Updated build targets:

```sh
make -C sim sim-cvxif-adapter-coarse
make -C sim test
make -C sim lint
```

## Protocols Compared

### 1. Baseline scalar mapping

This is the Phase 3.1A protocol:

- one custom instruction per 32-bit wrapper register access;
- explicit `SPX_WR addr, rs1` and `SPX_RD rd, addr`;
- one-inflight request/response model;
- each instruction costs two cycles in the standalone model.

It is useful for functional bring-up because it maps directly onto the existing
wrapper register map, but performance is dominated by moving pub seed, address,
input, status, and output words through scalar instructions.

### 2. Auto-increment register window

The new coarse adapter supports:

| Instruction | Use |
| --- | --- |
| `SPX_SET_PTR base_addr` | Set an adapter-side pointer to a wrapper register address. |
| `SPX_WR_NEXT rs1` | Write `rs1` to the current pointer, then increment the pointer. |
| `SPX_RD_NEXT rd` | Read the current pointer into `rd`, then increment the pointer. |
| `SPX_START_THASHX4` | Write `inblocks` from `rs1[1:0]`, then start the wrapper. |
| `SPX_STATUS rd` | Read wrapper status. |

The pointer is a raw wrapper register window. This preserves the Phase 3.0
register layout exactly. For `inblocks=1`, input lanes still have the wrapper's
8-word stride, so the testbench uses extra `SPX_SET_PTR` operations to skip the
unused high input words in each lane.

Performance model:

- `SPX_SET_PTR` and `SPX_WR_NEXT` are acknowledged in one cycle.
- `SPX_RD_NEXT` and `SPX_STATUS` take two cycles because 32-bit read data must
  return.
- `SPX_START_THASHX4` takes two cycles because it performs an internal config
  write followed by wrapper start.

This reduces cycle overhead but does not fundamentally reduce the number of
32-bit input and output words the CPU must issue.

### 3. Descriptor / bulk-load style protocol

The descriptor path is modeled in the testbench rather than as a real memory
interface. The assumed CPU protocol is one descriptor-start instruction carrying
the descriptor address. The adapter then:

1. reads pub seed, four addresses, and four input lanes from a memory-side
   buffer;
2. starts the unchanged thashx4 core;
3. writes the four 128-bit outputs back to a memory-side buffer;
4. reports done through status polling.

No real AXI/AHB/APB interface is implemented. The model evaluates three
memory-side bandwidth assumptions:

- `bulk_1w`: 1 x 32-bit word per cycle;
- `bulk_2w`: 2 x 32-bit words per cycle;
- `bulk_4w`: 4 x 32-bit words per cycle.

Modeled movement:

| `inblocks` | Load words | Store words |
| ---: | ---: | ---: |
| 1 | 52 | 16 |
| 2 | 68 | 16 |

Status polling remains a two-cycle custom-instruction read in the model.

## Simulation Result

Run on 2026-05-13:

```sh
make -C sim sim-cvxif-adapter-coarse
make -C sim test
make -C sim lint
```

Correctness:

```text
PASS spx_cvxif_adapter_coarse inblocks=1,2 (200 cases)
PASS rtl lint
```

Auto-increment adapter stats:

```text
COARSE_AUTO_INC_STATS inblocks=1:
  set_ptr_instr = 6
  wr_next_instr = 52
  rd_next_instr = 16
  start_instr = 1
  status_instr = 15
  total_instr = 90
  total_cycles = 122
  core_cycles = 27
  overhead_cycles = 95
COARSE_AUTO_INC_STATS inblocks=2:
  set_ptr_instr = 3
  wr_next_instr = 68
  rd_next_instr = 16
  start_instr = 1
  status_instr = 15
  total_instr = 103
  total_cycles = 135
  core_cycles = 27
  overhead_cycles = 108
```

Bulk model stats:

```text
BULK_MODEL_STATS width=1words_per_cycle inblocks=1:
  descriptor_instr = 1
  status_instr = 48
  load_cycles = 52
  store_cycles = 16
  total_instr = 49
  total_cycles = 97
  core_cycles = 27
  overhead_cycles = 70
BULK_MODEL_STATS width=1words_per_cycle inblocks=2:
  descriptor_instr = 1
  status_instr = 56
  load_cycles = 68
  store_cycles = 16
  total_instr = 57
  total_cycles = 113
  core_cycles = 27
  overhead_cycles = 86
BULK_MODEL_STATS width=2words_per_cycle inblocks=1:
  total_instr = 32
  total_cycles = 63
  core_cycles = 27
  overhead_cycles = 36
BULK_MODEL_STATS width=2words_per_cycle inblocks=2:
  total_instr = 36
  total_cycles = 71
  core_cycles = 27
  overhead_cycles = 44
BULK_MODEL_STATS width=4words_per_cycle inblocks=1:
  total_instr = 23
  total_cycles = 45
  core_cycles = 27
  overhead_cycles = 18
BULK_MODEL_STATS width=4words_per_cycle inblocks=2:
  total_instr = 25
  total_cycles = 49
  core_cycles = 27
  overhead_cycles = 22
```

## Comparison

```text
Protocol              inblocks  instr  total_cycles  core_cycles  overhead  active_share
-----------------------------------------------------------------------------------------
scalar                1         84     168           27           141       16.1%
scalar                2         100    200           27           173       13.5%
auto_inc              1         90     122           27           95        22.1%
auto_inc              2         103    135           27           108       20.0%
bulk_1w               1         49     97            27           70        27.8%
bulk_1w               2         57     113           27           86        23.9%
bulk_2w               1         32     63            27           36        42.9%
bulk_2w               2         36     71            27           44        38.0%
bulk_4w               1         23     45            27           18        60.0%
bulk_4w               2         25     49            27           22        55.1%
```

## Interpretation

The scalar mapping is functionally correct but remains heavily data-movement
limited.

The auto-increment window improves elapsed cycles by allowing one-cycle pointer
setup and write-next operations. It does not reduce the amount of CPU-visible
32-bit data movement, so instruction count is slightly higher than scalar after
adding pointer setup instructions. It is a good low-risk adapter refinement, but
not enough as the final performance path.

The descriptor/bulk model is the first protocol that materially changes the
data-movement balance. Even at 1 word/cycle it beats auto-increment in elapsed
cycles. At 4 words/cycle, the thashx4 core is active for more than half of the
observed operation window.

## Phase 3.2 Recommendation

Do not continue with pure scalar custom instructions as the performance path.
Keep the scalar mapping only as a simple functional/debug path.

Add an adapter-side FIFO if the next experiment remains instruction-driven. A
FIFO can let the CPU issue write-next streams without waiting on each adapter
response, but it will not solve output movement or the total number of words.

Prioritize a memory-side descriptor/bulk-load model before real SoC integration.
The Phase 3.1B results show that even a narrow 1-word/cycle memory-side path
beats scalar and auto-increment, while 2-word and 4-word paths are much closer
to keeping the core busy.

It is worth modeling a hardware WOTS chain loop after the descriptor path is
defined. WOTS chains create many regular `inblocks=1` thash operations; moving
the loop into hardware could reduce CPU command traffic beyond one descriptor
per thashx4 operation. That should be evaluated as a second-level coarse
operation, ideally fed by the same descriptor/bulk movement mechanism rather
than by scalar register writes.
