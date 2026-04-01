# HDR Model + STH/STCH/STHC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the HDR register model and STH/STCH/STHC header metadata instructions to the parser ISA model.

**Architecture:** New HDR state (two 32-entry arrays) in state.sail, a `set_hdr` helper, three new union clauses in types.sail, three execute clauses in insts.sail, one test file. Follows established patterns.

**Tech Stack:** Sail, C backend, CMake/CTest

---

### Task 1: Add HDR state and helper to state.sail

**Files:**
- Modify: `model/parser/state.sail`

- [ ] **Step 1: Add HDR registers after the existing parser state registers**

Add after `register parser_drop : bool` (line 16) in `model/parser/state.sail`:

```sail
// Header present flags: 32 entries, indexed by header ID.
// Assumption: 32 entries is a reasonable default; the white paper does not
// specify the exact count. Adjust when more information is available.
register hdr_present : vector(32, bool)

// Header offset values: 32 entries, indexed by header offset ID.
// Records the cursor position (byte offset) when a header was identified.
register hdr_offset : vector(32, bits8)
```

- [ ] **Step 2: Initialize HDR arrays in parser_init()**

In `model/parser/state.sail`, add HDR initialization inside `parser_init()`, after the `pflag_n = false;` line and before the `// Reset instruction memory to all NOPs` comment:

```sail
    // Reset header metadata
    var i : int = 0;
    while i < 32 do {
        hdr_present[i] = false;
        hdr_offset[i] = sail_zeros(8);
        i = i + 1
    };
```

- [ ] **Step 3: Add set_hdr helper function**

Add after the `write_preg` function (after line 317) in `model/parser/state.sail`:

```sail
// Set header present flag and offset for the given IDs.
// Uses the current cursor position as the offset value.
val set_hdr : (bits8, bits8) -> unit
function set_hdr(present_id, offset_id) = {
    let pid : int = unsigned(present_id);
    let oid : int = unsigned(offset_id);
    assert(0 <= pid & pid < 32, "header present ID out of bounds");
    assert(0 <= oid & oid < 32, "header offset ID out of bounds");
    hdr_present[pid] = true;
    hdr_offset[oid] = pcursor
}
```

- [ ] **Step 4: Verify the model compiles**

Run: `./dev.sh cmake --build build 2>&1 | tail -5`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add model/parser/state.sail
git commit -m "Add HDR register model with present/offset arrays and set_hdr helper"
```

### Task 2: Add union clauses for STH, STCH, STHC

**Files:**
- Modify: `model/parser/types.sail`

- [ ] **Step 1: Add union clauses before `end pinstr`**

Add before `end pinstr` in `model/parser/types.sail`:

```sail
// STH: Set header present and offset fields at current cursor position.
// Fields: (header_present_id, header_offset_id, halt)
union clause pinstr = PSTH : (bits8, bits8, bool)

// STCH: Set cursor then header fields (STCI + STH compound).
// Fields: (incr_value, header_present_id, header_offset_id, halt)
union clause pinstr = PSTCH : (bits16, bits8, bits8, bool)

// STHC: Set header fields then cursor (STH + STCI compound).
// Fields: (incr_value, header_present_id, header_offset_id)
union clause pinstr = PSTHC : (bits16, bits8, bits8)
```

- [ ] **Step 2: Verify the model compiles**

Run: `./dev.sh cmake --build build 2>&1 | tail -5`
Expected: Build succeeds (new clauses unused but valid).

- [ ] **Step 3: Commit**

```bash
git add model/parser/types.sail
git commit -m "Add union clauses for STH, STCH, and STHC instructions"
```

### Task 3: Write failing tests for STH

**Files:**
- Create: `test/parser/test_sth.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create test file with STH tests**

Create `test/parser/test_sth.sail`:

```sail
// Tests for STH, STCH, and STHC (header metadata) instructions.

// STH: basic — sets present and offset at current cursor.
val test_sth_basic : unit -> unit
function test_sth_basic() = {
    parser_init();
    pcursor = 0x0E;
    let _ = execute(PSTH(0x00, 0x00, false));
    assert(hdr_present[0] == true, "STH should set hdr_present[0]");
    assert(hdr_offset[0] == 0x0E, "STH should set hdr_offset[0] to cursor position")
}

// STH: with halt modifier.
val test_sth_with_halt : unit -> unit
function test_sth_with_halt() = {
    parser_init();
    pcursor = 0x0E;
    let result = execute(PSTH(0x00, 0x00, true));
    assert(result == RETIRE_HALT, "STH.H should return RETIRE_HALT");
    assert(parser_halted == true, "STH.H should set parser_halted");
    assert(hdr_present[0] == true, "STH.H should still set header present");
    assert(hdr_offset[0] == 0x0E, "STH.H should still set header offset")
}

// STH: different present and offset IDs.
val test_sth_different_ids : unit -> unit
function test_sth_different_ids() = {
    parser_init();
    pcursor = 0x0A;
    let _ = execute(PSTH(0x01, 0x02, false));
    assert(hdr_present[0] == false, "hdr_present[0] should be unchanged");
    assert(hdr_present[1] == true, "STH should set hdr_present[1]");
    assert(hdr_offset[0] == 0x00, "hdr_offset[0] should be unchanged");
    assert(hdr_offset[2] == 0x0A, "STH should set hdr_offset[2] to cursor position")
}

val main : unit -> unit
function main() = {
    test_sth_basic();
    test_sth_with_halt();
    test_sth_different_ids()
}
```

- [ ] **Step 2: Register test in CMakeLists.txt**

Add to the end of `test/CMakeLists.txt`:

```cmake
add_sail_test(test_sth test/parser/test_sth.sail)
```

- [ ] **Step 3: Build and verify tests fail**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_sth --verbose 2>&1 | tail -10`
Expected: test_sth fails with "Pattern match failure in execute".

### Task 4: Implement STH execute clause

**Files:**
- Modify: `model/parser/insts.sail`

- [ ] **Step 1: Add STH execute clause**

Add before `end execute` in `model/parser/insts.sail`:

```sail
// STH: Set header present and offset fields.
// Optionally halt (.H modifier) after setting the header.
function clause execute(PSTH(present_id, offset_id, halt)) = {
    set_hdr(present_id, offset_id);
    if halt then {
        parser_halted = true;
        RETIRE_HALT
    } else {
        RETIRE_SUCCESS
    }
}
```

- [ ] **Step 2: Build and run STH tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_sth --verbose 2>&1 | tail -10`
Expected: All 3 STH tests pass.

- [ ] **Step 3: Commit**

```bash
git add model/parser/insts.sail test/parser/test_sth.sail test/CMakeLists.txt
git commit -m "Add STH instruction with tests"
```

### Task 5: Write failing tests for STCH and STHC

**Files:**
- Modify: `test/parser/test_sth.sail`

- [ ] **Step 1: Add STCH and STHC tests**

Add before `val main` in `test/parser/test_sth.sail`:

```sail
// STCH: increment cursor then set header (offset = new cursor).
val test_stch_basic : unit -> unit
function test_stch_basic() = {
    parser_init();
    pcursor = 0x00;
    let _ = execute(PSTCH(0x000E, 0x00, 0x00, false));
    assert(pcursor == 0x0E, "STCH should increment cursor to 14");
    assert(hdr_present[0] == true, "STCH should set hdr_present[0]");
    assert(hdr_offset[0] == 0x0E, "STCH should set hdr_offset[0] to NEW cursor position")
}

// STCH: with halt modifier.
val test_stch_with_halt : unit -> unit
function test_stch_with_halt() = {
    parser_init();
    pcursor = 0x00;
    let result = execute(PSTCH(0x000E, 0x00, 0x00, true));
    assert(result == RETIRE_HALT, "STCH.H should return RETIRE_HALT");
    assert(parser_halted == true, "STCH.H should set parser_halted");
    assert(pcursor == 0x0E, "STCH.H should still increment cursor");
    assert(hdr_offset[0] == 0x0E, "STCH.H should still set header offset")
}

// STHC: set header at current cursor then increment (offset = old cursor).
val test_sthc_basic : unit -> unit
function test_sthc_basic() = {
    parser_init();
    pcursor = 0x00;
    let _ = execute(PSTHC(0x000E, 0x00, 0x00));
    assert(pcursor == 0x0E, "STHC should increment cursor to 14");
    assert(hdr_present[0] == true, "STHC should set hdr_present[0]");
    assert(hdr_offset[0] == 0x00, "STHC should set hdr_offset[0] to OLD cursor position")
}

// STCH vs STHC: same parameters, different offset recorded.
val test_stch_vs_sthc_ordering : unit -> unit
function test_stch_vs_sthc_ordering() = {
    // STCH: cursor advances first, header records NEW position
    parser_init();
    pcursor = 0x04;
    let _ = execute(PSTCH(0x000A, 0x00, 0x00, false));
    let stch_offset = hdr_offset[0];
    assert(stch_offset == 0x0E, "STCH should record offset=14 (4+10, new cursor)");

    // STHC: header records CURRENT position, then cursor advances
    parser_init();
    pcursor = 0x04;
    let _ = execute(PSTHC(0x000A, 0x01, 0x01));
    let sthc_offset = hdr_offset[1];
    assert(sthc_offset == 0x04, "STHC should record offset=4 (old cursor)")
}
```

- [ ] **Step 2: Update main to call all tests**

Replace the `main` function in `test/parser/test_sth.sail`:

```sail
val main : unit -> unit
function main() = {
    test_sth_basic();
    test_sth_with_halt();
    test_sth_different_ids();
    test_stch_basic();
    test_stch_with_halt();
    test_sthc_basic();
    test_stch_vs_sthc_ordering()
}
```

- [ ] **Step 3: Build and verify STCH/STHC tests fail**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_sth --verbose 2>&1 | tail -10`
Expected: test_sth fails — no execute clause for PSTCH/PSTHC yet.

### Task 6: Implement STCH and STHC execute clauses

**Files:**
- Modify: `model/parser/insts.sail`

- [ ] **Step 1: Add STCH and STHC execute clauses**

Add after the STH clause and before `end execute` in `model/parser/insts.sail`:

```sail
// STCH: Increment cursor, then set header (STCI + STH compound).
// The header offset records the NEW cursor position (after increment).
function clause execute(PSTCH(incr_value, present_id, offset_id, halt)) = {
    let incr_8 : bits8 = sail_mask(8, incr_value);
    pcursor = pcursor + incr_8;
    set_hdr(present_id, offset_id);
    if halt then {
        parser_halted = true;
        RETIRE_HALT
    } else {
        RETIRE_SUCCESS
    }
}

// STHC: Set header at current cursor, then increment cursor (STH + STCI compound).
// The header offset records the OLD cursor position (before increment).
function clause execute(PSTHC(incr_value, present_id, offset_id)) = {
    set_hdr(present_id, offset_id);
    let incr_8 : bits8 = sail_mask(8, incr_value);
    pcursor = pcursor + incr_8;
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Build and run all STH/STCH/STHC tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_sth --verbose 2>&1 | tail -10`
Expected: All 7 tests pass.

- [ ] **Step 3: Commit**

```bash
git add model/parser/insts.sail test/parser/test_sth.sail
git commit -m "Add STCH and STHC instructions with tests"
```

### Task 7: Add program-level test

**Files:**
- Modify: `test/parser/test_sth.sail`

- [ ] **Step 1: Add program-level test**

Add before `val main` in `test/parser/test_sth.sail`:

```sail
// Program: Parse two protocol headers from a packet.
// Packet: [Eth header 14 bytes] [IPv4 header 20 bytes] [payload...]
//
// Step 1: STHC(14, 0, 0) — record Ethernet at offset 0, advance cursor to 14
// Step 2: EXT 8 bits at cursor=14 into R0 (first byte of IPv4)
// Step 3: STHC(20, 1, 1) — record IPv4 at offset 14, advance cursor to 34
// Step 4: HALT
val test_parse_two_headers : unit -> unit
function test_parse_two_headers() = {
    parser_init();

    // Fill packet: Ethernet (14 bytes) + IPv4 (starts with version/IHL = 0x45)
    packet_hdr[14] = 0x45;

    parser_load_program(
        [|
            PSTHC(0x000E, 0x00, 0x00),
            PEXT(PR0, 0x00, 0x0000, 0x08, true),
            PSTHC(0x0014, 0x01, 0x01),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    // Ethernet header recorded at offset 0
    assert(hdr_present[0] == true, "Ethernet header should be present");
    assert(hdr_offset[0] == 0x00, "Ethernet header offset should be 0");
    // IPv4 header recorded at offset 14
    assert(hdr_present[1] == true, "IPv4 header should be present");
    assert(hdr_offset[1] == 0x0E, "IPv4 header offset should be 14");
    // Cursor should be at 34 (14 + 20)
    assert(pcursor == 0x22, "cursor should be at 34 after both headers");
    // R0 should have first byte of IPv4 header
    assert(PR[0] == 0x00000000_00000000_00000000_00000045, "R0 should have IPv4 version/IHL byte")
}
```

- [ ] **Step 2: Update main to call program-level test**

Replace the `main` function:

```sail
val main : unit -> unit
function main() = {
    test_sth_basic();
    test_sth_with_halt();
    test_sth_different_ids();
    test_stch_basic();
    test_stch_with_halt();
    test_sthc_basic();
    test_stch_vs_sthc_ordering();
    test_parse_two_headers()
}
```

- [ ] **Step 3: Build and run all tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_sth --verbose 2>&1 | tail -10`
Expected: All 8 tests pass.

- [ ] **Step 4: Run the full test suite**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --verbose 2>&1 | tail -30`
Expected: All tests pass (no regressions).

- [ ] **Step 5: Commit**

```bash
git add test/parser/test_sth.sail
git commit -m "Add program-level test for parsing two protocol headers"
```

### Task 8: Update coverage tracker

**Files:**
- Modify: `docs/coverage.md`

- [ ] **Step 1: Update STH, STCH, and STHC status**

In `docs/coverage.md`, change the rows:

From:
```
| 15 | STH | 3.12.7 | Not started | Requires HDR model |
| 18 | STCH | 3.12.9 | Not started | |
| 19 | STHC | 3.12.9 | Not started | |
```

To:
```
| 15 | STH | 3.12.7 | Done | .H supported. No JumpMode, .SCSM, .ECSM yet |
| 18 | STCH | 3.12.9 | Done | .H supported. No JumpMode, .SCSM, .ECSM yet |
| 19 | STHC | 3.12.9 | Done | No JumpMode, .SCSM, .ECSM yet |
```

- [ ] **Step 2: Commit**

```bash
git add docs/coverage.md
git commit -m "Update coverage for STH, STCH, and STHC instructions"
```
