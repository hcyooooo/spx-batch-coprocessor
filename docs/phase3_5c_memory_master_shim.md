# Phase 3.5C Memory Master Shim Mock

Phase 3.5C adds a standalone memory-master shim mock between
`spx_descriptor_adapter_4w` and a mock bus/memory model. It does not connect
CV32E40PX, AXI, AHB, APB, or a full SoC fabric. It also does not change the
descriptor ABI, Keccak, `spx_thashx4_core`, or the `spx_descriptor_adapter_4w`
bulk-data path.

The tested standalone path is:

```text
SPX_SET_DESC / SPX_START / SPX_STATUS / SPX_CLEAR / SPX_WAIT
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
mock bus request/response model
        |
        v
128-bit mock memory
```

## Shim Architecture

The new RTL module is:

```text
rtl/mem/spx_mem_master_shim_mock.sv
```

The shim preserves the descriptor adapter's simple memory-side contract while
making the bus side explicitly request/response based:

- descriptor side presents one `mem_*` beat;
- shim issues one mock bus request and waits for request acceptance;
- shim waits for the matching mock bus response;
- shim completes the descriptor-side beat only when the response is available.

This keeps bulk data off CV-X-IF and keeps the descriptor-control adapter thin.
The mock bus is deliberately not a real protocol adapter.

## Descriptor Side Interface

The descriptor side is unchanged:

```systemverilog
mem_valid
mem_ready
mem_we
mem_addr
mem_wdata[127:0]
mem_rdata[127:0]
mem_error
```

The descriptor beat completes when `mem_valid && mem_ready`. For reads,
`mem_rdata` and `mem_error` are sampled on that completed beat. For writes,
`mem_error` is the write response status sampled on that completed beat.

## Mock Bus Side Interface

The mock bus side separates request acceptance from response return:

```systemverilog
bus_req_valid
bus_req_ready
bus_req_we
bus_req_addr
bus_req_wdata[127:0]

bus_rsp_valid
bus_rsp_rdata[127:0]
bus_rsp_error
```

`bus_req_valid && bus_req_ready` accepts a request. `bus_rsp_valid` returns the
corresponding response. The mock bus has no response-ready input because the
one-outstanding shim is always waiting for the response once a request has been
accepted.

## One-Outstanding Policy

The current shim supports exactly one outstanding transaction.

This matches the current descriptor adapter behavior: `spx_descriptor_adapter_4w`
waits for each memory beat to complete before moving to the next beat. It does
not issue another load or store while a previous beat is still pending.

Future performance work can consider:

- read prefetch for descriptor, public seed, address, or input bursts;
- multiple outstanding reads;
- separate write acceptance and write completion queues;
- response reordering rules if a real bus protocol requires them.

Those are intentionally out of scope for Phase 3.5C.

## Request/Response Timing

Request-side backpressure is modeled with `bus_req_ready`. If the mock bus is
not ready, the shim keeps `bus_req_valid` asserted and leaves descriptor-side
`mem_ready` low.

Once a request is accepted, the response can be returned in the same cycle or a
later cycle:

| Timing case | Bus behavior | Descriptor-side result |
| --- | --- | --- |
| Zero latency | request accepted and response valid in the same cycle | `mem_ready` asserts in the same cycle |
| Delayed read | request accepted, read response after configured latency | `mem_ready` stays low until read response |
| Delayed write response | write request accepted, write response after configured latency | `mem_ready` stays low until write response |
| Request backpressure | `bus_req_ready=0` before accept | no bus request is accepted and `mem_ready=0` |

The standalone testbench covers read response latencies of 1, 2, and 4 cycles,
write response latencies of 1, 2, and 4 cycles, fixed request-side
backpressure, and deterministic random request readiness.

## Error Mapping

`bus_rsp_error` maps directly to descriptor-side `mem_error` on the completed
beat:

```text
bus_rsp_error -> mem_error
```

The descriptor adapter then maps the completed beat according to the active
state:

| Bus response | Descriptor adapter result |
| --- | --- |
| read response with `bus_rsp_error=1` | `ERR_MEM_READ` |
| write response with `bus_rsp_error=1` | `ERR_MEM_WRITE` |

The Phase 3.5C regression injects read and write bus errors through the shim and
checks CV-X-IF status, descriptor status writeback, and final error code.

## Performance Statistics

Run on 2026-05-13:

```sh
make -C sim sim-mem-master-shim
make -C sim lint
```

Correctness:

```text
PASS spx_mem_master_shim_mock standalone memory-master tests
PASS rtl lint
```

The test uses one golden vector per `inblocks` value for each timing mode.
`bus_request_count` and `bus_response_count` must match for every successful
case.

| Mode | `inblocks` | total cycles | descriptor adapter cycles | memory load cycles | core cycles | memory store cycles | shim stall cycles | bus requests | bus responses | active share |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| zero latency | 1 | 51 | 50 | 15 | 27 | 5 | 0 | 20 | 20 | 52.9% |
| zero latency | 2 | 55 | 54 | 19 | 27 | 5 | 0 | 24 | 24 | 49.1% |
| read latency 1 | 1 | 66 | 65 | 30 | 27 | 5 | 15 | 20 | 20 | 40.9% |
| read latency 1 | 2 | 74 | 73 | 38 | 27 | 5 | 19 | 24 | 24 | 36.5% |
| read latency 2 | 1 | 81 | 80 | 45 | 27 | 5 | 30 | 20 | 20 | 33.3% |
| read latency 2 | 2 | 93 | 92 | 57 | 27 | 5 | 38 | 24 | 24 | 29.0% |
| read latency 4 | 1 | 111 | 110 | 75 | 27 | 5 | 60 | 20 | 20 | 24.3% |
| read latency 4 | 2 | 131 | 130 | 95 | 27 | 5 | 76 | 24 | 24 | 20.6% |
| write latency 1 | 1 | 56 | 55 | 15 | 27 | 10 | 5 | 20 | 20 | 48.2% |
| write latency 1 | 2 | 60 | 59 | 19 | 27 | 10 | 5 | 24 | 24 | 45.0% |
| write latency 2 | 1 | 61 | 60 | 15 | 27 | 15 | 10 | 20 | 20 | 44.3% |
| write latency 2 | 2 | 65 | 64 | 19 | 27 | 15 | 10 | 24 | 24 | 41.5% |
| write latency 4 | 1 | 71 | 70 | 15 | 27 | 25 | 20 | 20 | 20 | 38.0% |
| write latency 4 | 2 | 75 | 74 | 19 | 27 | 25 | 20 | 24 | 24 | 36.0% |
| request backpressure 2 | 1 | 91 | 90 | 45 | 27 | 15 | 40 | 20 | 20 | 29.7% |
| request backpressure 2 | 2 | 103 | 102 | 57 | 27 | 15 | 48 | 24 | 24 | 26.2% |
| random request ready 50% | 1 | 74 | 73 | 31 | 27 | 12 | 23 | 20 | 20 | 36.5% |
| random request ready 50% | 2 | 74 | 73 | 37 | 27 | 6 | 19 | 24 | 24 | 36.5% |
| split response delay | 1 | 101 | 100 | 45 | 27 | 25 | 50 | 20 | 20 | 26.7% |
| split response delay | 2 | 113 | 112 | 57 | 27 | 25 | 58 | 24 | 24 | 23.9% |

The successful request counts match the expected 4-word beat profile:

| `inblocks` | Read beats | Write beats | Total bus requests |
| ---: | ---: | ---: | ---: |
| 1 | 15 | 5 | 20 |
| 2 | 19 | 5 | 24 |

## Difference From Phase 3.5B

Phase 3.5B modeled wait states directly on the descriptor memory side by
holding `mem_ready=0`. That proved the descriptor adapter tolerated wait states,
backpressure, and `mem_error` on completed beats.

Phase 3.5C moves the latency model behind an explicit shim:

- Phase 3.5B: memory model directly controls `mem_ready`.
- Phase 3.5C: shim drives `mem_ready` only after mock bus request acceptance and
  mock bus response return.

This adds a clearer boundary for later bus integration without committing to
AXI, AHB, APB, or a specific SoC fabric.

## Phase 3.6 Recommendation

Yes, the project is ready to enter Phase 3.6 real CV-X-IF bring-up, with one
important boundary condition: keep Phase 3.6 focused on the real CV-X-IF
control path and preserve the descriptor-memory bulk path proven here.

Recommended next step:

- bind `spx_cvxif_desc_adapter` to the real CV32E40PX CV-X-IF instruction path;
- keep `spx_descriptor_adapter_4w` as the performance path;
- keep the shim/mock bus boundary as the memory integration contract;
- defer real AXI/AHB/APB attachment until the CV-X-IF control bring-up is stable.

