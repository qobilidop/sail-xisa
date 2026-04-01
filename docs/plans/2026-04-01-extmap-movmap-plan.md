# EXTMAP, MOVMAP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add EXTMAP and MOVMAP parser instructions that write into MAP registers, including the MAP register file model.

**Architecture:** Create `model/map/state.sail` for the MAP register file (14 x 128-bit). Add union clauses and execute clauses to the existing parser types/insts files. EXTMAP reuses EXT's packet extraction logic targeting MAP registers. MOVMAP uses extract_bits/insert_bits between parser and MAP registers.

**Tech Stack:** Sail, CMake/CTest

---

### Task 1: Create MAP register file model

**Files:**
- Create: `model/map/state.sail`
- Modify: `model/main.sail` (add $include)
- Modify: `model/parser/state.sail` (add MAP init to parser_init)

- [ ] **Step 1: Create `model/map/state.sail`**

```sail

// MAP register file: 14 x 128-bit registers (R0-R13).
// See XISA spec section 4.2.
// The parser can write these via EXTMAP and MOVMAP instructions.
// After parsing, HW pre-loads R7.0 (SMD bytes 0-3), R11 (HDR.PRESENT),
// R12-R13 (HDR.OFFSET0/1) — that step is not modeled here.
register MAP : vector(14, bits128)

val init_map : unit -> vector(14, bits128)
function init_map() = [
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128),
]

// Read a MAP register by index (0-13).
val read_mapreg : int -> bits128
function read_mapreg(idx) = {
    assert(0 <= idx & idx < 14, "MAP register index out of bounds");
    MAP[idx]
}

// Write a MAP register by index (0-13).
val write_mapreg : (int, bits128) -> unit
function write_mapreg(idx, val) = {
    assert(0 <= idx & idx < 14, "MAP register index out of bounds");
    MAP[idx] = val
}
```

- [ ] **Step 2: Add `$include` in `model/main.sail`**

Add after the prelude line, before parser includes:

```sail
$include "prelude.sail"
$include "map/state.sail"
$include "parser/types.sail"
$include "parser/state.sail"
$include "parser/decode.sail"
$include "parser/insts.sail"
$include "parser/exec.sail"
```

- [ ] **Step 3: Add MAP init to `parser_init()` in `model/parser/state.sail`**

Add before the `// Reset instruction memory to all NOPs` comment:

```sail
    // Reset MAP registers
    MAP = init_map();

    // Reset instruction memory to all NOPs
    pimem = init_pimem()
```

- [ ] **Step 4: Build and type-check**

Run: `docker compose run --rm dev cmake --build build --target check`
Expected: PASS (no type errors)

- [ ] **Step 5: Run existing tests to confirm no regressions**

Run: `docker compose run --rm dev ctest --test-dir build`
Expected: all existing tests pass

- [ ] **Step 6: Commit**

```bash
git add model/map/state.sail model/main.sail model/parser/state.sail
git commit -m "Add MAP register file model (14 x 128-bit)"
```

---

### Task 2: Add EXTMAP and MOVMAP union clauses

**Files:**
- Modify: `model/parser/types.sail:149` (before `end pinstr`)

- [ ] **Step 1: Add union clauses to `model/parser/types.sail`**

Insert before the `end pinstr` line:

```sail
// EXTMAP: Extract data from packet into a MAP register.
// Fields: (map_reg_idx, dest_offset_bits, packet_offset_bits, size_bits)
union clause pinstr = PEXTMAP : (bits4, bits8, bits16, bits8)

// MOVMAP: Move data from a parser register into a MAP register.
// Fields: (map_reg_idx, dest_offset_bits, src_reg, src_offset_bits, size_bits)
union clause pinstr = PMOVMAP : (bits4, bits8, pregidx, bits8, bits8)
```

- [ ] **Step 2: Type-check**

Run: `docker compose run --rm dev cmake --build build --target check`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add model/parser/types.sail
git commit -m "Add union clauses for EXTMAP and MOVMAP instructions"
```

---

### Task 3: Write EXTMAP tests

**Files:**
- Create: `test/parser/test_extmap_movmap.sail`
- Modify: `test/CMakeLists.txt` (register test)

- [ ] **Step 1: Create `test/parser/test_extmap_movmap.sail` with EXTMAP tests**

```sail
// Tests for EXTMAP and MOVMAP (write to MAP registers) instructions.

// EXTMAP: extract 8 bits from packet byte 0 into MAP0[7:0].
val test_extmap_basic : unit -> unit
function test_extmap_basic() = {
    parser_init();
    packet_hdr[0] = 0xAB;
    let _ = execute(PEXTMAP(0x0, 0x00, 0x0000, 0x08));
    assert(read_mapreg(0) == 0x00000000_00000000_00000000_000000AB,
        "EXTMAP should extract 0xAB into MAP0[7:0]")
}

// EXTMAP: extract into MAP register at non-zero dest offset.
val test_extmap_dest_offset : unit -> unit
function test_extmap_dest_offset() = {
    parser_init();
    packet_hdr[0] = 0xAB;
    let _ = execute(PEXTMAP(0x0, 0x20, 0x0000, 0x08));
    assert(read_mapreg(0) == 0x00000000_00000000_000000AB_00000000,
        "EXTMAP should extract 0xAB into MAP0[39:32]")
}

// EXTMAP: extract from non-zero packet bit offset.
val test_extmap_packet_offset : unit -> unit
function test_extmap_packet_offset() = {
    parser_init();
    packet_hdr[0] = 0x00;
    packet_hdr[1] = 0x00;
    packet_hdr[2] = 0xCD;
    let _ = execute(PEXTMAP(0x0, 0x00, 0x0010, 0x08));
    assert(read_mapreg(0) == 0x00000000_00000000_00000000_000000CD,
        "EXTMAP should extract byte at packet bit offset 16")
}

// EXTMAP: extract 16 bits across two bytes into MAP1.
val test_extmap_16bit : unit -> unit
function test_extmap_16bit() = {
    parser_init();
    packet_hdr[0] = 0x12;
    packet_hdr[1] = 0x34;
    let _ = execute(PEXTMAP(0x1, 0x00, 0x0000, 0x10));
    assert(read_mapreg(1) == 0x00000000_00000000_00000000_00001234,
        "EXTMAP should extract 16 bits into MAP1[15:0]")
}
```

- [ ] **Step 2: Register test in `test/CMakeLists.txt`**

Add at the end:

```cmake
add_sail_test(test_extmap_movmap test/parser/test_extmap_movmap.sail)
```

- [ ] **Step 3: Type-check (test won't compile yet — execute clauses missing)**

Run: `docker compose run --rm dev cmake --build build --target check`
Expected: FAIL (no execute clause for PEXTMAP/PMOVMAP). This confirms the test references the correct union types.

Note: Sail requires exhaustive clause coverage for scattered functions, so the type-check will fail until execute clauses are added. This is expected TDD behavior for Sail.

---

### Task 4: Implement EXTMAP execute clause

**Files:**
- Modify: `model/parser/insts.sail:458` (before `end execute`)

- [ ] **Step 1: Add EXTMAP execute clause to `model/parser/insts.sail`**

Insert before the `end execute` line:

```sail
// EXTMAP: MAPReg[dest_off + size - 1 : dest_off] = Packet[cursor*8 + pkt_off + size - 1 : cursor*8 + pkt_off]
// Same extraction logic as EXT, but writes to a MAP register.
function clause execute(PEXTMAP(map_idx, dest_offset, pkt_offset_bits, size_bits)) = {
    let midx : int = unsigned(map_idx);
    let doff = unsigned(dest_offset);
    let soff = unsigned(pkt_offset_bits);
    let sz = unsigned(size_bits);
    let cursor_bit_offset = unsigned(pcursor) * 8;
    let packet_bit_offset = cursor_bit_offset + soff;

    // Compute byte index and bit-within-byte (same as EXT).
    let pbo_bv : bits(20) = get_slice_int(20, packet_bit_offset, 0);
    let start_byte = unsigned(sail_shiftright(pbo_bv, 3));
    let bit_in_byte = unsigned(pbo_bv & 0x00007);

    // bytes_needed = ceil((bit_in_byte + sz) / 8)
    let sum_bv : bits(20) = get_slice_int(20, bit_in_byte + sz + 7, 0);
    let bytes_needed = unsigned(sail_shiftright(sum_bv, 3));

    // Accumulate bytes into a 128-bit value (big-endian).
    var acc : bits128 = sail_zeros(128);
    var i : int = 0;
    while i < bytes_needed do {
        let byte_idx : int = start_byte + i;
        let byte_val : bits128 = sail_zero_extend(read_packet_byte(byte_idx), 128);
        acc = acc | sail_shiftleft(byte_val, 8 * (bytes_needed - 1 - i));
        i = i + 1
    };

    // Shift right to align the extracted bits, then mask to sz bits.
    let shift_amount : int = bytes_needed * 8 - bit_in_byte - sz;
    let extracted : bits128 = sail_shiftright(acc, shift_amount) & sail_mask(128, sail_ones(sz));

    // Write to MAP register
    let dst_val = read_mapreg(midx);
    let result = insert_bits(dst_val, doff, sz, extracted);
    write_mapreg(midx, result);
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Type-check**

Run: `docker compose run --rm dev cmake --build build --target check`
Expected: FAIL (PMOVMAP still has no execute clause)

---

### Task 5: Implement MOVMAP execute clause

**Files:**
- Modify: `model/parser/insts.sail` (before `end execute`, after EXTMAP)

- [ ] **Step 1: Add MOVMAP execute clause to `model/parser/insts.sail`**

Insert after the EXTMAP clause, before `end execute`:

```sail
// MOVMAP: MAPReg[dest_off + size - 1 : dest_off] = SrcReg[src_off + size - 1 : src_off]
// Copies a bit-field from a parser register into a MAP register.
function clause execute(PMOVMAP(map_idx, dest_offset, rs, src_offset, size_bits)) = {
    let midx : int = unsigned(map_idx);
    let doff : nat = unsigned(dest_offset);
    let soff : nat = unsigned(src_offset);
    let sz : nat = unsigned(size_bits);

    let src_val = read_preg(rs);
    let extracted = extract_bits(src_val, soff, sz);

    let dst_val = read_mapreg(midx);
    let result = insert_bits(dst_val, doff, sz, extracted);
    write_mapreg(midx, result);
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Type-check**

Run: `docker compose run --rm dev cmake --build build --target check`
Expected: PASS (all clauses now covered)

- [ ] **Step 3: Commit execute clauses**

```bash
git add model/parser/insts.sail
git commit -m "Add EXTMAP and MOVMAP execute clauses"
```

---

### Task 6: Add MOVMAP and program-level tests, run all tests

**Files:**
- Modify: `test/parser/test_extmap_movmap.sail` (add MOVMAP tests, program test, main)

- [ ] **Step 1: Add MOVMAP tests and program test to `test/parser/test_extmap_movmap.sail`**

Append after the EXTMAP tests:

```sail
// MOVMAP: move 8 bits from R0[7:0] to MAP0[7:0].
val test_movmap_basic : unit -> unit
function test_movmap_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000CD;
    let _ = execute(PMOVMAP(0x0, 0x00, PR0, 0x00, 0x08));
    assert(read_mapreg(0) == 0x00000000_00000000_00000000_000000CD,
        "MOVMAP should copy R0[7:0] to MAP0[7:0]")
}

// MOVMAP: move with non-zero source and dest offsets.
val test_movmap_offsets : unit -> unit
function test_movmap_offsets() = {
    parser_init();
    PR[1] = 0x00000000_00000000_00000000_0000EF00;
    let _ = execute(PMOVMAP(0x2, 0x10, PR1, 0x08, 0x08));
    assert(read_mapreg(2) == 0x00000000_00000000_00000000_00EF0000,
        "MOVMAP should copy R1[15:8] to MAP2[23:16]")
}

// MOVMAP: write to MAP register 13 (highest index).
val test_movmap_high_reg : unit -> unit
function test_movmap_high_reg() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000FF;
    let _ = execute(PMOVMAP(0xD, 0x00, PR0, 0x00, 0x08));
    assert(read_mapreg(13) == 0x00000000_00000000_00000000_000000FF,
        "MOVMAP should write to MAP register 13")
}

// Program: EXT packet data into R0, MOVMAP from R0 into MAP0,
// EXTMAP packet data directly into MAP1, verify both.
// Packet: [0x45, 0x00, 0x00, 0x28]
val test_extmap_movmap_program : unit -> unit
function test_extmap_movmap_program() = {
    parser_init();
    packet_hdr[0] = 0x45;
    packet_hdr[1] = 0x00;
    packet_hdr[2] = 0x00;
    packet_hdr[3] = 0x28;

    parser_load_program(
        [|
            PEXT(PR0, 0x00, 0x0000, 0x08, true),
            PMOVMAP(0x0, 0x00, PR0, 0x00, 0x08),
            PEXTMAP(0x1, 0x00, 0x0018, 0x08),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[0] == 0x00000000_00000000_00000000_00000045, "R0 should have 0x45");
    assert(read_mapreg(0) == 0x00000000_00000000_00000000_00000045,
        "MAP0 should have 0x45 from MOVMAP");
    assert(read_mapreg(1) == 0x00000000_00000000_00000000_00000028,
        "MAP1 should have 0x28 from EXTMAP")
}

val main : unit -> unit
function main() = {
    test_extmap_basic();
    test_extmap_dest_offset();
    test_extmap_packet_offset();
    test_extmap_16bit();
    test_movmap_basic();
    test_movmap_offsets();
    test_movmap_high_reg();
    test_extmap_movmap_program()
}
```

- [ ] **Step 2: Build and run new test**

Run: `docker compose run --rm dev bash -c "cmake --build build && ctest --test-dir build -R test_extmap_movmap -V"`
Expected: PASS — all 8 tests execute successfully

- [ ] **Step 3: Run full test suite for regressions**

Run: `docker compose run --rm dev ctest --test-dir build`
Expected: all tests pass

- [ ] **Step 4: Commit tests**

```bash
git add test/parser/test_extmap_movmap.sail test/CMakeLists.txt
git commit -m "Add tests for EXTMAP and MOVMAP instructions"
```

---

### Task 7: Update coverage

**Files:**
- Modify: `docs/coverage.md`

- [ ] **Step 1: Update `docs/coverage.md`**

Change lines 19-20 from:

```markdown
| 11 | EXTMAP | 3.12.4 | Not started | Requires MAP register model |
| 12 | MOVMAP | 3.12.5 | Not started | Requires MAP register model |
```

to:

```markdown
| 11 | EXTMAP | 3.12.4 | Done | No .PR, .SCSM, .ECSM yet |
| 12 | MOVMAP | 3.12.5 | Done | No .HDR modifier yet |
```

- [ ] **Step 2: Commit**

```bash
git add docs/coverage.md
git commit -m "Update coverage for EXTMAP and MOVMAP instructions"
```
