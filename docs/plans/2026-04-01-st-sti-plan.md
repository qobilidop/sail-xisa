# ST/STI Struct Store Instructions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Struct-0 model and ST/STI store-to-struct instructions to the parser ISA model.

**Architecture:** New `struct0` register (128-bit) in state.sail, two new union clauses in types.sail, two execute clauses in insts.sail reusing existing `extract_bits`/`insert_bits` helpers, one test file. Follows established patterns.

**Tech Stack:** Sail, C backend, CMake/CTest

---

### Task 1: Add Struct-0 register to state.sail

**Files:**
- Modify: `model/parser/state.sail`

- [ ] **Step 1: Add struct0 register**

Add after the `hdr_offset` register and before the init functions in `model/parser/state.sail`:

```sail
// Struct-0: 128-bit Standard Metadata (SMD) register.
// Passed from the parser to the MAP after parsing completes.
// Bits 6-31 are HW-controlled in real hardware; not enforced in this model.
register struct0 : bits128
```

- [ ] **Step 2: Initialize struct0 in parser_init()**

Add `struct0 = sail_zeros(128);` in `parser_init()`, after the `hdr_offset = init_hdr_offset();` line:

```sail
    // Reset Struct-0 (Standard Metadata)
    struct0 = sail_zeros(128);
```

- [ ] **Step 3: Verify the model compiles**

Run: `./dev.sh cmake --build build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add model/parser/state.sail
git commit -m "Add Struct-0 register model for Standard Metadata"
```

### Task 2: Add union clauses for ST and STI

**Files:**
- Modify: `model/parser/types.sail`

- [ ] **Step 1: Add PST and PSTI union clauses**

Add before `end pinstr` in `model/parser/types.sail`:

```sail
// ST: Store register sub-field into Struct-0.
// Fields: (src_reg, src_offset_bits, struct_offset_bits, size_bits, halt)
union clause pinstr = PST : (pregidx, bits8, bits8, bits8, bool)

// STI: Store immediate value into Struct-0.
// Fields: (immediate_value, struct_offset_bits, size_bits)
union clause pinstr = PSTI : (bits16, bits8, bits8)
```

- [ ] **Step 2: Verify the model compiles**

Run: `./dev.sh cmake --build build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add model/parser/types.sail
git commit -m "Add union clauses for ST and STI instructions"
```

### Task 3: Write failing tests for STI

**Files:**
- Create: `test/parser/test_st.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create test file with STI tests**

Create `test/parser/test_st.sail`:

```sail
// Tests for ST and STI (store to Struct-0) instructions.

// STI: store immediate into struct0 at offset 0.
val test_sti_basic : unit -> unit
function test_sti_basic() = {
    parser_init();
    let _ = execute(PSTI(0x00AB, 0x00, 0x08));
    assert(struct0 == 0x00000000_00000000_00000000_000000AB, "STI should store 0xAB at struct0[7:0]")
}

// STI: store immediate at non-zero offset.
val test_sti_at_offset : unit -> unit
function test_sti_at_offset() = {
    parser_init();
    let _ = execute(PSTI(0x00FF, 0x20, 0x08));
    assert(struct0 == 0x00000000_00000000_000000FF_00000000, "STI should store 0xFF at struct0[39:32]")
}

val main : unit -> unit
function main() = {
    test_sti_basic();
    test_sti_at_offset()
}
```

- [ ] **Step 2: Register test in CMakeLists.txt**

Add to the end of `test/CMakeLists.txt`:

```cmake
add_sail_test(test_st test/parser/test_st.sail)
```

- [ ] **Step 3: Build and verify tests fail**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_st --verbose 2>&1 | tail -10`
Expected: test_st fails with "Pattern match failure in execute".

### Task 4: Implement STI execute clause

**Files:**
- Modify: `model/parser/insts.sail`

- [ ] **Step 1: Add STI execute clause**

Add before `end execute` in `model/parser/insts.sail`:

```sail
// STI: Struct0[struct_off + size - 1 : struct_off] = ImmediateValue[size-1:0]
// Stores an immediate value (up to 16 bits) into Struct-0.
function clause execute(PSTI(immediate, struct_offset_bits, size_bits)) = {
    let doff : nat = unsigned(struct_offset_bits);
    let sz : nat = unsigned(size_bits);
    let imm_128 : bits128 = sail_zero_extend(immediate, 128);
    struct0 = insert_bits(struct0, doff, sz, imm_128);
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Build and run STI tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_st --verbose 2>&1 | tail -10`
Expected: Both STI tests pass.

- [ ] **Step 3: Commit**

```bash
git add model/parser/insts.sail test/parser/test_st.sail test/CMakeLists.txt
git commit -m "Add STI instruction with tests"
```

### Task 5: Write failing tests for ST

**Files:**
- Modify: `test/parser/test_st.sail`

- [ ] **Step 1: Add ST tests**

Add before `val main` in `test/parser/test_st.sail`:

```sail
// ST: basic — copy 8 bits from R0[7:0] to struct0[7:0].
val test_st_basic : unit -> unit
function test_st_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    let _ = execute(PST(PR0, 0x00, 0x00, 0x08, false));
    assert(struct0 == 0x00000000_00000000_00000000_000000AB, "ST should copy R0[7:0] to struct0[7:0]")
}

// ST: with non-zero source and struct offsets.
// R0[15:8] = 0xCD, copy to struct0[39:32].
val test_st_with_offsets : unit -> unit
function test_st_with_offsets() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000CD00;
    let _ = execute(PST(PR0, 0x08, 0x20, 0x08, false));
    assert(struct0 == 0x00000000_00000000_000000CD_00000000, "ST should copy R0[15:8] to struct0[39:32]")
}

// ST: with .H halt modifier.
val test_st_with_halt : unit -> unit
function test_st_with_halt() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    let result = execute(PST(PR0, 0x00, 0x00, 0x08, true));
    assert(result == RETIRE_HALT, "ST.H should return RETIRE_HALT");
    assert(parser_halted == true, "ST.H should set parser_halted");
    assert(struct0 == 0x00000000_00000000_00000000_000000AB, "ST.H should still store the value")
}

// ST: 16-bit copy.
val test_st_16bit : unit -> unit
function test_st_16bit() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00001234;
    let _ = execute(PST(PR0, 0x00, 0x00, 0x10, false));
    assert(struct0 == 0x00000000_00000000_00000000_00001234, "ST should copy 16 bits from R0 to struct0")
}
```

- [ ] **Step 2: Update main to call all tests**

Replace the `main` function in `test/parser/test_st.sail`:

```sail
val main : unit -> unit
function main() = {
    test_sti_basic();
    test_sti_at_offset();
    test_st_basic();
    test_st_with_offsets();
    test_st_with_halt();
    test_st_16bit()
}
```

- [ ] **Step 3: Build and verify ST tests fail**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_st --verbose 2>&1 | tail -10`
Expected: test_st fails — no execute clause for PST yet.

### Task 6: Implement ST execute clause

**Files:**
- Modify: `model/parser/insts.sail`

- [ ] **Step 1: Add ST execute clause**

Add before the STI clause in `model/parser/insts.sail`:

```sail
// ST: Struct0[struct_off + size - 1 : struct_off] = SrcReg[src_off + size - 1 : src_off]
// Copies a bit-field from a parser register into Struct-0.
// Optionally halt (.H modifier) after the store.
function clause execute(PST(rs, src_offset_bits, struct_offset_bits, size_bits, halt)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let doff : nat = unsigned(struct_offset_bits);
    let sz : nat = unsigned(size_bits);
    let extracted = extract_bits(src_val, soff, sz);
    struct0 = insert_bits(struct0, doff, sz, extracted);
    if halt then {
        parser_halted = true;
        RETIRE_HALT
    } else {
        RETIRE_SUCCESS
    }
}
```

- [ ] **Step 2: Build and run all ST/STI tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_st --verbose 2>&1 | tail -10`
Expected: All 6 tests pass.

- [ ] **Step 3: Commit**

```bash
git add model/parser/insts.sail test/parser/test_st.sail
git commit -m "Add ST instruction with tests"
```

### Task 7: Add program-level test

**Files:**
- Modify: `test/parser/test_st.sail`

- [ ] **Step 1: Add program-level test**

Add before `val main` in `test/parser/test_st.sail`:

```sail
// Program: Extract packet data, store into struct0.
// Packet: [0x45, 0x00, 0x00, 0x28, ...]  (IPv4 header)
// Step 1: EXT 8 bits at cursor=0 into R0 (version/IHL = 0x45)
// Step 2: ST R0[7:0] into struct0[39:32]  (store version byte at offset 32)
// Step 3: STI 0x0001 into struct0[7:0]    (store a flag)
// Step 4: HALT
val test_st_program : unit -> unit
function test_st_program() = {
    parser_init();
    packet_hdr[0] = 0x45;

    parser_load_program(
        [|
            PEXT(PR0, 0x00, 0x0000, 0x08, true),
            PST(PR0, 0x00, 0x20, 0x08, false),
            PSTI(0x0001, 0x00, 0x08),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[0] == 0x00000000_00000000_00000000_00000045, "R0 should have 0x45");
    // struct0 should have: version byte at [39:32] = 0x45, flag at [7:0] = 0x01
    assert(struct0 == 0x00000000_00000000_00000045_00000001, "struct0 should have version at [39:32] and flag at [7:0]")
}
```

- [ ] **Step 2: Update main to call program-level test**

Replace the `main` function:

```sail
val main : unit -> unit
function main() = {
    test_sti_basic();
    test_sti_at_offset();
    test_st_basic();
    test_st_with_offsets();
    test_st_with_halt();
    test_st_16bit();
    test_st_program()
}
```

- [ ] **Step 3: Build and run all tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_st --verbose 2>&1 | tail -10`
Expected: All 7 tests pass.

- [ ] **Step 4: Run the full test suite**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --verbose 2>&1 | tail -30`
Expected: All tests pass (no regressions).

- [ ] **Step 5: Commit**

```bash
git add test/parser/test_st.sail
git commit -m "Add program-level test for ST and STI with struct0"
```

### Task 8: Update coverage tracker

**Files:**
- Modify: `docs/coverage.md`

- [ ] **Step 1: Update ST and STI status**

In `docs/coverage.md`, change the rows:

From:
```
| 20 | ST | 3.12.10 | Not started | Requires Struct model |
| 21 | STI | 3.12.10 | Not started | |
```

To:
```
| 20 | ST | 3.12.10 | Done | .H supported. HW bits 6-31 restriction not enforced |
| 21 | STI | 3.12.10 | Done | |
```

- [ ] **Step 2: Commit**

```bash
git add docs/coverage.md
git commit -m "Update coverage for ST and STI instructions"
```
