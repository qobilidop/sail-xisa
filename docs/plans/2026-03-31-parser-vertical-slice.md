# Parser ISA Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working Sail XISA project with dev container, build system, and a vertical slice of the Parser ISA (NOP, HALT, MOV/MOVI, EXT) with tests.

**Architecture:** Dev container (Ubuntu + opam + Sail) with CMake build system. Sail model organized by sub-ISA (parser/ directory), with shared prelude. Tests are Sail files compiled to C executables via Sail's C backend.

**Tech Stack:** Sail language, CMake, GCC, opam/OCaml (for Sail toolchain), Docker/devcontainer

---

## File Map

| File | Responsibility |
|------|---------------|
| `.devcontainer/Dockerfile` | Ubuntu 24.04 + opam + OCaml + Sail + C deps |
| `.devcontainer/devcontainer.json` | Dev container configuration |
| `dev.sh` | Convenience script to run commands inside the dev container |
| `CMakeLists.txt` | Root build configuration: type-check, C build, test targets |
| `model/prelude.sail` | Shared types (bitvector aliases, execution result) and helpers |
| `model/parser/types.sail` | Parser register index enum, instruction union declaration |
| `model/parser/state.sail` | Parser mutable state (registers, cursor, packet buffer, flags) |
| `model/parser/decode.sail` | Instruction decoding (bit patterns to union variants) |
| `model/parser/insts.sail` | Instruction execution semantics |
| `model/main.sail` | Top-level includes, step function, main entry point |
| `test/parser/test_nop.sail` | NOP instruction tests |
| `test/parser/test_halt.sail` | HALT/HALTDROP instruction tests |
| `test/parser/test_mov.sail` | MOV/MOVI instruction tests |
| `test/parser/test_ext.sail` | EXT instruction tests |
| `test/CMakeLists.txt` | Test target registration for CTest |
| `docs/dev-commands.md` | Development commands reference |
| `docs/coverage.md` | Parser/MAP instruction spec coverage tracker |
| `docs/todo.md` | Tech debt and known issues |

---

### Task 1: Dev Container Setup

**Files:**
- Create: `.devcontainer/Dockerfile`
- Create: `.devcontainer/devcontainer.json`
- Create: `dev.sh`

- [ ] **Step 1: Create Dockerfile**

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies for Sail and its C backend
RUN apt-get update && apt-get install -y \
    opam gcc make cmake pkg-config \
    libgmp-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Initialize opam (OCaml package manager)
# --disable-sandboxing is needed inside Docker (no bwrap available)
RUN opam init --disable-sandboxing --yes --bare

# Create an OCaml 5.1.0 switch (compiler environment)
RUN opam switch create 5.1.0

# Install Sail into this switch
RUN eval $(opam env --switch=5.1.0) && opam install sail --yes

# Make opam binaries available without eval $(opam env)
ENV PATH="/root/.opam/5.1.0/bin:${PATH}"
ENV SAIL_DIR="/root/.opam/5.1.0/share/sail"

WORKDIR /workspace
```

- [ ] **Step 2: Create devcontainer.json**

```json
{
    "name": "sail-xisa",
    "build": {
        "dockerfile": "Dockerfile",
        "context": ".."
    },
    "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind",
    "workspaceFolder": "/workspace"
}
```

- [ ] **Step 3: Create dev.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Run a command inside the sail-xisa dev container.
#
# Usage:
#   ./dev.sh <command> [args...]
#
# Examples:
#   ./dev.sh sail --version
#   ./dev.sh cmake -B build
#   ./dev.sh cmake --build build
#   ./dev.sh ctest --test-dir build
#   ./dev.sh bash              # interactive shell

devcontainer exec --workspace-folder . "$@"
```

- [ ] **Step 4: Make dev.sh executable**

Run: `chmod +x dev.sh`

- [ ] **Step 5: Build and verify the dev container**

Run: `devcontainer build --workspace-folder .`
Expected: Container builds successfully, Sail is installed.

Run: `./dev.sh sail --version`
Expected: Prints Sail version (0.18+).

- [ ] **Step 6: Commit**

```bash
git add .devcontainer/Dockerfile .devcontainer/devcontainer.json dev.sh
git commit -m "Add dev container with Ubuntu, opam, and Sail toolchain"
```

---

### Task 2: CMake Build System

**Files:**
- Create: `CMakeLists.txt`
- Create: `test/CMakeLists.txt`

- [ ] **Step 1: Create root CMakeLists.txt**

```cmake
cmake_minimum_required(VERSION 3.20)
project(sail-xisa LANGUAGES C)

# Find the Sail compiler
find_program(SAIL sail REQUIRED)
message(STATUS "Found Sail: ${SAIL}")

# Find the Sail library directory (for C runtime headers and sources)
# SAIL_DIR should be set in the environment (set in our Dockerfile)
if(DEFINED ENV{SAIL_DIR})
    set(SAIL_DIR $ENV{SAIL_DIR})
else()
    message(FATAL_ERROR "SAIL_DIR environment variable not set. Cannot find Sail runtime.")
endif()
message(STATUS "Sail directory: ${SAIL_DIR}")

# Collect all model Sail files
file(GLOB_RECURSE MODEL_SAIL_FILES "${CMAKE_SOURCE_DIR}/model/*.sail")

# Target: type-check the model (fast, no C compilation)
add_custom_target(check
    COMMAND ${SAIL} --just-check ${MODEL_SAIL_FILES}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Type-checking Sail model..."
    SOURCES ${MODEL_SAIL_FILES}
)

# Enable testing
enable_testing()
add_subdirectory(test)
```

- [ ] **Step 2: Create test/CMakeLists.txt (placeholder)**

```cmake
# Test targets will be added as we implement instructions.
# Each test is a Sail file compiled to a C executable.
#
# Usage:
#   cmake --build build
#   ctest --test-dir build

# Helper function: compile a Sail test to a C executable and register it with CTest.
#
# Arguments:
#   TEST_NAME  - name for the test (used as executable name and CTest label)
#   TEST_SAIL  - path to the test .sail file
#
# The test Sail file is compiled together with all model files.
# Sail generates C, which is compiled with gcc and linked against libgmp and the Sail runtime.
function(add_sail_test TEST_NAME TEST_SAIL)
    set(TEST_C "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}.c")
    set(TEST_EXE "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}")

    # Step 1: Sail -> C
    add_custom_command(
        OUTPUT ${TEST_C}
        COMMAND ${SAIL} -c ${MODEL_SAIL_FILES} ${CMAKE_SOURCE_DIR}/${TEST_SAIL} -o ${TEST_C}
        DEPENDS ${MODEL_SAIL_FILES} ${CMAKE_SOURCE_DIR}/${TEST_SAIL}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        COMMENT "Compiling Sail test ${TEST_NAME} to C..."
    )

    # Step 2: C -> executable
    add_executable(${TEST_NAME} ${TEST_C} ${SAIL_DIR}/lib/sail.c)
    target_include_directories(${TEST_NAME} PRIVATE ${SAIL_DIR}/lib)
    target_link_libraries(${TEST_NAME} PRIVATE gmp z)
    target_compile_options(${TEST_NAME} PRIVATE -O2)

    # Step 3: Register with CTest
    add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME})
endfunction()
```

- [ ] **Step 3: Verify CMake configures successfully**

Run: `./dev.sh cmake -B build`
Expected: CMake configures, finds Sail, prints Sail version and directory.

- [ ] **Step 4: Verify type-check target works (will fail until we have Sail files, that's expected)**

Run: `./dev.sh cmake --build build --target check`
Expected: Fails with "no Sail files" or similar — confirms the target exists and Sail runs.

- [ ] **Step 5: Commit**

```bash
git add CMakeLists.txt test/CMakeLists.txt
git commit -m "Add CMake build system with type-check and test infrastructure"
```

---

### Task 3: Sail Prelude and Parser State

**Files:**
- Create: `model/prelude.sail`
- Create: `model/parser/types.sail`
- Create: `model/parser/state.sail`

- [ ] **Step 1: Create model/prelude.sail**

```sail
default Order dec

// Bitvector type aliases
type bits8   = bits(8)
type bits16  = bits(16)
type bits128 = bits(128)

// Execution result for instructions
enum ExecutionResult = {
    RETIRE_SUCCESS,
    RETIRE_HALT,
    RETIRE_DROP
}
```

- [ ] **Step 2: Create model/parser/types.sail**

```sail
// Parser register indices.
// The Parser has 4 general-purpose 128-bit registers (R0-R3).
// RN is a null register used when the destination is not needed.
enum pregidx = {PR0, PR1, PR2, PR3, PRN}

// Convert parser register index to numeric index (0-3).
// PRN maps to 0 but writes to PRN are discarded (see state.sail).
val pregidx_to_nat : pregidx -> range(0, 3)
function pregidx_to_nat(r) = match r {
    PR0 => 0,
    PR1 => 1,
    PR2 => 2,
    PR3 => 3,
    PRN => 0
}

// Is this the null register?
val is_null_reg : pregidx -> bool
function is_null_reg(r) = match r {
    PRN => true,
    _   => false
}

// Parser instruction union (scattered — each file adds clauses).
scattered union pinstr

// NOP: No operation.
union clause pinstr = PNOP : unit

// HALT: Terminate parsing. Bool indicates drop (true = HALTDROP).
union clause pinstr = PHALT : bool

// MOV: Copy SizeBits bits from SourceReg at SrcOffset to DestReg at DestOffset.
// Fields: (dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits)
union clause pinstr = PMOV : (pregidx, bits8, pregidx, bits8, bits8)

// MOVI: Load immediate value into DestReg.
// Fields: (dest_reg, dest_offset_bytes, immediate_value, size_bits)
union clause pinstr = PMOVI : (pregidx, bits8, bits16, bits8)

// EXT: Extract data from packet buffer at cursor-relative offset into DestReg.
// Fields: (dest_reg, dest_offset_bits, source_offset_bits, size_bits, clear_dest)
// source_offset_bits is relative to the current cursor position.
// clear_dest corresponds to the .CD optional modifier.
union clause pinstr = PEXT : (pregidx, bits8, bits16, bits8, bool)

end pinstr
```

- [ ] **Step 3: Create model/parser/state.sail**

```sail
// Parser general-purpose registers: 4 x 128-bit, big-endian.
register PR : vector(4, bits128)

// Parser cursor position in the packet header buffer.
// Range 0-255 (up to 256 bytes of packet header).
register pcursor : bits8

// Packet header buffer: 256 bytes.
register packet_hdr : vector(256, bits8)

// Parser halted flag.
register parser_halted : bool

// Parser drop flag (set by HALTDROP).
register parser_drop : bool

// Condition flags (set by arithmetic/compare instructions).
register pflag_z : bool  // Zero flag
register pflag_n : bool  // Negative flag

// Read a parser register. PRN always reads as zero.
val read_preg : pregidx -> bits128
function read_preg(r) =
    if is_null_reg(r) then zeros()
    else PR[pregidx_to_nat(r)]

// Write a parser register. Writes to PRN are discarded.
val write_preg : (pregidx, bits128) -> unit
function write_preg(r, v) =
    if not_bool(is_null_reg(r)) then PR[pregidx_to_nat(r)] = v

// Initialize parser state (called before running a parser program).
val parser_init : unit -> unit
function parser_init() = {
    PR[0] = zeros();
    PR[1] = zeros();
    PR[2] = zeros();
    PR[3] = zeros();
    pcursor = zeros();
    parser_halted = false;
    parser_drop = false;
    pflag_z = false;
    pflag_n = false;
}

// Read a range of bits from a 128-bit register value.
// offset and size are in bits. Big-endian: bit 127 is MSB, bit 0 is LSB.
// Returns the extracted bits zero-extended to 128 bits (in the low bits).
val extract_bits : (bits128, nat, nat) -> bits128
function extract_bits(reg_val, offset, size) = {
    let mask : bits128 = sail_mask(128, sail_ones(size));
    (reg_val >> offset) & mask
}

// Write a range of bits into a 128-bit register value.
// Returns the updated 128-bit value.
val insert_bits : (bits128, nat, nat, bits128) -> bits128
function insert_bits(reg_val, offset, size, data) = {
    let mask : bits128 = sail_mask(128, sail_ones(size)) << offset;
    let cleared = reg_val & not_vec(mask);
    let shifted_data = (data & sail_mask(128, sail_ones(size))) << offset;
    cleared | shifted_data
}
```

- [ ] **Step 4: Verify type-check passes**

Run: `./dev.sh cmake --build build --target check`
Expected: Sail type-checks these three files successfully (exit 0).

Note: You may need to adjust the CMake `file(GLOB_RECURSE ...)` or pass files in the right order. Sail requires `prelude.sail` before files that use its types. If the glob doesn't produce the right order, update CMakeLists.txt to list files explicitly:

```cmake
set(MODEL_SAIL_FILES
    ${CMAKE_SOURCE_DIR}/model/prelude.sail
    ${CMAKE_SOURCE_DIR}/model/parser/types.sail
    ${CMAKE_SOURCE_DIR}/model/parser/state.sail
)
```

- [ ] **Step 5: Commit**

```bash
git add model/prelude.sail model/parser/types.sail model/parser/state.sail
git commit -m "Add Sail prelude, parser types, and parser state definitions"
```

---

### Task 4: NOP Instruction (Test-First)

**Files:**
- Create: `model/parser/insts.sail`
- Create: `model/parser/decode.sail`
- Create: `model/main.sail`
- Create: `test/parser/test_nop.sail`

- [ ] **Step 1: Create minimal insts.sail with execute function declaration**

```sail
// Parser instruction execution.
// Each instruction adds a clause to this scattered function.
scattered function execute : pinstr -> ExecutionResult

// NOP: No operation. Does nothing, returns success.
function clause execute(PNOP()) = RETIRE_SUCCESS

end execute
```

- [ ] **Step 2: Create minimal decode.sail (placeholder for future binary decoding)**

```sail
// Parser instruction decoding.
// For now, tests construct instruction values directly.
// Binary decoding will be added when instruction encodings are fully specified.
```

- [ ] **Step 3: Create model/main.sail**

```sail
$include <prelude.sail>
$include "prelude.sail"
$include "parser/types.sail"
$include "parser/state.sail"
$include "parser/decode.sail"
$include "parser/insts.sail"
```

- [ ] **Step 4: Write NOP test**

Create `test/parser/test_nop.sail`:

```sail
// Tests for the NOP instruction.
// NOP should not modify any parser state.

val test_nop_does_not_change_registers : unit -> unit
function test_nop_does_not_change_registers() = {
    parser_init();
    PR[0] = 0xAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD;
    PR[1] = 0x11111111_22222222_33333333_44444444;
    PR[2] = 0x55555555_66666666_77777777_88888888;
    PR[3] = 0x99999999_AABBCCDD_EEFF0011_22334455;

    let result = execute(PNOP());

    assert(result == RETIRE_SUCCESS, "NOP should return RETIRE_SUCCESS");
    assert(PR[0] == 0xAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD, "NOP should not modify R0");
    assert(PR[1] == 0x11111111_22222222_33333333_44444444, "NOP should not modify R1");
    assert(PR[2] == 0x55555555_66666666_77777777_88888888, "NOP should not modify R2");
    assert(PR[3] == 0x99999999_AABBCCDD_EEFF0011_22334455, "NOP should not modify R3");
}

val test_nop_does_not_change_cursor : unit -> unit
function test_nop_does_not_change_cursor() = {
    parser_init();
    pcursor = 0x42;

    let _ = execute(PNOP());

    assert(pcursor == 0x42, "NOP should not modify cursor");
}

val test_nop_does_not_change_flags : unit -> unit
function test_nop_does_not_change_flags() = {
    parser_init();
    pflag_z = true;
    pflag_n = true;

    let _ = execute(PNOP());

    assert(pflag_z == true, "NOP should not modify Z flag");
    assert(pflag_n == true, "NOP should not modify N flag");
}

val main : unit -> unit
function main() = {
    test_nop_does_not_change_registers();
    test_nop_does_not_change_cursor();
    test_nop_does_not_change_flags();
}
```

- [ ] **Step 5: Register NOP test in test/CMakeLists.txt**

Add at the end of `test/CMakeLists.txt`:

```cmake
add_sail_test(test_nop test/parser/test_nop.sail)
```

- [ ] **Step 6: Build and run the NOP test**

Run: `./dev.sh cmake -B build && ./dev.sh cmake --build build`
Expected: Compiles successfully.

Run: `./dev.sh ctest --test-dir build --verbose`
Expected: `test_nop` passes (exit 0).

Note: The `add_sail_test` function compiles the test .sail file together with all model files. The Sail command will be something like:
```
sail -c model/main.sail test/parser/test_nop.sail -o test_nop.c
```
You may need to adjust the `add_sail_test` function to use `model/main.sail` (which includes everything via `$include`) rather than listing all model files separately. If `$include` handles the dependency chain, only `model/main.sail` and the test file need to be passed to Sail. Adjust accordingly.

- [ ] **Step 7: Commit**

```bash
git add model/parser/insts.sail model/parser/decode.sail model/main.sail \
        test/parser/test_nop.sail test/CMakeLists.txt
git commit -m "Add NOP instruction with tests"
```

---

### Task 5: HALT and HALTDROP Instructions

**Files:**
- Modify: `model/parser/insts.sail`
- Create: `test/parser/test_halt.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Write HALT test**

Create `test/parser/test_halt.sail`:

```sail
// Tests for the HALT and HALTDROP instructions.

val test_halt_sets_halted_flag : unit -> unit
function test_halt_sets_halted_flag() = {
    parser_init();
    assert(parser_halted == false, "parser should start not halted");

    let result = execute(PHALT(false));

    assert(result == RETIRE_HALT, "HALT should return RETIRE_HALT");
    assert(parser_halted == true, "HALT should set parser_halted flag");
    assert(parser_drop == false, "HALT should not set drop flag");
}

val test_haltdrop_sets_both_flags : unit -> unit
function test_haltdrop_sets_both_flags() = {
    parser_init();

    let result = execute(PHALT(true));

    assert(result == RETIRE_DROP, "HALTDROP should return RETIRE_DROP");
    assert(parser_halted == true, "HALTDROP should set parser_halted flag");
    assert(parser_drop == true, "HALTDROP should set drop flag");
}

val test_halt_does_not_modify_registers : unit -> unit
function test_halt_does_not_modify_registers() = {
    parser_init();
    PR[0] = 0xDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF;

    let _ = execute(PHALT(false));

    assert(PR[0] == 0xDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF,
           "HALT should not modify registers");
}

val test_halt_does_not_modify_cursor : unit -> unit
function test_halt_does_not_modify_cursor() = {
    parser_init();
    pcursor = 0x10;

    let _ = execute(PHALT(false));

    assert(pcursor == 0x10, "HALT should not modify cursor");
}

val main : unit -> unit
function main() = {
    test_halt_sets_halted_flag();
    test_haltdrop_sets_both_flags();
    test_halt_does_not_modify_registers();
    test_halt_does_not_modify_cursor();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./dev.sh cmake --build build`
Expected: FAIL — `execute(PHALT(...))` has no matching clause yet.

- [ ] **Step 3: Add HALT execute clause to model/parser/insts.sail**

Add before `end execute`:

```sail
// HALT: Terminate parsing.
// PHALT(false) = HALT — stop parsing, hand off to MAP.
// PHALT(true)  = HALTDROP — stop parsing, drop the packet.
function clause execute(PHALT(drop)) = {
    parser_halted = true;
    if drop then {
        parser_drop = true;
        RETIRE_DROP
    } else {
        RETIRE_HALT
    }
}
```

- [ ] **Step 4: Register test and run**

Add to `test/CMakeLists.txt`:
```cmake
add_sail_test(test_halt test/parser/test_halt.sail)
```

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --verbose`
Expected: Both `test_nop` and `test_halt` pass.

- [ ] **Step 5: Commit**

```bash
git add model/parser/insts.sail test/parser/test_halt.sail test/CMakeLists.txt
git commit -m "Add HALT and HALTDROP instructions with tests"
```

---

### Task 6: MOV and MOVI Instructions

**Files:**
- Modify: `model/parser/insts.sail`
- Create: `test/parser/test_mov.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Write MOV/MOVI tests**

Create `test/parser/test_mov.sail`:

```sail
// Tests for MOV and MOVI instructions.
//
// MOV copies a range of bits from a source register to a destination register.
// MOVI loads an immediate value into a destination register.
//
// Per the XISA spec (Section 3.12.11):
//   MOV: DestReg[i:j] = SourceReg[k:l]
//     j = DestOffsetBits (range 0-127)
//     l = SrcOffsetBits (range 0-127)
//     i = DestOffsetBits + SizeBits (range 1-128)
//     k = SrcOffsetBits + SizeBits (range 1-128)
//
//   MOVI: DestReg[i:j] = ImmediateValue[k-1:0]
//     j = DestOffsetBytes * 8
//     i = (DestOffsetBytes * 8) + SizeBits
//     k = SizeBits
//     DestOffsetBytes range 0-15, SizeBits range 1-16

val test_mov_full_register : unit -> unit
function test_mov_full_register() = {
    parser_init();
    PR[0] = 0xAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD;
    PR[1] = zeros();

    // MOV R1, 0, R0, 0, 128 — copy all 128 bits
    let _ = execute(PMOV(PR1, 0x00, PR0, 0x00, 0x80));

    assert(PR[1] == 0xAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD,
           "MOV should copy full register");
    assert(PR[0] == 0xAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD,
           "MOV should not modify source register");
}

val test_mov_partial_bits : unit -> unit
function test_mov_partial_bits() = {
    parser_init();
    // Source: R0 has 0xFF in bits [7:0]
    PR[0] = 0x00000000_00000000_00000000_000000FF;
    PR[1] = zeros();

    // MOV R1, dest_offset=8, R0, src_offset=0, size=8
    // Copies R0[7:0] into R1[15:8]
    let _ = execute(PMOV(PR1, 0x08, PR0, 0x00, 0x08));

    assert(PR[1] == 0x00000000_00000000_00000000_0000FF00,
           "MOV should copy bits to correct offset in destination");
}

val test_mov_to_null_register : unit -> unit
function test_mov_to_null_register() = {
    parser_init();
    PR[0] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;

    // MOV to null register should be discarded
    let result = execute(PMOV(PRN, 0x00, PR0, 0x00, 0x80));

    assert(result == RETIRE_SUCCESS, "MOV to PRN should succeed");
    // PRN reads as zero, and underlying PR[0] should be unchanged
    assert(PR[0] == 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF,
           "MOV to null register should not corrupt other registers");
}

val test_mov_preserves_other_bits : unit -> unit
function test_mov_preserves_other_bits() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000FF;
    PR[1] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;

    // MOV R1, dest_offset=0, R0, src_offset=0, size=8
    // Should only overwrite R1[7:0], leaving R1[127:8] unchanged.
    let _ = execute(PMOV(PR1, 0x00, PR0, 0x00, 0x08));

    assert(PR[1] == 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF,
           "MOV should preserve other bits in destination (0xFF overwrites 0xFF here)");

    // Better test: source has different value than destination bits
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0x11111111_11111111_11111111_11111100;
    let _ = execute(PMOV(PR1, 0x00, PR0, 0x00, 0x08));

    assert(PR[1] == 0x11111111_11111111_11111111_111111AB,
           "MOV should only overwrite the target bit range");
}

val test_movi_load_immediate : unit -> unit
function test_movi_load_immediate() = {
    parser_init();
    PR[0] = zeros();

    // MOVI R0, dest_offset_bytes=0, immediate=0xABCD, size_bits=16
    // Loads 0xABCD into R0[15:0]
    let _ = execute(PMOVI(PR0, 0x00, 0xABCD, 0x10));

    assert(PR[0] == 0x00000000_00000000_00000000_0000ABCD,
           "MOVI should load immediate into low bits");
}

val test_movi_with_byte_offset : unit -> unit
function test_movi_with_byte_offset() = {
    parser_init();
    PR[0] = zeros();

    // MOVI R0, dest_offset_bytes=2, immediate=0xFF, size_bits=8
    // dest_offset_bits = 2 * 8 = 16, so loads into R0[23:16]
    let _ = execute(PMOVI(PR0, 0x02, 0x00FF, 0x08));

    assert(PR[0] == 0x00000000_00000000_00000000_00FF0000,
           "MOVI should load at correct byte offset");
}

val main : unit -> unit
function main() = {
    test_mov_full_register();
    test_mov_partial_bits();
    test_mov_to_null_register();
    test_mov_preserves_other_bits();
    test_movi_load_immediate();
    test_movi_with_byte_offset();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./dev.sh cmake --build build`
Expected: FAIL — no execute clause for PMOV/PMOVI.

- [ ] **Step 3: Add MOV and MOVI execute clauses to model/parser/insts.sail**

Add before `end execute`:

```sail
// MOV: DestReg[dest_offset + size - 1 : dest_offset] = SourceReg[src_offset + size - 1 : src_offset]
// Bit-field copy between registers. Other bits in destination are preserved.
function clause execute(PMOV(rd, dest_offset, rs, src_offset, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
    let doff : nat = unsigned(dest_offset);
    let soff : nat = unsigned(src_offset);
    let sz   : nat = unsigned(size_bits);
    let extracted = extract_bits(src_val, soff, sz);
    let result = insert_bits(dst_val, doff, sz, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVI: DestReg[(dest_offset_bytes*8) + size_bits - 1 : (dest_offset_bytes*8)] = immediate[size_bits-1:0]
// Load an immediate value (up to 16 bits) into a register at a byte-aligned offset.
function clause execute(PMOVI(rd, dest_offset_bytes, immediate, size_bits)) = {
    let dst_val = read_preg(rd);
    let doff : nat = unsigned(dest_offset_bytes) * 8;
    let sz   : nat = unsigned(size_bits);
    let imm_128 : bits128 = sail_zero_extend(immediate, 128);
    let result = insert_bits(dst_val, doff, sz, imm_128);
    write_preg(rd, result);
    RETIRE_SUCCESS
}
```

- [ ] **Step 4: Register test and run**

Add to `test/CMakeLists.txt`:
```cmake
add_sail_test(test_mov test/parser/test_mov.sail)
```

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --verbose`
Expected: All tests pass (`test_nop`, `test_halt`, `test_mov`).

- [ ] **Step 5: Commit**

```bash
git add model/parser/insts.sail test/parser/test_mov.sail test/CMakeLists.txt
git commit -m "Add MOV and MOVI instructions with tests"
```

---

### Task 7: EXT Instruction

**Files:**
- Modify: `model/parser/insts.sail`
- Create: `test/parser/test_ext.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Write EXT tests**

Create `test/parser/test_ext.sail`:

```sail
// Tests for the EXT (Extract) instruction.
//
// Per the XISA spec (Section 3.12.3):
//   EXT: DestReg[i-1:j] = Packet[l:k-1]
//     j = DestOffsetBits (range 0-127)
//     l = SourceOffsetBits, offset from current cursor position (range 0-511)
//     i = DestOffsetBits + SizeBits (range 1-128)
//     k = SourceOffsetBits + SizeBits (range 1-128)
//
// The packet is accessed relative to the cursor position.

// Helper: load bytes into the packet header buffer at a given offset.
val load_packet_bytes : (nat, list(bits8)) -> unit
function load_packet_bytes(start, bytes) = {
    match bytes {
        [||] => (),
        b :: rest => {
            packet_hdr[start] = b;
            load_packet_bytes(start + 1, rest)
        }
    }
}

val test_ext_basic : unit -> unit
function test_ext_basic() = {
    parser_init();

    // Load a simple packet: bytes 0x01, 0x02, 0x03, 0x04 at position 0
    packet_hdr[0] = 0x01;
    packet_hdr[1] = 0x02;
    packet_hdr[2] = 0x03;
    packet_hdr[3] = 0x04;

    // Cursor at 0, extract 16 bits (2 bytes) from packet offset 0 into R0 at offset 0
    pcursor = 0x00;
    let _ = execute(PEXT(PR0, 0x00, 0x0000, 0x10, false));

    // Bytes 0x01, 0x02 extracted. In big-endian, 0x01 is MSB.
    // As 16 bits placed at offset 0 in R0: R0[15:0] = 0x0102
    assert(PR[0] == 0x00000000_00000000_00000000_00000102,
           "EXT should extract 2 bytes from packet into register");
}

val test_ext_with_cursor_offset : unit -> unit
function test_ext_with_cursor_offset() = {
    parser_init();

    packet_hdr[0] = 0xAA;
    packet_hdr[1] = 0xBB;
    packet_hdr[2] = 0xCC;
    packet_hdr[3] = 0xDD;

    // Cursor at byte 2, extract 8 bits (1 byte) from packet offset 0 (relative to cursor)
    // Actual packet position = cursor + source_offset/8 = byte 2
    pcursor = 0x02;
    let _ = execute(PEXT(PR0, 0x00, 0x0000, 0x08, false));

    assert(PR[0] == 0x00000000_00000000_00000000_000000CC,
           "EXT should extract relative to cursor position");
}

val test_ext_with_source_offset : unit -> unit
function test_ext_with_source_offset() = {
    parser_init();

    packet_hdr[0] = 0xAA;
    packet_hdr[1] = 0xBB;
    packet_hdr[2] = 0xCC;
    packet_hdr[3] = 0xDD;

    // Cursor at 0, extract 8 bits from packet offset 16 bits (= 2 bytes from cursor)
    pcursor = 0x00;
    let _ = execute(PEXT(PR0, 0x00, 0x0010, 0x08, false));

    assert(PR[0] == 0x00000000_00000000_00000000_000000CC,
           "EXT should respect source offset from cursor");
}

val test_ext_with_dest_offset : unit -> unit
function test_ext_with_dest_offset() = {
    parser_init();

    packet_hdr[0] = 0xFF;

    // Extract 8 bits from packet offset 0, place at dest offset 112 (byte 14, near MSB)
    pcursor = 0x00;
    let _ = execute(PEXT(PR0, 0x70, 0x0000, 0x08, false));

    // R0[119:112] = 0xFF
    assert(PR[0] == 0x00FF0000_00000000_00000000_00000000,
           "EXT should place data at correct destination offset");
}

val test_ext_with_clear_dest : unit -> unit
function test_ext_with_clear_dest() = {
    parser_init();
    PR[0] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;

    packet_hdr[0] = 0xAB;

    // EXT.CD: clear destination register before extraction
    pcursor = 0x00;
    let _ = execute(PEXT(PR0, 0x00, 0x0000, 0x08, true));

    assert(PR[0] == 0x00000000_00000000_00000000_000000AB,
           "EXT.CD should clear register then place extracted data");
}

val test_ext_preserves_other_bits_without_cd : unit -> unit
function test_ext_preserves_other_bits_without_cd() = {
    parser_init();
    PR[0] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFF00;

    packet_hdr[0] = 0xAB;

    // EXT without .CD: other bits in R0 should be preserved
    pcursor = 0x00;
    let _ = execute(PEXT(PR0, 0x00, 0x0000, 0x08, false));

    assert(PR[0] == 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFAB,
           "EXT without .CD should preserve other bits");
}

val main : unit -> unit
function main() = {
    test_ext_basic();
    test_ext_with_cursor_offset();
    test_ext_with_source_offset();
    test_ext_with_dest_offset();
    test_ext_with_clear_dest();
    test_ext_preserves_other_bits_without_cd();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./dev.sh cmake --build build`
Expected: FAIL — no execute clause for PEXT.

- [ ] **Step 3: Add EXT execute clause to model/parser/insts.sail**

Add before `end execute`:

```sail
// EXT: Extract data from packet buffer into a register.
// DestReg[dest_offset + size - 1 : dest_offset] = Packet[cursor*8 + src_offset + size - 1 : cursor*8 + src_offset]
//
// The source offset is in bits, relative to the cursor position (which is in bytes).
// Data is extracted from the packet in big-endian order.
// If clear_dest is true (.CD modifier), the destination register is cleared before extraction.
function clause execute(PEXT(rd, dest_offset, src_offset_bits, size_bits, clear_dest)) = {
    let doff : nat = unsigned(dest_offset);
    let soff : nat = unsigned(src_offset_bits);
    let sz   : nat = unsigned(size_bits);
    let cursor_bit_offset : nat = unsigned(pcursor) * 8;
    let packet_bit_offset : nat = cursor_bit_offset + soff;

    // Read sz bits from packet starting at packet_bit_offset (big-endian).
    // The packet is stored as a byte array. We reconstruct the bits.
    let start_byte : nat = packet_bit_offset / 8;
    let bit_in_byte : nat = packet_bit_offset % 8;

    // Read enough bytes to cover the extraction.
    // We need ceil((bit_in_byte + sz) / 8) bytes.
    let bytes_needed : nat = (bit_in_byte + sz + 7) / 8;

    // Accumulate bytes into a 128-bit value (big-endian).
    var acc : bits128 = zeros();
    var i : nat = 0;
    while i < bytes_needed do {
        let byte_idx : nat = start_byte + i;
        let byte_val : bits128 = sail_zero_extend(packet_hdr[byte_idx], 128);
        // Place this byte at the correct position (big-endian: first byte is most significant)
        acc = acc | (byte_val << (8 * (bytes_needed - 1 - i)));
        i = i + 1;
    };

    // Now acc has the bytes in big-endian order. Shift right to align the extracted bits.
    // The bits we want start at bit_in_byte from the MSB of our accumulated value.
    let total_bits : nat = bytes_needed * 8;
    let shift_amount : nat = total_bits - bit_in_byte - sz;
    let extracted : bits128 = (acc >> shift_amount) & sail_mask(128, sail_ones(sz));

    // Write to destination register
    let dst_val : bits128 = if clear_dest then zeros() else read_preg(rd);
    let result = insert_bits(dst_val, doff, sz, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}
```

- [ ] **Step 4: Register test and run**

Add to `test/CMakeLists.txt`:
```cmake
add_sail_test(test_ext test/parser/test_ext.sail)
```

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --verbose`
Expected: All tests pass (`test_nop`, `test_halt`, `test_mov`, `test_ext`).

- [ ] **Step 5: Commit**

```bash
git add model/parser/insts.sail test/parser/test_ext.sail test/CMakeLists.txt
git commit -m "Add EXT instruction with tests"
```

---

### Task 8: Documentation

**Files:**
- Create: `docs/dev-commands.md`
- Create: `docs/coverage.md`
- Create: `docs/todo.md`
- Modify: `README.md`

- [ ] **Step 1: Create docs/dev-commands.md**

```markdown
# Development Commands Reference

All commands are run through `dev.sh`, which executes them inside the dev container.

## First-Time Setup

```bash
# Build the dev container (one-time, or after Dockerfile changes)
devcontainer build --workspace-folder .

# Verify Sail is installed
./dev.sh sail --version
```

## Building

```bash
# Configure the build (one-time, or after CMakeLists.txt changes)
./dev.sh cmake -B build

# Type-check the Sail model (fast, no C compilation)
./dev.sh cmake --build build --target check

# Full build (type-check + compile tests)
./dev.sh cmake --build build
```

## Testing

```bash
# Run all tests
./dev.sh ctest --test-dir build

# Run all tests with verbose output (shows pass/fail per test)
./dev.sh ctest --test-dir build --verbose

# Run a specific test by name
./dev.sh ctest --test-dir build -R test_nop --verbose
```

## Interactive

```bash
# Open a shell inside the dev container
./dev.sh bash

# Run the Sail interactive interpreter on the model
./dev.sh sail -i model/main.sail
```

## Common Workflows

### Adding a new instruction

1. Add the union clause to `model/parser/types.sail`
2. Add the execute clause to `model/parser/insts.sail`
3. Create a test file in `test/parser/test_<name>.sail`
4. Register the test in `test/CMakeLists.txt`
5. Build and test: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --verbose`

### Debugging a test failure

```bash
# Run just the failing test with verbose output
./dev.sh ctest --test-dir build -R test_name --verbose

# Or run the test executable directly for more detail
./dev.sh ./build/test_name
```
```

- [ ] **Step 2: Create docs/coverage.md**

```markdown
# XISA Spec Coverage

Tracks which XISA instructions are formally specified in Sail.

## Parser ISA (Section 3 of XISA spec)

| # | Instruction | Spec Section | Status | Notes |
|---|-------------|-------------|--------|-------|
| 1 | NOP | 3.12.20 | Done | |
| 2 | HALT | 3.12.19 | Done | Simplified: no .RP or MAP-PC support yet |
| 3 | HALTDROP | 3.12.19 | Done | Simplified: no .RP support yet |
| 4 | MOV | 3.12.11 | Done | No .CD modifier yet |
| 5 | MOVI | 3.12.11 | Done | No .CD modifier yet |
| 6 | EXT | 3.12.3 | Done | No .PR, .SCSM, .ECSM modifiers yet. .CD supported. |
| 7 | EXTNXTP | 3.12.3 | Not started | |
| 8 | NXTP | 3.12.1 | Not started | Requires transition table model |
| 9 | PSEEK | 3.12.2 | Not started | Requires PSEEK table model |
| 10 | PSEEKNXTP | 3.12.2 | Not started | |
| 11 | EXTMAP | 3.12.4 | Not started | Requires MAP register model |
| 12 | MOVMAP | 3.12.5 | Not started | Requires MAP register model |
| 13 | CNCTBY | 3.12.6 | Not started | |
| 14 | CNCTBI | 3.12.6 | Not started | |
| 15 | STH | 3.12.7 | Not started | Requires HDR model |
| 16 | STC | 3.12.8 | Not started | |
| 17 | STCI | 3.12.8 | Not started | |
| 18 | STCH | 3.12.9 | Not started | |
| 19 | STHC | 3.12.9 | Not started | |
| 20 | ST | 3.12.10 | Not started | Requires Struct model |
| 21 | STI | 3.12.10 | Not started | |
| 22 | MOVL/MOVR variants | 3.12.12 | Not started | 6 sub-variants |
| 23 | ADD/ADDI | 3.12.13 | Not started | |
| 24 | SUB/SUBI/SUBII | 3.12.14 | Not started | |
| 25 | AND/ANDI | 3.12.15 | Not started | |
| 26 | OR/ORI | 3.12.16 | Not started | |
| 27 | CMP/CMPIBY/CMPIBI | 3.12.17 | Not started | |
| 28 | BR variants | 3.12.18 | Not started | 6 sub-variants |

## MAP ISA (Section 4 of XISA spec)

Not yet started. See Section 4.12 of the XISA white paper for the full instruction list (~54 instructions).
```

- [ ] **Step 3: Create docs/todo.md**

```markdown
# Tech Debt and Known Issues

## Current

- **Instruction encoding not modeled**: `model/parser/decode.sail` is a placeholder. The XISA white paper does not publish full binary encoding formats, so we test by constructing instruction union values directly. If encodings become available, add `mapping clause encdec` for each instruction.

- **MOV/MOVI .CD modifier not modeled**: The .CD (clear destination) optional modifier is not yet supported for MOV and MOVI. It should clear the destination register before writing. Currently only EXT supports .CD.

- **HALT simplifications**: The HALT instruction does not model the `.RP` (reparse) modifier, the optional MAP-PC entry point, or the optional PARSER-PC jump address. These require modeling the MAP thread handoff and reparse flow.

- **EXT simplifications**: The EXT instruction does not model the `.PR` (present bit), `.SCSM` (start checksum), or `.ECSM` (end checksum) modifiers. These require the checksum accelerator and HDR.PRESENT models.

- **No fetch-decode-execute loop**: `model/main.sail` only includes files; there is no `step()` function that fetches from instruction memory. Tests call `execute()` directly with constructed instruction values.

- **Sail helper functions may not match Sail stdlib**: `extract_bits` and `insert_bits` in `state.sail` are custom helpers. Sail's standard library may have built-in equivalents (`vector_subrange`, `vector_update_subrange`) that would be more idiomatic. Investigate and refactor if so.

## Resolved

(None yet)
```

- [ ] **Step 4: Update README.md**

Replace the contents of `README.md` with:

```markdown
# Sail XISA

A formal specification of [XISA](https://xsightlabs.com/switches/xisa) (Xsight Labs' X-Switch Instruction Set Architecture) written in [Sail](https://github.com/rems-project/sail).

XISA defines packet processing for the X-Switch family of programmable network switches. This project provides a machine-readable, executable formal model of the ISA, inspired by the [Sail RISC-V model](https://github.com/riscv/sail-riscv).

## Quick Start

Requires the [devcontainer CLI](https://github.com/devcontainers/cli).

```bash
# Build the dev container
devcontainer build --workspace-folder .

# Configure and build
./dev.sh cmake -B build
./dev.sh cmake --build build

# Run tests
./dev.sh ctest --test-dir build --verbose
```

See [docs/dev-commands.md](docs/dev-commands.md) for the full commands reference.

## Status

See [docs/coverage.md](docs/coverage.md) for spec coverage and [docs/todo.md](docs/todo.md) for known issues.

## License

[Apache License 2.0](LICENSE)
```

- [ ] **Step 5: Commit**

```bash
git add docs/dev-commands.md docs/coverage.md docs/todo.md README.md
git commit -m "Add development docs, coverage tracker, and tech debt log"
```

---

### Task 9: Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Clean build from scratch**

Run:
```bash
./dev.sh rm -rf build
./dev.sh cmake -B build
./dev.sh cmake --build build
```

Expected: Clean build with no warnings or errors.

- [ ] **Step 2: Run full test suite**

Run: `./dev.sh ctest --test-dir build --verbose`

Expected output (4 tests, all pass):
```
test_nop ... Passed
test_halt ... Passed
test_mov ... Passed
test_ext ... Passed

100% tests passed, 0 tests failed
```

- [ ] **Step 3: Run type-check target**

Run: `./dev.sh cmake --build build --target check`
Expected: Exits 0, no type errors.

- [ ] **Step 4: Review all files for consistency**

Verify:
- All instruction names in `docs/coverage.md` match the union clauses in `model/parser/types.sail`
- All test files listed in `test/CMakeLists.txt` exist
- `docs/todo.md` accurately reflects current simplifications
- `docs/dev-commands.md` commands work as documented

- [ ] **Step 5: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "Fix issues found during final verification"
```
