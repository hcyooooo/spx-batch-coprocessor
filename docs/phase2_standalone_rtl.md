# Phase 2 Standalone RTL: SPHINCS+ thashx4

This phase adds a standalone SystemVerilog implementation of the
SPHINCS+-SHAKE-128f-simple `thashx4` datapath. It is intentionally limited to
the primitive core and RTL simulation harness: no CV32E40PX, no CV-X-IF, no
custom instruction, no SoC integration, and no AXI/AHB/APB wrapper.

## Target

- `PARAMS=sphincs-shake-128f`
- `THASH=simple`
- `SPX_N=16`
- `SHAKE256_RATE=136`
- Four independent Keccak/SHAKE lanes
- Supported `thashx4` input shapes: `inblocks=1` and `inblocks=2`
- One 16-byte output per lane

`inblocks > 2` is not supported by this RTL phase.

## Current File Structure

```text
rtl/
├── common/
│   └── spx_thashx4_pkg.sv
└── core/
    ├── spx_keccak_round.sv
    ├── spx_keccakx4_core.sv
    └── spx_thashx4_core.sv

sim/
├── Makefile
├── gen_thashx4_vectors.c
├── tb/
│   ├── tb_keccakx4_core.sv
│   └── tb_thashx4_core.sv
└── vectors/
    ├── keccakx4_vectors.hex
    ├── thashx4_inblocks1.hex
    ├── thashx4_inblocks2.hex
    └── thashx4_expected.hex
```

## RTL Modules

`spx_thashx4_pkg.sv`

Defines the fixed Phase 2 constants, Keccak round constants, rho offsets, and
the `rotl64()` helper.

`spx_keccak_round.sv`

Combinational Keccak-f1600 single-round block. It implements theta, rho, pi,
chi, and iota over 25 64-bit state words. State word `i` is mapped to
`state[64*i +: 64]`.

`spx_keccakx4_core.sv`

Iterative four-lane Keccak-f1600 permutation core. It instantiates four
single-round blocks and applies one round per cycle for 24 rounds. `done`
pulses when the permuted states are available.

`spx_thashx4_core.sv`

Builds four SHAKE256 absorb states:

```text
pub_seed || addr || input || 0x1f || zero padding || rate_end_0x80
```

Then it calls `spx_keccakx4_core` and returns the low 16 bytes of each
permuted state. Interface byte order follows the C golden model: byte 0 is in
the low 8 bits of each packed input vector.

## Interfaces

The standalone cores use a simple `start`/`done` pulse protocol. Inputs must be
stable when `start` is asserted. A new operation should not be started until
`done` has pulsed.

For `spx_thashx4_core`, `in0` to `in3` are 256-bit to cover `inblocks=2`.
When `inblocks=1`, only bits `[127:0]` are absorbed. Unsupported `inblocks`
values complete immediately with zero outputs.

## Vector Generation

The vector generator links against the existing C golden
`sw/spx_model/keccakx4.c`.

Manual command from the repository root:

```sh
mkdir -p sim/build sim/vectors
gcc -std=c99 -Wall -Wextra -O2 -Isw/spx_model \
  -o sim/build/gen_thashx4_vectors \
  sim/gen_thashx4_vectors.c sw/spx_model/keccakx4.c
./sim/build/gen_thashx4_vectors sim/vectors
```

Generated coverage:

- `keccakx4_vectors.hex`: 128 permutation cases
- `thashx4_inblocks1.hex`: 100 random input cases
- `thashx4_inblocks2.hex`: 100 random input cases
- `thashx4_expected.hex`: 200 expected `thashx4` output cases

## Simulation

The simulation flow uses Verilator.

Run everything:

```sh
make -C sim test
```

Run only Keccak:

```sh
make -C sim sim-keccakx4
```

Run only thashx4:

```sh
make -C sim sim-thashx4
```

## Test Results

Run locally on 2026-05-13:

```text
PASS keccakx4_core (128 cases)
PASS thashx4_core inblocks=1,2 (200 cases)
```

The `thashx4` coverage includes 100 `inblocks=1` cases and 100 `inblocks=2`
cases. All outputs match the C golden model.

## Current Limits

- Fixed to SPHINCS+-SHAKE-128f-simple.
- Supports only `inblocks=1` and `inblocks=2`.
- Single-rate-block SHAKE256 absorb only.
- No area or frequency optimization.
- No CPU, SoC, bus, CV-X-IF, or custom-instruction integration.
- No algorithm semantic changes relative to the C golden model.

## Future CV-X-IF Integration Direction

The next integration phase can wrap `spx_thashx4_core` behind a CV-X-IF
coprocessor shell. That wrapper should define operand movement for `pub_seed`,
four addresses, four inputs, `inblocks`, and four 16-byte outputs, then map the
existing `start`/`done` protocol onto the CV-X-IF issue/result handshake. The
standalone RTL here should remain the golden core underneath that wrapper.
