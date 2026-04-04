# Differential Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a differential testing harness that runs the same binary programs on both the Rust simulator and Sail C emulator, comparing final parser state.

**Architecture:** A C harness links against Sail-generated C code and reads binary files. A Rust integration test assembles programs, runs both simulators, and compares JSON state output. Proptest fuzzes packet data for programs that access packets.

**Tech Stack:** C (GMP for 128-bit values), Sail→C compilation, Rust (serde_json, proptest), CMake

---

### Task 1: Create the dummy Sail main and C harness

**Files:**
- Create: `test/diff/main.sail`
- Create: `test/diff/harness.c`

- [ ] **Step 1: Create the dummy Sail main**

The Sail→C compiler generates a `main()` that calls `zmain()`. We need a Sail file that defines `main` so the generated C compiles. Our C harness will replace the generated `main()` via a compile flag.

Create `test/diff/main.sail`:

```sail
// Dummy main for the differential testing harness.
// The real entry point is in harness.c.
val main : unit -> unit
function main() = ()
```

- [ ] **Step 2: Create the C harness**

Create `test/diff/harness.c`:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gmp.h>
#include "sail.h"
#include "rts.h"

// Forward declarations from Sail-generated code.
void model_init(void);
void model_fini(void);

// Sail-generated functions.
extern unit zparser_init(unit);

// zwrite_pimem_raw takes a sail_int (mpz_t) index and a uint64_t value.
extern unit zwrite_pimem_raw(sail_int, uint64_t);

extern enum zExecutionResult zparser_run(unit);

// Sail-generated register globals.
extern zz5vecz8z5bvz9 zPR;           // PR[0..3], each is lbits
extern uint64_t zppc;
extern uint64_t zpcursor;
extern bool zpflag_zz;                // pflag_z (Sail name-mangles the trailing z)
extern bool zpflag_n;
extern bool zparser_halted;
extern bool zparser_drop;
extern lbits zstruct0;
extern zz5vecz8z5boolz9 zhdr_present; // bool vector, len=32
extern zz5vecz8z5bv8z9 zhdr_offset;   // uint64_t vector, len=32
extern zz5vecz8z5bv8z9 zpacket_hdr;   // uint64_t vector, len=256

// Print a 128-bit lbits value as a 0x-prefixed 32-digit hex string.
static void print_lbits_hex(FILE *f, const lbits *val) {
    char *str = mpz_get_str(NULL, 16, *val->bits);
    // Pad to 32 hex digits.
    size_t len = strlen(str);
    fprintf(f, "\"0x");
    for (size_t i = len; i < 32; i++) fprintf(f, "0");
    fprintf(f, "%s\"", str);
    free(str);
}

// Dump parser-observable state as JSON to stdout.
static void dump_state(void) {
    printf("{\n");

    // pc
    printf("  \"pc\": %lu,\n", (unsigned long)zppc);

    // regs
    printf("  \"regs\": [\n");
    for (int i = 0; i < 4; i++) {
        printf("    ");
        print_lbits_hex(stdout, &zPR.data[i]);
        printf("%s\n", i < 3 ? "," : "");
    }
    printf("  ],\n");

    // flags
    printf("  \"flag_z\": %s,\n", zpflag_zz ? "true" : "false");
    printf("  \"flag_n\": %s,\n", zpflag_n ? "true" : "false");

    // cursor
    printf("  \"cursor\": %lu,\n", (unsigned long)zpcursor);

    // halted, dropped
    printf("  \"halted\": %s,\n", zparser_halted ? "true" : "false");
    printf("  \"dropped\": %s,\n", zparser_drop ? "true" : "false");

    // struct0
    printf("  \"struct0\": ");
    print_lbits_hex(stdout, &zstruct0);
    printf(",\n");

    // hdr_present
    printf("  \"hdr_present\": [");
    for (int i = 0; i < 32; i++) {
        printf("%s%s", zhdr_present.data[i] ? "true" : "false", i < 31 ? ", " : "");
    }
    printf("],\n");

    // hdr_offset
    printf("  \"hdr_offset\": [");
    for (int i = 0; i < 32; i++) {
        printf("%lu%s", (unsigned long)zhdr_offset.data[i], i < 31 ? ", " : "");
    }
    printf("]\n");

    printf("}\n");
}

// Usage: sail-c-emu-harness <program.bin> [packet.bin]
int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: sail-c-emu-harness <program.bin> [packet.bin]\n");
        return 1;
    }

    // Initialize the Sail runtime and all registers.
    model_init();
    zparser_init(UNIT);

    // Load program binary.
    FILE *prog = fopen(argv[1], "rb");
    if (!prog) {
        fprintf(stderr, "Error: cannot open %s\n", argv[1]);
        model_fini();
        return 1;
    }

    uint8_t buf[8];
    sail_int idx;
    CREATE(sail_int)(&idx);
    int pc = 0;
    while (fread(buf, 1, 8, prog) == 8) {
        uint64_t word = 0;
        for (int i = 0; i < 8; i++) {
            word = (word << 8) | buf[i];
        }
        mpz_set_si(*idx, pc);
        zwrite_pimem_raw(idx, word);
        pc++;
    }
    fclose(prog);
    KILL(sail_int)(&idx);

    // Load packet data (optional).
    if (argc >= 3) {
        FILE *pkt = fopen(argv[2], "rb");
        if (!pkt) {
            fprintf(stderr, "Error: cannot open %s\n", argv[2]);
            model_fini();
            return 1;
        }
        uint8_t pkt_buf[256];
        memset(pkt_buf, 0, 256);
        size_t n = fread(pkt_buf, 1, 256, pkt);
        fclose(pkt);
        (void)n;

        // Write into zpacket_hdr vector (each element is a uint64_t holding one byte).
        for (int i = 0; i < 256; i++) {
            zpacket_hdr.data[i] = pkt_buf[i];
        }
    }

    // Run the parser.
    zparser_run(UNIT);

    // Dump state.
    dump_state();

    model_fini();
    return 0;
}
```

- [ ] **Step 3: Commit**

```bash
git add test/diff/main.sail test/diff/harness.c
git commit -m "Add Sail C emulator harness for differential testing"
```

---

### Task 2: Add CMake build target for the harness

**Files:**
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Add the harness build target**

Add to the end of `test/CMakeLists.txt`:

```cmake
# Differential testing harness
# Compile model + dummy main to C, then link with our custom harness.c
set(DIFF_SAIL_STEM "${CMAKE_CURRENT_BINARY_DIR}/diff_model")
set(DIFF_C "${DIFF_SAIL_STEM}.c")

add_custom_command(
    OUTPUT ${DIFF_C}
    COMMAND ${SAIL} -c
        ${CMAKE_SOURCE_DIR}/model/main.sail
        ${CMAKE_SOURCE_DIR}/test/diff/main.sail
        -o ${DIFF_SAIL_STEM}
    DEPENDS ${MODEL_SAIL_FILES} ${CMAKE_SOURCE_DIR}/test/diff/main.sail
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Compiling Sail model for diff testing harness..."
)

add_executable(sail-c-emu-harness
    ${DIFF_C}
    ${CMAKE_SOURCE_DIR}/test/diff/harness.c
    ${SAIL_DIR}/lib/sail.c
    ${SAIL_DIR}/lib/rts.c
    ${SAIL_DIR}/lib/elf.c
    ${SAIL_DIR}/lib/sail_failure.c
)
target_include_directories(sail-c-emu-harness PRIVATE
    ${SAIL_DIR}/lib
    ${CMAKE_CURRENT_BINARY_DIR}  # for the generated .h file
)
target_link_libraries(sail-c-emu-harness PRIVATE gmp z)
target_compile_options(sail-c-emu-harness PRIVATE -O2)
# Rename the Sail-generated main() to avoid conflict with our harness main().
# Only apply to the generated C file, not harness.c.
set_source_files_properties(${DIFF_C} PROPERTIES COMPILE_DEFINITIONS "main=__sail_generated_main")
```

- [ ] **Step 2: Build and test the harness**

```bash
./dev.sh bash -c "cmake --build build --target sail-c-emu-harness 2>&1 | tail -10"
```

Expected: builds successfully.

Then test with an existing binary:

```bash
./dev.sh bash -c "cd playground && cargo run --bin xisa-asm -- examples/simple-branch.xisa /tmp/test.bin 2>/dev/null && ../build/test/sail-c-emu-harness /tmp/test.bin"
```

Expected: JSON output of parser state.

- [ ] **Step 3: Commit**

```bash
git add test/CMakeLists.txt
git commit -m "Add CMake build target for diff testing harness"
```

---

### Task 3: Add Rust helper to produce comparable JSON from Rust simulator

**Files:**
- Create: `playground/src/diff.rs`
- Modify: `playground/src/lib.rs`

The Rust `SimState` serialization (from `xisa-sim`) includes many fields the Sail harness doesn't output (map_regs, transition tables, step_count, etc.). We need a function that extracts only the parser-observable fields and serializes them in the same format.

- [ ] **Step 1: Create the diff module**

Create `playground/src/diff.rs`:

```rust
use serde::Serialize;
use crate::state::SimState;

/// Parser-observable state for differential testing.
/// Matches the JSON format produced by the Sail C emulator harness.
#[derive(Debug, Serialize, PartialEq)]
pub struct DiffState {
    pub pc: u16,
    pub regs: [String; 4],
    pub flag_z: bool,
    pub flag_n: bool,
    pub cursor: u8,
    pub halted: bool,
    pub dropped: bool,
    pub struct0: String,
    pub hdr_present: Vec<bool>,
    pub hdr_offset: Vec<u8>,
}

impl DiffState {
    /// Extract the parser-observable state from a SimState.
    pub fn from_sim_state(state: &SimState) -> Self {
        DiffState {
            pc: state.pc,
            regs: [
                format!("0x{:032x}", state.regs[0]),
                format!("0x{:032x}", state.regs[1]),
                format!("0x{:032x}", state.regs[2]),
                format!("0x{:032x}", state.regs[3]),
            ],
            flag_z: state.flag_z,
            flag_n: state.flag_n,
            cursor: state.cursor,
            halted: state.halted,
            dropped: state.dropped,
            struct0: format!("0x{:032x}", state.struct0),
            hdr_present: state.hdr_present.to_vec(),
            hdr_offset: state.hdr_offset.to_vec(),
        }
    }

    /// Parse from JSON string (for parsing Sail harness output).
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}
```

- [ ] **Step 2: Add `Deserialize` to the struct**

Update the derive to include `Deserialize` (needed for `from_json`):

```rust
use serde::{Serialize, Deserialize};

#[derive(Debug, Serialize, Deserialize, PartialEq)]
pub struct DiffState {
```

- [ ] **Step 3: Export the module from `lib.rs`**

Add to `playground/src/lib.rs`:

```rust
pub mod diff;
```

- [ ] **Step 4: Verify it compiles**

Run: `./dev.sh bash -c "cd playground && cargo check"`

- [ ] **Step 5: Commit**

```bash
git add playground/src/diff.rs playground/src/lib.rs
git commit -m "Add diff module for parser-observable state comparison"
```

---

### Task 4: Create the Rust integration test

**Files:**
- Create: `playground/tests/diff_test.rs`

- [ ] **Step 1: Create the diff test**

Create `playground/tests/diff_test.rs`:

```rust
use std::io::Write;
use std::process::Command;

use xisa::assembler::assemble;
use xisa::diff::DiffState;
use xisa::execute;
use xisa::state::SimState;

/// Path to the Sail C emulator harness binary.
/// Built by CMake: cmake --build build --target sail-c-emu-harness
const HARNESS_PATH: &str = "build/test/sail-c-emu-harness";

/// Check if the harness binary exists. If not, skip all diff tests.
fn harness_available() -> bool {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join(HARNESS_PATH);
    path.exists()
}

fn harness_path() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .join(HARNESS_PATH)
}

/// Run a program on the Rust simulator and return the DiffState.
fn run_rust(program_bytes: &[u8], packet: &[u8]) -> DiffState {
    let mut state = SimState::new();

    // Load instructions.
    for chunk in program_bytes.chunks_exact(8) {
        let word = u64::from_be_bytes([
            chunk[0], chunk[1], chunk[2], chunk[3],
            chunk[4], chunk[5], chunk[6], chunk[7],
        ]);
        state.instruction_mem.push(word);
    }

    // Load packet.
    let len = packet.len().min(256);
    state.packet_header[..len].copy_from_slice(&packet[..len]);

    // Run.
    loop {
        match execute::step(&mut state) {
            Ok(result) => {
                if result.halted || result.dropped {
                    break;
                }
            }
            Err(e) => panic!("Rust simulator error: {}", e),
        }
    }

    DiffState::from_sim_state(&state)
}

/// Run a program on the Sail C emulator harness and return the DiffState.
fn run_sail(program_bytes: &[u8], packet: &[u8]) -> DiffState {
    // Write program to temp file.
    let mut prog_file = tempfile::NamedTempFile::new().unwrap();
    prog_file.write_all(program_bytes).unwrap();
    prog_file.flush().unwrap();

    // Write packet to temp file.
    let mut pkt_file = tempfile::NamedTempFile::new().unwrap();
    pkt_file.write_all(packet).unwrap();
    pkt_file.flush().unwrap();

    let output = Command::new(harness_path())
        .arg(prog_file.path())
        .arg(pkt_file.path())
        .output()
        .expect("Failed to run sail-c-emu-harness");

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        panic!("sail-c-emu-harness failed: {}", stderr);
    }

    let stdout = String::from_utf8(output.stdout).unwrap();
    DiffState::from_json(&stdout)
        .unwrap_or_else(|e| panic!("Failed to parse Sail JSON: {}\nOutput: {}", e, stdout))
}

/// Assemble source, run on both simulators, compare.
fn diff_test(source: &str, packet: &[u8]) {
    if !harness_available() {
        eprintln!("Skipping diff test: sail-c-emu-harness not found at {}", HARNESS_PATH);
        return;
    }

    let result = assemble(source).expect("Assembly failed");
    let mut bytes = Vec::new();
    for word in &result.words {
        bytes.extend_from_slice(&word.to_be_bytes());
    }

    let rust_state = run_rust(&bytes, packet);
    let sail_state = run_sail(&bytes, packet);

    assert_eq!(rust_state, sail_state,
        "Rust and Sail states differ!\nRust: {}\nSail: {}",
        serde_json::to_string_pretty(&rust_state).unwrap(),
        serde_json::to_string_pretty(&sail_state).unwrap(),
    );
}

// --- Deterministic tests (no packet data) ---

#[test]
fn diff_simple_halt() {
    diff_test("HALT", &[0u8; 256]);
}

#[test]
fn diff_movi_halt() {
    diff_test("MOVI PR0, 42, 8\nHALT", &[0u8; 256]);
}

#[test]
fn diff_add_program() {
    diff_test(
        "MOVI PR0, 10, 8\nMOVI PR1, 20, 8\nADD PR2, PR0, PR1\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_branch_taken() {
    diff_test(
        "MOVI PR0, 5, 8\nMOVI PR1, 5, 8\nCMP PR0, PR1\nBR.EQ 6\nMOVI PR2, 255, 8\nHALT\nMOVI PR2, 170, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_branch_not_taken() {
    diff_test(
        "MOVI PR0, 3, 8\nMOVI PR1, 5, 8\nCMP PR0, PR1\nBR.EQ 6\nMOVI PR2, 187, 8\nHALT\nMOVI PR2, 204, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_counting_loop() {
    diff_test(
        "MOVI PR0, 3, 8\nSUBI PR0, PR0, 1\nCMP PR0, PR1\nBR.NEQ 1\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_haltdrop() {
    diff_test("MOVI PR0, 1, 8\nHALTDROP", &[0u8; 256]);
}

// --- Packet-dependent tests ---

#[test]
fn diff_ext_fixed_packet() {
    // Extract first 4 bytes of packet into PR0.
    let mut packet = [0u8; 256];
    packet[0] = 0x45; // IPv4 version+IHL
    packet[1] = 0x00;
    packet[2] = 0x00;
    packet[3] = 0x3C;

    diff_test(
        "EXT PR0, 0, 4\nHALT",
        &packet,
    );
}
```

- [ ] **Step 2: Add `tempfile` as a dev-dependency**

In `playground/Cargo.toml`, add:

```toml
[dev-dependencies]
proptest = "1"
tempfile = "3"
```

- [ ] **Step 3: Verify it compiles**

Run: `./dev.sh bash -c "cd playground && cargo test --test diff_test --no-run 2>&1 | tail -5"`

- [ ] **Step 4: Build the harness and run the tests**

```bash
./dev.sh bash -c "cmake --build build --target sail-c-emu-harness && cd playground && cargo test --test diff_test -- --nocapture 2>&1 | tail -30"
```

Expected: all diff tests pass (or skip if harness not available).

- [ ] **Step 5: Commit**

```bash
git add playground/tests/diff_test.rs playground/Cargo.toml
git commit -m "Add differential tests comparing Rust and Sail simulators"
```

---

### Task 5: Add proptest packet fuzzing

**Files:**
- Modify: `playground/tests/diff_test.rs`

- [ ] **Step 1: Add proptest-based packet fuzzing tests**

Append to `playground/tests/diff_test.rs`:

```rust
use proptest::prelude::*;

/// Generate a random 256-byte packet buffer.
fn arb_packet() -> impl Strategy<Value = Vec<u8>> {
    proptest::collection::vec(any::<u8>(), 256)
}

proptest! {
    #[test]
    fn diff_ext_fuzz_packet(packet in arb_packet()) {
        if !harness_available() {
            return Ok(());
        }
        // Extract 4 bytes at offset 0 from packet.
        diff_test("EXT PR0, 0, 4\nHALT", &packet);
    }

    #[test]
    fn diff_ext_with_cursor_fuzz(packet in arb_packet()) {
        if !harness_available() {
            return Ok(());
        }
        // Set cursor to 14 (common Ethernet header size), then extract 2 bytes.
        diff_test("STCI 14\nEXT PR0, 0, 2\nHALT", &packet);
    }
}
```

- [ ] **Step 2: Run the fuzz tests**

```bash
./dev.sh bash -c "cmake --build build --target sail-c-emu-harness && cd playground && cargo test --test diff_test -- --nocapture 2>&1 | tail -30"
```

Expected: all tests pass (deterministic + fuzz).

- [ ] **Step 3: Commit**

```bash
git add playground/tests/diff_test.rs
git commit -m "Add proptest packet fuzzing to differential tests"
```

---

### Task 6: Add existing example programs as diff tests

**Files:**
- Modify: `playground/tests/diff_test.rs`

- [ ] **Step 1: Add tests using example .xisa files**

Append to `playground/tests/diff_test.rs`:

```rust
#[test]
fn diff_example_simple_branch() {
    if !harness_available() {
        return;
    }
    let source = include_str!("../examples/simple-branch.xisa");
    diff_test(source, &[0u8; 256]);
}

#[test]
fn diff_example_extract_ipv4() {
    if !harness_available() {
        return;
    }
    let source = include_str!("../examples/extract-ipv4.xisa");
    // Use a minimal valid IPv4 header.
    let mut packet = [0u8; 256];
    packet[0] = 0x45; // version=4, IHL=5
    packet[1] = 0x00; // DSCP/ECN
    packet[2] = 0x00; // total length (high)
    packet[3] = 0x3C; // total length (low) = 60
    packet[9] = 0x06; // protocol = TCP
    packet[12] = 192; // src IP
    packet[13] = 168;
    packet[14] = 1;
    packet[15] = 1;
    packet[16] = 10; // dst IP
    packet[17] = 0;
    packet[18] = 0;
    packet[19] = 1;
    diff_test(source, &packet);
}
```

- [ ] **Step 2: Run all diff tests**

```bash
./dev.sh bash -c "cmake --build build --target sail-c-emu-harness && cd playground && cargo test --test diff_test -- --nocapture 2>&1 | tail -30"
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add playground/tests/diff_test.rs
git commit -m "Add example program diff tests"
```
