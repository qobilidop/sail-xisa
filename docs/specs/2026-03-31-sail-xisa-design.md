# Sail XISA Design Spec

## Overview

A formal specification of [XISA](https://xsightlabs.com/switches/xisa) (Xsight Labs' X-Switch Instruction Set Architecture) written in [Sail](https://github.com/rems-project/sail). XISA defines packet processing for the X-Switch family of programmable network switches.

The spec serves as:
- A reference model that can be simulated to validate packet processing programs
- A formal spec for correctness reasoning via Sail's type system
- A single source of truth for generating emulators, test suites, and documentation

Inspired by the [Sail RISC-V model](https://github.com/riscv/sail-riscv).

## XISA Architecture Summary

XISA has two sub-ISAs executed by the Programmable Forwarding Engine (PFE):

### Parser ISA
- **Purpose:** Parse incoming packet headers, set header metadata for MAP processing
- **Registers:** 4 general-purpose 128-bit registers (R0-R3), big-endian
- **Cursor:** Maintains a position in the packet header buffer (up to 256 bytes)
- **Instructions:** ~25 instructions for packet extraction, cursor movement, branching, and metadata setting
- **Termination:** HALT instruction hands off to MAP; HALTDROP discards the packet

### MAP ISA
- **Purpose:** Match-action processing — classification, forwarding, header editing, lookups
- **Registers:** Richer register file with multiple addressing modes
- **Instructions:** ~54 instructions including arithmetic, memory access, lookups, counters, and packet send/drop
- **Features:** Condition code flags (Z, N, C, V), dependency checker, async lookup flag

## Scope: First Iteration

This iteration covers:
1. Dev container with Sail toolchain
2. Project structure and build system
3. Parser ISA vertical slice: NOP, HALT, MOV/MOVI, EXT
4. Readable tests for each instruction
5. Documentation (dev commands, coverage tracker, tech debt)

## Project Structure

```
sail-xisa/
├── .devcontainer/
│   ├── devcontainer.json
│   └── Dockerfile              # Ubuntu + opam + Sail + C deps
├── dev.sh                      # Run any command inside the dev container
├── model/
│   ├── prelude.sail            # Shared types, bitvector helpers
│   ├── parser/
│   │   ├── types.sail          # Parser register types, enums
│   │   ├── state.sail          # Parser state (registers, cursor, flags)
│   │   ├── decode.sail         # Instruction decoding (bits -> union)
│   │   └── insts.sail          # Instruction execution semantics
│   └── main.sail               # Top-level glue, fetch-decode-execute
├── test/
│   ├── parser/
│   │   ├── test_nop.sail
│   │   ├── test_halt.sail
│   │   ├── test_mov.sail
│   │   └── test_ext.sail
│   └── CMakeLists.txt          # Test registration for CTest
├── CMakeLists.txt              # Root build config
├── docs/
│   ├── dev-commands.md         # Development commands reference
│   ├── coverage.md             # Spec coverage tracker
│   └── todo.md                 # Tech debt and known issues
├── README.md
└── LICENSE
```

Key decisions:
- `model/parser/` keeps Parser ISA files together; `model/map/` added later for MAP ISA
- One file per concern within parser (types, state, decode, execution)
- Tests are Sail files compiled to executables via C backend
- Uppercase filenames only for root-level conventional files (README.md, LICENSE, Makefile, CMakeLists.txt, Dockerfile)
- All other filenames are lowercase with hyphens

## Dev Container & Build System

### Dockerfile

Ubuntu 24.04 base with explicit opam setup:

```dockerfile
FROM ubuntu:24.04

# System dependencies
RUN apt-get update && apt-get install -y \
    opam gcc make cmake pkg-config \
    libgmp-dev zlib1g-dev

# Opam + OCaml environment
RUN opam init --disable-sandboxing --yes
RUN opam switch create 5.1.0
RUN eval $(opam env) && opam install sail --yes

# Keep opam env active for all commands
ENV PATH="/root/.opam/5.1.0/bin:$PATH"
```

### dev.sh

Thin wrapper around `devcontainer exec`:

```bash
#!/bin/bash
# Usage: ./dev.sh <command>
# Examples:
#   ./dev.sh sail --version
#   ./dev.sh cmake --build build
#   ./dev.sh ctest --test-dir build
devcontainer exec --workspace-folder . "$@"
```

### CMake Build

Root CMakeLists.txt:
- `find_program(SAIL sail REQUIRED)` — locate Sail compiler
- **`check` target** — `sail --just-check` on all model files (type-checking only, fast)
- **`build_sim` target** — `sail -c` generates C, gcc compiles, links libgmp
- **`test` target** — CTest runs each test Sail file through the simulator

Build workflow:
```bash
./dev.sh cmake -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo
./dev.sh cmake --build build
./dev.sh ctest --test-dir build
```

## Sail Code Architecture

### prelude.sail

Shared foundation:
- Bitvector type aliases: `type bits128 = bits(128)`, `type bits8 = bits(8)`, etc.
- Common helper functions (e.g., big-endian byte extraction from a 128-bit register)

### parser/types.sail

Parser-specific types:
- Register index enum: `R0, R1, R2, R3, RN` (RN = null register)
- Instruction union with scattered clauses — one `union clause pinstr` per instruction
- Initial instructions: PNOP, PHALT, PMOV, PMOVI, PEXT

### parser/state.sail

Mutable Parser state:
- `register PR : vector(4, bits(128))` — 4 general-purpose 128-bit registers
- `register pcursor : bits(8)` — cursor position (0-255)
- `register packet_hdr : vector(256, bits(8))` — packet header buffer
- `register parser_halted : bool` — halted flag

### parser/decode.sail

Instruction decoding:
- `mapping clause encdec` for each instruction — maps bit patterns to union variants
- Exact encodings based on the XISA white paper where available
- Incomplete encodings tracked in `docs/todo.md`

### parser/insts.sail

Execution semantics:
- `function clause execute` for each instruction
- Returns execution result (success/failure)
- Each clause is self-contained and readable

### main.sail

Top-level loop:
- `fetch()` — read instruction bits from instruction memory at PC
- `decode()` — call encdec mapping to get pinstr union
- `execute()` — dispatch to matching clause
- `step()` — fetch, decode, execute, advance PC; loop until halted

### Conventions

- All Parser types/names prefixed with `P` or `parser_` to avoid future MAP collisions
- Instruction union uses scattered definitions so each file can add clauses
- Big-endian throughout (matching the XISA spec)

## Testing Strategy

### Test structure

Each test is a Sail file that:
1. Sets up initial state (register values, packet data)
2. Executes one instruction
3. Asserts expected results using Sail's `assert`

Example:
```sail
// Test: MOV R1, R0 copies register value
function test_mov() -> unit = {
    PR[0] = 0xDEADBEEF_00000000_00000000_00000000;
    PR[1] = zeros();

    execute(PMOV(R1, R0));

    assert(PR[1] == 0xDEADBEEF_00000000_00000000_00000000,
           "MOV should copy source to destination");
    assert(PR[0] == 0xDEADBEEF_00000000_00000000_00000000,
           "MOV should not modify source");
}
```

### Test coverage

| File | Tests |
|------|-------|
| test_nop.sail | NOP doesn't change any state |
| test_halt.sail | HALT sets halted flag, HALTDROP variant |
| test_mov.sail | MOV reg-to-reg, MOVI immediate load, null register RN behavior |
| test_ext.sail | EXT extracts correct bytes from packet buffer at cursor position |

### How tests run

- Each test file includes model files plus test functions
- `main()` calls all test functions
- Sail compiles to C via `sail -c`, gcc builds executable, runs and exits 0 on success
- CTest registers each test executable

### What tests prove

- Type-checking catches structural errors (wrong bitvector widths, missing match cases)
- Test execution catches semantic errors (wrong behavior for given inputs)
- Together: readable evidence that the spec matches the white paper
