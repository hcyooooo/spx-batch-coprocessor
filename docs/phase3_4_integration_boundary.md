# Phase 3.4 Real Integration Boundary Design

This phase defines the next integration boundary for a future CV32E40PX +
CV-X-IF + descriptor-adapter system. It is an architecture preparation step,
not a full SoC integration.

It intentionally does not:

- connect AXI, AHB, APB, or a full system fabric;
- modify Keccak or thash algorithms;
- modify `spx_thashx4_core` semantics;
- replace the existing scalar/debug adapter path.

Phase 3.4 selects the 4-word descriptor adapter configuration as the preferred
performance path:

```text
spx_descriptor_adapter, MEM_WORDS_PER_CYCLE = 4
memory-side beat width = 128 bits
```

Use the 2-word descriptor adapter as the fallback if the target platform cannot
provide a practical 128-bit memory-side path.

## Why `descriptor_4w`

Phase 3.2 showed that descriptor/bulk movement is the first protocol that
materially reduces CPU-visible data movement. Phase 3.3 then synthesized the
descriptor adapter in three memory-side widths and found that all three meet
the 10.0 ns OOC FPGA target.

| Config | Width | LUT | FF | Fmax | `inblocks=1` throughput | `inblocks=2` throughput |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `descriptor_1w` | 32 bits | 13565 | 11853 | 107.65 MHz | 4.02 Mthash/s | 3.50 Mthash/s |
| `descriptor_2w` | 64 bits | 14090 | 11858 | 107.20 MHz | 6.21 Mthash/s | 5.57 Mthash/s |
| `descriptor_4w` | 128 bits | 14801 | 11870 | 103.34 MHz | 8.27 Mthash/s | 7.65 Mthash/s |

`descriptor_4w` is preferred because:

- it has the best absolute throughput for both supported input shapes;
- it has the best throughput per LUT despite the slightly lower Fmax;
- the area cost versus `descriptor_2w` is modest: +711 LUT and +12 FF;
- it keeps `spx_thashx4_core` active for about half of the standalone
  descriptor operation: 54.0% for `inblocks=1`, 50.0% for `inblocks=2`;
- it directly matches a 128-bit memory-side beat, which is a natural width for
  moving four 32-bit words per cycle.

The 4w path is therefore the right boundary to design around first. The 2w path
remains the realistic fallback for a system with only a 64-bit SRAM, TCDM, L2,
or bus segment.

## Why Not Continue Scalar Custom Instructions

The scalar custom-instruction path is functionally useful but not a good
performance path. It moves pub seed words, address words, input words, status,
and output words through 32-bit instruction operands and results. That makes
instruction traffic, not Keccak/thash compute, the dominant cost.

The Phase 3.1B comparison showed the direction clearly:

| Protocol | `inblocks` | Total cycles | Core cycles | Active share |
| --- | ---: | ---: | ---: | ---: |
| scalar | 1 | 168 | 27 | 16.1% |
| scalar | 2 | 200 | 27 | 13.5% |
| bulk_4w model | 1 | 45 | 27 | 60.0% |
| bulk_4w model | 2 | 49 | 27 | 55.1% |

The scalar interface should remain available as a debug and bring-up path. A
small `SPX_WR` / `SPX_RD` style register path is useful for visibility, simple
smoke tests, and fallback diagnostics. It should not be treated as the
performance path for SPHINCS+ thash batching.

## CV-X-IF Responsibility

CV-X-IF should only carry coarse control for the accelerator:

- descriptor base address;
- start;
- status readback;
- done/error clear;
- optionally a wait operation if the eventual CV-X-IF binding supports it
  cleanly.

CV-X-IF should not carry bulk thash input and output data. The bulk data path
belongs on the memory side, where the descriptor adapter can fetch and store
wide beats without requiring one custom instruction per 32-bit word.

The minimal custom-instruction set for Phase 3.5 is:

| Instruction | Operand/result | Purpose |
| --- | --- | --- |
| `SPX_SET_DESC rs1` | `rs1 = descriptor base address` | Set the descriptor base address used by the adapter. |
| `SPX_START` | none | Start the descriptor adapter using the current descriptor address. |
| `SPX_STATUS rd` | `rd = status bits` | Read `busy`, `done`, and `error`. |
| `SPX_CLEAR` | none | Clear sticky `done` and `error` status. |
| `SPX_WAIT rd` | optional `rd = final status` | Optional blocking or polling wait, depending on real CV-X-IF support. |

Recommended status bit convention:

| Bit | Name | Meaning |
| ---: | --- | --- |
| 0 | `busy` | Adapter is executing or waiting on memory. |
| 1 | `done` | Last operation completed. |
| 2 | `error` | Last operation failed before producing valid output. |
| 7:4 | `error_code` | Adapter-defined error code. |

Do not add many scalar `SPX_WR` / `SPX_RD` instructions to the performance
path. They can remain as a debug register path, but software should use
descriptors and memory buffers for normal execution.

## Bulk Data Movement

Bulk data moves through memory:

```text
software prepares descriptor and buffers in memory
CV-X-IF points hardware at descriptor
descriptor adapter reads descriptor, seed, addresses, and input lanes
descriptor adapter runs unchanged spx_thashx4_core
descriptor adapter writes output and status back to memory
software reads output buffer
```

For the Phase 3.4 preferred ABI:

- descriptor and buffers must be aligned to 16 bytes;
- the 4w path transfers 128 bits per accepted memory beat;
- `inblocks=1` compact input layout is 4 lanes x 4 words;
- `inblocks=2` compact input layout is 4 lanes x 8 words;
- output layout is 4 lanes x 4 words.

The 16-byte alignment rule is kept at the software ABI boundary even if a
future 2w fallback can technically run with 8-byte beats. This keeps buffers
compatible with the preferred 4w path and avoids ABI churn.

## Software Calling Flow

The C-side contract is descriptor driven. The exact final header can be added
in Phase 3.5, but the intended call shape is:

```c
typedef struct {
    volatile uint32_t flags_status;
    uint32_t config;
    uintptr_t pub_seed_ptr;
    uintptr_t addr_base_ptr;
    uintptr_t input_base_ptr;
    uintptr_t output_base_ptr;
    uint32_t descriptor_len_words;
    uint32_t reserved;
} spx_desc;

#define SPX_DESC_ALIGN 16
#define SPX_LANES 4
#define SPX_VARIANT_SHAKE_128F_SIMPLE 1

alignas(SPX_DESC_ALIGN) spx_desc desc;
alignas(SPX_DESC_ALIGN) uint32_t pub_seed[4];
alignas(SPX_DESC_ALIGN) uint32_t addr[SPX_LANES][8];
alignas(SPX_DESC_ALIGN) uint32_t input[SPX_LANES][8];
alignas(SPX_DESC_ALIGN) uint32_t output[SPX_LANES][4];

/* Prepare pub_seed, addr, and input buffers. */
prepare_pub_seed(pub_seed);
prepare_addr_words(addr);
prepare_input_words(input, inblocks);

desc.flags_status = 0;
desc.config =
    (inblocks & 0x3u) |
    (SPX_LANES << 4) |
    (SPX_VARIANT_SHAKE_128F_SIMPLE << 8);
desc.pub_seed_ptr = (uintptr_t)&pub_seed[0];
desc.addr_base_ptr = (uintptr_t)&addr[0][0];
desc.input_base_ptr = (uintptr_t)&input[0][0];
desc.output_base_ptr = (uintptr_t)&output[0][0];
desc.descriptor_len_words = 8;
desc.reserved = 0;

spx_accel_start(&desc);
spx_accel_wait_done();

/* Read output[0..3][0..3]. */
consume_output_words(output);
```

The software-visible layouts are:

```text
pub_seed:
  word 0..3

addr_base:
  lane 0 addr word 0..7
  lane 1 addr word 0..7
  lane 2 addr word 0..7
  lane 3 addr word 0..7

input_base, inblocks=1:
  lane 0 input word 0..3
  lane 1 input word 0..3
  lane 2 input word 0..3
  lane 3 input word 0..3

input_base, inblocks=2:
  lane 0 input word 0..7
  lane 1 input word 0..7
  lane 2 input word 0..7
  lane 3 input word 0..7

output_base:
  lane 0 output word 0..3
  lane 1 output word 0..3
  lane 2 output word 0..3
  lane 3 output word 0..3
```

`spx_accel_start()` maps to the coarse CV-X-IF control sequence:

```c
static inline void spx_accel_start(spx_desc *desc)
{
    spx_set_desc((uintptr_t)desc);  /* SPX_SET_DESC rs1 */
    spx_start();                    /* SPX_START */
}

static inline void spx_accel_wait_done(void)
{
    uint32_t status;

    do {
        status = spx_status();      /* SPX_STATUS rd */
    } while ((status & SPX_STATUS_DONE) == 0u &&
             (status & SPX_STATUS_ERROR) == 0u);
}
```

If the target software stack uses cached memory, the real implementation also
needs cache maintenance around the descriptor and buffers:

- flush descriptor, pub seed, address, and input buffers before `SPX_START`;
- invalidate output buffer and descriptor status after completion;
- or place all accelerator-visible buffers in uncached memory.

## Integration Boundary

The intended module boundary is:

```text
CV32E40PX
  |
  | CV-X-IF custom instruction
  v
spx_cvxif_desc_adapter
  |
  | start/status/desc_addr
  v
spx_descriptor_adapter_4w
  |
  | simplified 128-bit memory request
  v
memory master shim / system bus
  |
  v
SRAM / L2 / TCDM
```

The split is deliberate:

- `spx_cvxif_desc_adapter` translates CV-X-IF custom instructions into a small
  start/status/descriptor-address control protocol.
- `spx_descriptor_adapter_4w` owns descriptor parsing, compact buffer reads,
  `spx_thashx4_core` start/done control, output writes, and descriptor status
  writeback.
- `memory master shim` owns the real SoC memory protocol and all bus-specific
  behavior.

The descriptor adapter should keep its simplified memory request interface as
long as possible:

```systemverilog
mem_valid
mem_ready
mem_we
mem_addr
mem_wdata[127:0]
mem_rdata[127:0]
```

The memory master shim must handle the system-dependent work:

- convert the descriptor adapter's 128-bit requests to the real SoC bus;
- handle wait states and backpressure;
- handle alignment requirements and report alignment errors where needed;
- handle write response and write error reporting;
- bridge narrower target buses if the system does not expose 128-bit transfers;
- implement cache-coherency policy with software, either through
  flush/invalidate requirements or by placing buffers in uncached memory.

The shim is the right place to decide whether the SoC uses SRAM, L2, TCDM, an
AXI-like fabric, an AHB-like fabric, or another local memory protocol. Phase 3.4
does not commit to one of those buses.

## Real-System Issues To Resolve

A real CV32E40PX system needs decisions that the standalone adapter did not
make:

- Memory master ownership: whether the accelerator has an independent master
  port, a TCDM port, or a tightly coupled SRAM port.
- Bus protocol: how `valid/ready/we/addr/wdata/rdata` maps to the target
  request, grant, response, byte-enable, and error channels.
- Backpressure: whether the adapter stalls per beat, buffers requests, or uses
  a small FIFO between the descriptor adapter and the bus shim.
- Alignment: whether unaligned descriptors and buffers are rejected in hardware,
  fixed up by software, or split by the shim.
- Write response: how output writes and descriptor-status writes report bus
  errors back into `done/error/error_code`.
- Cache coherency: whether accelerator-visible memory is uncached, explicitly
  maintained by software, or coherent through the system fabric.
- Address width and protection: how CV-X-IF source registers provide descriptor
  addresses on the target system and whether address translation or PMP-like
  checks are in scope.
- Interrupts: whether completion is only polled through `SPX_STATUS` or can
  later raise an interrupt. Polling is enough for Phase 3.5.

## Risk Analysis

1. CV-X-IF itself is usually not a good bulk-data movement mechanism. It should
   carry coarse accelerator control, not every thash input and output word.
2. `descriptor_4w` needs a memory-side master path to realize its measured
   throughput advantage.
3. If the target platform has no practical 128-bit memory path, Phase 3.5
   should use `descriptor_2w` as the 64-bit fallback.
4. Real bus latency, arbitration, and wait states can make the Phase 3.2
   standalone latency worse.
5. Cache coherence can increase software complexity through flush/invalidate
   requirements or uncached allocation constraints.
6. FPGA OOC PPA is not final SoC PPA. Full-system timing, routing, clocking,
   bus logic, and memory macros can change area, Fmax, and throughput.

## Phase 3.5 Implementation Plan

Phase 3.5 should stay staged and standalone before any full CV32E40PX SoC work:

1. Phase 3.5A: implement `spx_cvxif_desc_adapter` skeleton.
   - Handle only descriptor address, start, status, clear, and optional wait.
   - Do not move bulk data through CV-X-IF.
   - Keep scalar/debug access separate from the performance path.
2. Phase 3.5B: implement a memory master shim mock.
   - Convert the descriptor adapter's simplified 128-bit memory request into a
     mock bus transaction model.
   - Add wait-state, backpressure, write-response, alignment, and error tests.
3. Phase 3.5C: connect `spx_descriptor_adapter_4w`, mock memory, and
   `spx_cvxif_desc_adapter` in a full standalone system test.
   - Verify descriptor start/status through the CV-X-IF-facing shell.
   - Verify payload movement through the memory side.
   - Reuse the existing golden vectors and do not change `spx_thashx4_core`.
4. Phase 3.5D: only after the standalone boundary is stable, consider real
   CV32E40PX/CV-X-IF integration.

## Do Not Do Next

Keep the next phase focused on the real integration boundary. Do not:

- immediately convert the design to AXI;
- immediately connect a full SoC;
- rewrite `spx_thashx4_core`;
- optimize or restructure the Keccak round logic;
- delete the existing scalar/debug adapter.

Do not make Phase 3.5 an immediate AXI/AHB/APB or full-SoC port. The next
milestone is to prove the integration boundary with realistic wait states and
memory-side ownership while preserving the existing thashx4 core semantics.
