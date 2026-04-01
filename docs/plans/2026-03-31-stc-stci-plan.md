# STC/STCI Cursor Instructions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add STC and STCI cursor manipulation instructions to the parser ISA model.

**Architecture:** Two new union clauses (PSTC, PSTCI) in types.sail, two execute clauses in insts.sail, one test file with unit tests and a program-level test. Follows the established pattern exactly.

**Tech Stack:** Sail, C backend, CMake/CTest

---

### Task 1: Add union clauses for STC and STCI

**Files:**
- Modify: `model/parser/types.sail:119` (before `end pinstr`)

- [ ] **Step 1: Add PSTC and PSTCI union clauses**

Add before the `end pinstr` line in `model/parser/types.sail`:

```sail
// STC: Set cursor from register sub-field.
// Cursor += ((SrcReg[offset+size-1:offset] + AdditionalIncr) << SrcShift)
// Fields: (src_reg, src_offset_bits, src_size_bits, src_shift, additional_incr)
union clause pinstr = PSTC : (pregidx, bits8, bits8, bits8, bits8)

// STCI: Set cursor from immediate value.
// Cursor += IncrValue
// Fields: (incr_value)
union clause pinstr = PSTCI : bits16
```

- [ ] **Step 2: Verify the model still compiles**

Run: `./dev.sh cmake --build build 2>&1 | tail -5`
Expected: Build succeeds (new clauses are unused but valid).

- [ ] **Step 3: Commit**

```bash
git add model/parser/types.sail
git commit -m "Add union clauses for STC and STCI cursor instructions"
```

### Task 2: Write failing tests for STCI

**Files:**
- Create: `test/parser/test_stc.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create test file with STCI tests**

Create `test/parser/test_stc.sail`:

```sail
// Tests for STC and STCI (cursor manipulation) instructions.

// STCI: increment cursor from 0.
val test_stci_basic : unit -> unit
function test_stci_basic() = {
    parser_init();
    pcursor = 0x00;
    let _ = execute(PSTCI(0x000E));
    assert(pcursor == 0x0E, "STCI should set cursor to 14")
}

// STCI: increment cursor from non-zero position.
val test_stci_from_nonzero : unit -> unit
function test_stci_from_nonzero() = {
    parser_init();
    pcursor = 0x0A;
    let _ = execute(PSTCI(0x0004));
    assert(pcursor == 0x0E, "STCI should increment cursor from 10 to 14")
}

val main : unit -> unit
function main() = {
    test_stci_basic();
    test_stci_from_nonzero()
}
```

- [ ] **Step 2: Register test in CMakeLists.txt**

Add to the end of `test/CMakeLists.txt`:

```cmake
add_sail_test(test_stc test/parser/test_stc.sail)
```

- [ ] **Step 3: Build and verify tests fail**

Run: `./dev.sh cmake --build build 2>&1 | tail -10`
Expected: Build fails — no execute clause for PSTCI yet.

### Task 3: Implement STCI execute clause

**Files:**
- Modify: `model/parser/insts.sail` (before `end execute`)

- [ ] **Step 1: Add STCI execute clause**

Add before the `end execute` line in `model/parser/insts.sail`:

```sail
// STCI: Cursor += IncrValue.
// Increments the parser cursor by an immediate value (1-256).
// Value is truncated to 8 bits to match cursor width.
function clause execute(PSTCI(incr_value)) = {
    let incr_8 : bits8 = sail_mask(8, incr_value);
    pcursor = pcursor + incr_8;
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Build and run STCI tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_stc --verbose 2>&1 | tail -20`
Expected: Both STCI tests pass.

- [ ] **Step 3: Commit**

```bash
git add model/parser/insts.sail test/parser/test_stc.sail test/CMakeLists.txt
git commit -m "Add STCI instruction with tests"
```

### Task 4: Write failing tests for STC

**Files:**
- Modify: `test/parser/test_stc.sail`

- [ ] **Step 1: Add STC tests**

Add the following test functions before `val main` in `test/parser/test_stc.sail`:

```sail
// STC: basic extraction, no shift, no additional increment.
// R0[7:0] = 0x0A, cursor += 10.
val test_stc_basic : unit -> unit
function test_stc_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    pcursor = 0x00;
    let _ = execute(PSTC(PR0, 0x00, 0x08, 0x00, 0x00));
    assert(pcursor == 0x0A, "STC should add extracted value to cursor")
}

// STC: left shift applied.
// R0[7:0] = 0x03, shift=2, cursor += (3 << 2) = 12.
val test_stc_with_shift : unit -> unit
function test_stc_with_shift() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;
    pcursor = 0x00;
    let _ = execute(PSTC(PR0, 0x00, 0x08, 0x02, 0x00));
    assert(pcursor == 0x0C, "STC with shift: cursor += (3 << 2) = 12")
}

// STC: additional increment, no shift.
// R0[7:0] = 0x03, additional_incr=2, cursor += (3 + 2) = 5.
val test_stc_with_additional_incr : unit -> unit
function test_stc_with_additional_incr() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;
    pcursor = 0x00;
    let _ = execute(PSTC(PR0, 0x00, 0x08, 0x00, 0x02));
    assert(pcursor == 0x05, "STC with additional_incr: cursor += (3 + 2) = 5")
}

// STC: both shift and additional increment.
// R0[7:0] = 0x02, additional_incr=1, shift=1, cursor += ((2 + 1) << 1) = 6.
val test_stc_with_shift_and_incr : unit -> unit
function test_stc_with_shift_and_incr() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000002;
    pcursor = 0x00;
    let _ = execute(PSTC(PR0, 0x00, 0x08, 0x01, 0x01));
    assert(pcursor == 0x06, "STC with shift and incr: cursor += ((2 + 1) << 1) = 6")
}

// STC: PRN reads as zero, only additional_incr and shift contribute.
// PRN[7:0] = 0, additional_incr=1, shift=2, cursor += ((0 + 1) << 2) = 4.
val test_stc_with_null_reg : unit -> unit
function test_stc_with_null_reg() = {
    parser_init();
    pcursor = 0x00;
    let _ = execute(PSTC(PRN, 0x00, 0x08, 0x02, 0x01));
    assert(pcursor == 0x04, "STC with PRN: cursor += ((0 + 1) << 2) = 4")
}
```

- [ ] **Step 2: Update main to call STC tests**

Replace the `main` function in `test/parser/test_stc.sail`:

```sail
val main : unit -> unit
function main() = {
    test_stci_basic();
    test_stci_from_nonzero();
    test_stc_basic();
    test_stc_with_shift();
    test_stc_with_additional_incr();
    test_stc_with_shift_and_incr();
    test_stc_with_null_reg()
}
```

- [ ] **Step 3: Build and verify STC tests fail**

Run: `./dev.sh cmake --build build 2>&1 | tail -10`
Expected: Build fails — no execute clause for PSTC yet.

### Task 5: Implement STC execute clause

**Files:**
- Modify: `model/parser/insts.sail`

- [ ] **Step 1: Add STC execute clause**

Add before the STCI clause in `model/parser/insts.sail`:

```sail
// STC: Cursor += ((SrcReg[offset+size-1:offset] + AdditionalIncr) << SrcShift)
// Extracts 1-8 bits from a register sub-field, adds AdditionalIncr,
// left-shifts by SrcShift, and adds the result to the cursor.
function clause execute(PSTC(rs, src_offset_bits, src_size_bits, src_shift, additional_incr)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let sz : nat = unsigned(src_size_bits);
    let extracted = extract_bits(src_val, soff, sz);
    let base : bits8 = sail_mask(8, extracted) + sail_mask(8, additional_incr);
    let shift_amount : nat = unsigned(src_shift);
    let shifted : bits8 = sail_shiftleft(base, shift_amount);
    pcursor = pcursor + shifted;
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Build and run all STC/STCI tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_stc --verbose 2>&1 | tail -20`
Expected: All 7 tests pass.

- [ ] **Step 3: Commit**

```bash
git add model/parser/insts.sail test/parser/test_stc.sail
git commit -m "Add STC instruction with tests"
```

### Task 6: Add program-level test

**Files:**
- Modify: `test/parser/test_stc.sail`

- [ ] **Step 1: Add program-level test**

Add before `val main` in `test/parser/test_stc.sail`:

```sail
// Program: EXT two bytes, STCI to advance cursor, EXT again at new position.
// Packet: [0xAA, 0xBB, 0xCC, 0xDD, ...]
// Step 1: EXT 8 bits at cursor=0 -> R0 = 0xAA
// Step 2: STCI(2) -> cursor = 2
// Step 3: EXT 8 bits at cursor=2 -> R1 = 0xCC
// Step 4: HALT
val test_stci_program : unit -> unit
function test_stci_program() = {
    parser_init();
    packet_hdr[0] = 0xAA;
    packet_hdr[1] = 0xBB;
    packet_hdr[2] = 0xCC;
    packet_hdr[3] = 0xDD;

    parser_load_program(
        [|
            PEXT(PR0, 0x00, 0x0000, 0x08, true),
            PSTCI(0x0002),
            PEXT(PR1, 0x00, 0x0000, 0x08, true),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[0] == 0x00000000_00000000_00000000_000000AA, "first EXT at cursor=0 should get 0xAA");
    assert(PR[1] == 0x00000000_00000000_00000000_000000CC, "second EXT at cursor=2 should get 0xCC");
    assert(pcursor == 0x02, "cursor should be at 2 after STCI")
}
```

- [ ] **Step 2: Update main to call program-level test**

Replace the `main` function:

```sail
val main : unit -> unit
function main() = {
    test_stci_basic();
    test_stci_from_nonzero();
    test_stc_basic();
    test_stc_with_shift();
    test_stc_with_additional_incr();
    test_stc_with_shift_and_incr();
    test_stc_with_null_reg();
    test_stci_program()
}
```

- [ ] **Step 3: Build and run all tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_stc --verbose 2>&1 | tail -20`
Expected: All 8 tests pass.

- [ ] **Step 4: Run the full test suite**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --verbose 2>&1 | tail -30`
Expected: All tests pass (no regressions).

- [ ] **Step 5: Commit**

```bash
git add test/parser/test_stc.sail
git commit -m "Add program-level test for STCI with cursor advancement"
```

### Task 7: Update coverage tracker

**Files:**
- Modify: `docs/coverage.md`

- [ ] **Step 1: Update STC and STCI status**

In `docs/coverage.md`, change the STC and STCI rows:

From:
```
| 16 | STC | 3.12.8 | Not started | |
| 17 | STCI | 3.12.8 | Not started | |
```

To:
```
| 16 | STC | 3.12.8 | Done | No JumpMode, .SCSM, .ECSM yet |
| 17 | STCI | 3.12.8 | Done | No JumpMode, .SCSM, .ECSM yet |
```

- [ ] **Step 2: Commit**

```bash
git add docs/coverage.md
git commit -m "Update coverage for STC and STCI instructions"
```
