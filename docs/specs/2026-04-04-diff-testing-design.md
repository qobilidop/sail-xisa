# Differential Testing Design

## Goal

Verify that the Rust playground simulator produces the same results as the Sail-generated C emulator by running the same programs on both and comparing final state.

## Motivation

Proptest checks internal consistency (encode agrees with decode, assembler agrees with encoder), but it cannot detect bugs where both sides are wrong in the same way. Differential testing against the Sail reference model catches cases where the Rust implementation diverges from the specification.

## Architecture

### Components

1. **Sail C emulator harness** (`test/diff/harness.c`) — a C program that links against the Sail-generated C code. Reads a binary program file and an optional packet data file from command-line args. Calls `zparser_init()`, loads instructions into `pimem` via `zwrite_pimem_raw()`, optionally loads packet bytes into `zpacket_hdr`, calls `zparser_run()`, and dumps parser-observable state as JSON to stdout.

2. **CMake build target** — compiles the Sail model to C (reusing the existing `sail -c` pipeline), then compiles `harness.c` linked against it. Produces a `sail-c-emu-harness` executable.

3. **Rust integration test** (`playground/tests/diff_test.rs`) — for each test program:
   - Assembles source using the `xisa` crate directly (no subprocess)
   - Runs the Rust simulator using the `xisa` crate directly
   - Writes the binary program (and packet data, if any) to temp files
   - Shells out to the pre-built `sail-c-emu-harness` executable
   - Parses both JSON outputs
   - Compares the parser-observable fields
   - Uses proptest to fuzz packet data for programs that read packets

### Why a C harness (not Sail)

Sail has `print`/`print_endline` but no file I/O. A pure Sail harness cannot read binary files. The C harness links against the Sail-generated C code and accesses the generated register globals directly:

- `zPR` — register vector, `lbits` (GMP) per element
- `zppc` — program counter, `uint64_t`
- `zpcursor` — cursor, `uint64_t`
- `zpflag_zz` — zero flag, `bool` (note the double-z encoding from Sail name mangling)
- `zpflag_n` — negative flag, `bool`
- `zparser_halted` — halted flag, `bool`
- `zparser_drop` — drop flag, `bool`
- `zstruct0` — struct-0, `lbits`
- `zhdr_present` — header present vector, `bool` array
- `zhdr_offset` — header offset vector, `uint64_t` array

## Data flow

```
assembly source (.xisa)
        |
        v
  [xisa assembler] ──> binary file (.bin)
        |                     |
        v                     v
  [Rust simulator]    [Sail C emulator harness]
        |                     |
        v                     v
    Rust JSON             Sail JSON
        |                     |
        └──── compare ────────┘
```

For packet fuzzing, the Rust test also writes a packet data file and passes it to both simulators.

## Compared state (JSON format)

Both simulators output the same JSON structure:

```json
{
  "pc": 5,
  "regs": [
    "0x00000000000000000000000000000000",
    "0x00000000000000000000000000000000",
    "0x00000000000000000000000000000000",
    "0x00000000000000000000000000000000"
  ],
  "flag_z": true,
  "flag_n": false,
  "cursor": 14,
  "halted": true,
  "dropped": false,
  "struct0": "0x00000000000000000000000000000000",
  "hdr_present": [true, false, false, "...32 entries"],
  "hdr_offset": [14, 0, 0, "...32 entries"]
}
```

Registers and struct0 are 32-digit hex strings with `0x` prefix. Integer fields use decimal. Booleans are native JSON.

## Test programs

Start with these hand-written programs:

1. **`simple-branch.xisa`** — existing example, pure arithmetic/branch logic, no packet access. Deterministic output.
2. **`extract-ipv4.xisa`** — existing example, reads packet header fields. Fuzz the packet data.
3. **Additional targeted programs** — to be added as needed to cover instruction groups (header/cursor ops, compare+branch patterns, etc.).

For programs that don't touch packet data, a zeroed 256-byte buffer is used. For programs that do, proptest generates random 256-byte buffers.

## Prerequisites

The `sail-c-emu-harness` executable must be pre-built before running `cargo test`. The Rust test locates it at a known path (e.g., `build/test/sail-c-emu-harness`). If it doesn't exist, the diff tests are skipped (not failed) — this allows `cargo test` to work on machines without the Sail toolchain.

## What we're NOT doing

- Instruction-level diff testing (single instruction with arbitrary initial state) — future work
- MAP ISA diff testing — parser ISA only
- Automated test program generation — hand-written programs + packet fuzzing
- CI integration for diff tests — the Sail build is already in CI, but wiring `cargo test` to depend on the CMake build is a separate concern
