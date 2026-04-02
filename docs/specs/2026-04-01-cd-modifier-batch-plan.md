# .CD Modifier Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `.CD` (clear destination) modifier to all 13 remaining parser instructions that write to a destination register.

**Architecture:** Each instruction gets a `bool` field appended to its union clause, a 1-bit `encdec_bool(cd)` in its encoding (consuming one padding bit), and a conditional in its execute clause: `if clear_dest then sail_zeros(128) else read_preg(rd)`. This is identical to the existing `.CD` support on EXT, EXTNXTP, and MOVL/MOVR variants.

**Tech Stack:** Sail language, CTest

---

## File Map

| File | Change |
|------|--------|
| `model/parser/types.sail` | Add `bool` to 13 union clauses |
| `model/parser/decode.sail` | Add `encdec_bool(cd)` to 13 encodings, adjust padding |
| `model/parser/insts.sail` | Add `clear_dest` param + conditional to 13 execute clauses |
| `test/parser/test_mov.sail` | Update 6 call sites, add 2 `.CD` tests |
| `test/parser/test_add.sail` | Update 6 call sites, add 2 `.CD` tests |
| `test/parser/test_sub.sail` | Update 6 call sites, add 2 `.CD` tests |
| `test/parser/test_and.sail` | Update 4 call sites, add 2 `.CD` tests |
| `test/parser/test_or.sail` | Update 3 call sites, add 2 `.CD` tests |
| `test/parser/test_cnct.sail` | Update 3 call sites, add 2 `.CD` tests |
| `test/parser/test_integration.sail` | Update 16 call sites |
| `test/parser/test_program.sail` | Update 11 call sites |
| `test/parser/test_encoding.sail` | Update 1 call site (CNCTBY) |
| `docs/spec-coverage.md` | Remove `.CD` notes from 8 rows |
| `docs/todo.md` | Update `.CD` entry |

## Shared Pattern

Every instruction follows the same 3-change pattern across the model files. The pattern shown here once; tasks reference it.

**types.sail** — append `, bool` to the union tuple:
```sail
// Before:
union clause pinstr = PMOV : (pregidx, bits8, pregidx, bits8, bits8)
// After:
union clause pinstr = PMOV : (pregidx, bits8, pregidx, bits8, bits8, bool)
```

**decode.sail** — append `encdec_bool(cd)`, reduce padding by 1 bit:
```sail
// Before (30 field bits, 28 padding):
mapping clause encdec = PMOV(rd, doff, rs, soff, sz)
    <-> 0b010010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs) @ soff @ sz @ 0x0000000 : bits(28)
// After (31 field bits, 27 padding):
mapping clause encdec = PMOV(rd, doff, rs, soff, sz, cd)
    <-> 0b010010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs) @ soff @ sz @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x000000 : bits(24)
```

**insts.sail** — add `clear_dest` param, change `read_preg(rd)` to conditional:
```sail
// Before:
function clause execute(PMOV(rd, dest_offset, rs, src_offset, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
    ...
// After:
function clause execute(PMOV(rd, dest_offset, rs, src_offset, size_bits, clear_dest)) = {
    let src_val = read_preg(rs);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    ...
```

**Test call sites** — append `, false` to preserve existing behavior:
```sail
// Before:
let _ = execute(PMOV(PR1, 0x00, PR0, 0x00, 0x80));
// After:
let _ = execute(PMOV(PR1, 0x00, PR0, 0x00, 0x80, false));
```

---

### Task 1: MOV / MOVI — model changes + tests

**Files:**
- Modify: `model/parser/types.sail:41-47`
- Modify: `model/parser/decode.sail:114-120`
- Modify: `model/parser/insts.sail:50-74`
- Modify: `test/parser/test_mov.sail`

- [ ] **Step 1: Update types.sail — add `bool` to PMOV and PMOVI**

```sail
// MOV: Copy SizeBits bits from SourceReg at SrcOffset to DestReg at DestOffset.
// Fields: (dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits, clear_dest)
union clause pinstr = PMOV : (pregidx, bits8, pregidx, bits8, bits8, bool)

// MOVI: Load immediate value into DestReg.
// Fields: (dest_reg, dest_offset_bytes, immediate_value, size_bits, clear_dest)
union clause pinstr = PMOVI : (pregidx, bits8, bits16, bits8, bool)
```

- [ ] **Step 2: Update decode.sail — add `encdec_bool(cd)` to PMOV and PMOVI**

```sail
// Opcode 18: MOV (3+8+3+8+8+1 = 31 field bits, 27 padding)
mapping clause encdec = PMOV(rd, doff, rs, soff, sz, cd)
    <-> 0b010010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs) @ soff @ sz @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x000000 : bits(24)

// Opcode 19: MOVI (3+8+16+8+1 = 36 field bits, 22 padding)
mapping clause encdec = PMOVI(rd, doff, imm, sz, cd)
    <-> 0b010011 @ encdec_pregidx(rd) @ doff @ imm @ sz @ encdec_bool(cd) @ 0b00 : bits(2) @ 0x00000 : bits(20)
```

- [ ] **Step 3: Update insts.sail — add `clear_dest` to PMOV and PMOVI execute clauses**

For PMOV:
```sail
function clause execute(PMOV(rd, dest_offset, rs, src_offset, size_bits, clear_dest)) = {
    let src_val = read_preg(rs);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    ...
```

For PMOVI:
```sail
function clause execute(PMOVI(rd, dest_offset_bytes, immediate, size_bits, clear_dest)) = {
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    ...
```

- [ ] **Step 4: Update test_mov.sail — add `, false` to all 6 existing call sites**

Lines 23, 39, 50, 66: append `, false` to PMOV calls.
Lines 78, 90: append `, false` to PMOVI calls.

- [ ] **Step 5: Add .CD tests to test_mov.sail**

Add before the `main` function:

```sail
val test_mov_with_clear_dest : unit -> unit
function test_mov_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PMOV(PR1, 0x00, PR0, 0x00, 0x08, true));
    assert(PR[1] == 0x00000000_00000000_00000000_000000AB,
        "MOV.CD should clear dest then place copied bits")
}

val test_movi_with_clear_dest : unit -> unit
function test_movi_with_clear_dest() = {
    parser_init();
    PR[0] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PMOVI(PR0, 0x00, 0xABCD, 0x10, true));
    assert(PR[0] == 0x00000000_00000000_00000000_0000ABCD,
        "MOVI.CD should clear dest then place immediate")
}
```

Add calls `test_mov_with_clear_dest()` and `test_movi_with_clear_dest()` to `main`.

- [ ] **Step 6: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_mov --output-on-failure`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add model/parser/types.sail model/parser/decode.sail model/parser/insts.sail test/parser/test_mov.sail
git commit -m "Add .CD modifier to MOV and MOVI instructions"
```

---

### Task 2: ADD / ADDI — model changes + tests

**Files:**
- Modify: `model/parser/types.sail:55-61`
- Modify: `model/parser/decode.sail:146-152`
- Modify: `model/parser/insts.sail:125-157`
- Modify: `test/parser/test_add.sail`

- [ ] **Step 1: Update types.sail — add `bool` to PADD and PADDI**

```sail
// ADD: Unsigned addition of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits, clear_dest)
union clause pinstr = PADD : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8, bool)

// ADDI: Unsigned addition of register sub-field and immediate.
// Fields: (dest_reg, src_reg, immediate_value, size_bits, clear_dest)
union clause pinstr = PADDI : (pregidx, pregidx, bits16, bits8, bool)
```

- [ ] **Step 2: Update decode.sail — add `encdec_bool(cd)` to PADD and PADDI**

PADD currently has 41 field bits with `0b0 : bits(1) @ 0x0000 : bits(16)` padding (17 bits). The `0b0 : bits(1)` becomes `encdec_bool(cd)`:

```sail
// Opcode 26: ADD (3+8+3+8+3+8+8+1 = 42 field bits, 16 padding)
mapping clause encdec = PADD(rd, doff, rs1, s1off, rs2, s2off, sz, cd)
    <-> 0b011010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ encdec_bool(cd) @ 0x0000 : bits(16)

// Opcode 27: ADDI (3+3+16+8+1 = 31 field bits, 27 padding)
mapping clause encdec = PADDI(rd, rs, imm, sz, cd)
    <-> 0b011011 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x000000 : bits(24)
```

- [ ] **Step 3: Update insts.sail — add `clear_dest` to PADD and PADDI execute clauses**

For PADD:
```sail
function clause execute(PADD(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits, clear_dest)) = {
    ...
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    ...
```

For PADDI:
```sail
function clause execute(PADDI(rd, rs, immediate, size_bits, clear_dest)) = {
    ...
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    ...
```

- [ ] **Step 4: Update test_add.sail — add `, false` to all 6 existing call sites**

Lines 9, 21, 32, 43: append `, false` to PADD calls.
Lines 54, 65: append `, false` to PADDI calls.

- [ ] **Step 5: Add .CD tests to test_add.sail**

```sail
val test_add_with_clear_dest : unit -> unit
function test_add_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_00000014;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, true));
    assert(PR[2] == 0x00000000_00000000_00000000_0000001E,
        "ADD.CD should clear dest then place sum")
}

val test_addi_with_clear_dest : unit -> unit
function test_addi_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PADDI(PR1, PR0, 0x0005, 0x08, true));
    assert(PR[1] == 0x00000000_00000000_00000000_0000000F,
        "ADDI.CD should clear dest then place sum")
}
```

Add calls to `main`.

- [ ] **Step 6: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_add --output-on-failure`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add model/parser/types.sail model/parser/decode.sail model/parser/insts.sail test/parser/test_add.sail
git commit -m "Add .CD modifier to ADD and ADDI instructions"
```

---

### Task 3: SUB / SUBI / SUBII — model changes + tests

**Files:**
- Modify: `model/parser/types.sail:63-73`
- Modify: `model/parser/decode.sail:154-164`
- Modify: `model/parser/insts.sail:159-207`
- Modify: `test/parser/test_sub.sail`

- [ ] **Step 1: Update types.sail — add `bool` to PSUB, PSUBI, PSUBII**

```sail
// SUB: Subtraction of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits, clear_dest)
union clause pinstr = PSUB : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8, bool)

// SUBI: Subtraction of immediate from register sub-field.
// Fields: (dest_reg, src_reg, immediate_value, size_bits, clear_dest)
union clause pinstr = PSUBI : (pregidx, pregidx, bits16, bits8, bool)

// SUBII: Subtraction of register sub-field from immediate (reversed).
// Fields: (dest_reg, immediate_value, src_reg, size_bits, clear_dest)
union clause pinstr = PSUBII : (pregidx, bits16, pregidx, bits8, bool)
```

- [ ] **Step 2: Update decode.sail — add `encdec_bool(cd)` to PSUB, PSUBI, PSUBII**

```sail
// Opcode 28: SUB (3+8+3+8+3+8+8+1 = 42 field bits, 16 padding)
mapping clause encdec = PSUB(rd, doff, rs1, s1off, rs2, s2off, sz, cd)
    <-> 0b011100 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ encdec_bool(cd) @ 0x0000 : bits(16)

// Opcode 29: SUBI (3+3+16+8+1 = 31 field bits, 27 padding)
mapping clause encdec = PSUBI(rd, rs, imm, sz, cd)
    <-> 0b011101 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x000000 : bits(24)

// Opcode 30: SUBII (3+16+3+8+1 = 31 field bits, 27 padding)
mapping clause encdec = PSUBII(rd, imm, rs, sz, cd)
    <-> 0b011110 @ encdec_pregidx(rd) @ imm @ encdec_pregidx(rs) @ sz @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x000000 : bits(24)
```

- [ ] **Step 3: Update insts.sail — add `clear_dest` to PSUB, PSUBI, PSUBII**

Same pattern: change signature, replace `read_preg(rd)` with conditional.

- [ ] **Step 4: Update test_sub.sail — add `, false` to all 6 existing call sites**

Lines 9, 22, 34: PSUB. Lines 46: PSUBI. Lines 58, 69: PSUBII.

- [ ] **Step 5: Add .CD tests to test_sub.sail**

```sail
val test_sub_with_clear_dest : unit -> unit
function test_sub_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000014;
    PR[1] = 0x00000000_00000000_00000000_0000000A;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PSUB(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, true));
    assert(PR[2] == 0x00000000_00000000_00000000_0000000A,
        "SUB.CD should clear dest then place difference")
}

val test_subi_with_clear_dest : unit -> unit
function test_subi_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000014;
    PR[1] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PSUBI(PR1, PR0, 0x000A, 0x08, true));
    assert(PR[1] == 0x00000000_00000000_00000000_0000000A,
        "SUBI.CD should clear dest then place difference")
}
```

Add calls to `main`.

- [ ] **Step 6: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_sub --output-on-failure`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add model/parser/types.sail model/parser/decode.sail model/parser/insts.sail test/parser/test_sub.sail
git commit -m "Add .CD modifier to SUB, SUBI, and SUBII instructions"
```

---

### Task 4: AND / ANDI — model changes + tests

**Files:**
- Modify: `model/parser/types.sail:75-81`
- Modify: `model/parser/decode.sail:166-172`
- Modify: `model/parser/insts.sail:209-240`
- Modify: `test/parser/test_and.sail`

- [ ] **Step 1: Update types.sail — add `bool` to PAND and PANDI**

```sail
// AND: Bitwise AND of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits, clear_dest)
union clause pinstr = PAND : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8, bool)

// ANDI: Bitwise AND of register sub-field and immediate.
// Fields: (dest_reg, src_reg, immediate_value, size_bits, clear_dest)
union clause pinstr = PANDI : (pregidx, pregidx, bits16, bits8, bool)
```

- [ ] **Step 2: Update decode.sail — add `encdec_bool(cd)` to PAND and PANDI**

```sail
// Opcode 31: AND (3+8+3+8+3+8+8+1 = 42 field bits, 16 padding)
mapping clause encdec = PAND(rd, doff, rs1, s1off, rs2, s2off, sz, cd)
    <-> 0b011111 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ encdec_bool(cd) @ 0x0000 : bits(16)

// Opcode 32: ANDI (3+3+16+8+1 = 31 field bits, 27 padding)
mapping clause encdec = PANDI(rd, rs, imm, sz, cd)
    <-> 0b100000 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x000000 : bits(24)
```

- [ ] **Step 3: Update insts.sail — add `clear_dest` to PAND and PANDI**

Same pattern.

- [ ] **Step 4: Update test_and.sail — add `, false` to all 4 existing call sites**

Lines 9, 21: PAND. Lines 32, 43: PANDI.

- [ ] **Step 5: Add .CD tests to test_and.sail**

```sail
val test_and_with_clear_dest : unit -> unit
function test_and_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000FF;
    PR[1] = 0x00000000_00000000_00000000_0000000F;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PAND(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, true));
    assert(PR[2] == 0x00000000_00000000_00000000_0000000F,
        "AND.CD should clear dest then place AND result")
}

val test_andi_with_clear_dest : unit -> unit
function test_andi_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PANDI(PR1, PR0, 0x000F, 0x08, true));
    assert(PR[1] == 0x00000000_00000000_00000000_0000000B,
        "ANDI.CD should clear dest then place AND result")
}
```

Add calls to `main`.

- [ ] **Step 6: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_and --output-on-failure`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add model/parser/types.sail model/parser/decode.sail model/parser/insts.sail test/parser/test_and.sail
git commit -m "Add .CD modifier to AND and ANDI instructions"
```

---

### Task 5: OR / ORI — model changes + tests

**Files:**
- Modify: `model/parser/types.sail:83-89`
- Modify: `model/parser/decode.sail:174-180`
- Modify: `model/parser/insts.sail:242-273`
- Modify: `test/parser/test_or.sail`

- [ ] **Step 1: Update types.sail — add `bool` to POR and PORI**

```sail
// OR: Bitwise OR of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits, clear_dest)
union clause pinstr = POR : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8, bool)

// ORI: Bitwise OR of register sub-field and immediate.
// Fields: (dest_reg, src_reg, immediate_value, size_bits, clear_dest)
union clause pinstr = PORI : (pregidx, pregidx, bits16, bits8, bool)
```

- [ ] **Step 2: Update decode.sail — add `encdec_bool(cd)` to POR and PORI**

```sail
// Opcode 33: OR (3+8+3+8+3+8+8+1 = 42 field bits, 16 padding)
mapping clause encdec = POR(rd, doff, rs1, s1off, rs2, s2off, sz, cd)
    <-> 0b100001 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ encdec_bool(cd) @ 0x0000 : bits(16)

// Opcode 34: ORI (3+3+16+8+1 = 31 field bits, 27 padding)
mapping clause encdec = PORI(rd, rs, imm, sz, cd)
    <-> 0b100010 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x000000 : bits(24)
```

- [ ] **Step 3: Update insts.sail — add `clear_dest` to POR and PORI**

Same pattern.

- [ ] **Step 4: Update test_or.sail — add `, false` to all 3 existing call sites**

Lines 9, 21: POR. Line 31: PORI.

- [ ] **Step 5: Add .CD tests to test_or.sail**

```sail
val test_or_with_clear_dest : unit -> unit
function test_or_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000A0;
    PR[1] = 0x00000000_00000000_00000000_0000000B;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(POR(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, true));
    assert(PR[2] == 0x00000000_00000000_00000000_000000AB,
        "OR.CD should clear dest then place OR result")
}

val test_ori_with_clear_dest : unit -> unit
function test_ori_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000A0;
    PR[1] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PORI(PR1, PR0, 0x000B, 0x08, true));
    assert(PR[1] == 0x00000000_00000000_00000000_000000AB,
        "ORI.CD should clear dest then place OR result")
}
```

Add calls to `main`.

- [ ] **Step 6: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_or --output-on-failure`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add model/parser/types.sail model/parser/decode.sail model/parser/insts.sail test/parser/test_or.sail
git commit -m "Add .CD modifier to OR and ORI instructions"
```

---

### Task 6: CNCTBY / CNCTBI — model changes + tests

**Files:**
- Modify: `model/parser/types.sail:103-111`
- Modify: `model/parser/decode.sail:78-84`
- Modify: `model/parser/insts.sail:316-371`
- Modify: `test/parser/test_cnct.sail`

- [ ] **Step 1: Update types.sail — add `bool` to PCNCTBY and PCNCTBI**

```sail
// CNCTBY: Concatenate from two source registers (byte granularity).
// Fields: (dest_reg, dest_offset_bytes, src1_reg, src1_offset_bytes, src1_size_bytes,
//          src2_reg, src2_offset_bytes, src2_size_bytes, clear_dest)
union clause pinstr = PCNCTBY : (pregidx, bits8, pregidx, bits8, bits8, pregidx, bits8, bits8, bool)

// CNCTBI: Concatenate from two source registers (bit granularity).
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src1_size_bits,
//          src2_reg, src2_offset_bits, src2_size_bits, clear_dest)
union clause pinstr = PCNCTBI : (pregidx, bits8, pregidx, bits8, bits8, pregidx, bits8, bits8, bool)
```

- [ ] **Step 2: Update decode.sail — add `encdec_bool(cd)` to PCNCTBY and PCNCTBI**

CNCTBY/CNCTBI currently have 49 field bits with `0b0 : bits(1) @ 0x00 : bits(8)` padding (9 bits). The `0b0 : bits(1)` becomes `encdec_bool(cd)`:

```sail
// Opcode  9: CNCTBY (3+8+3+8+8+3+8+8+1 = 50 field bits, 8 padding)
mapping clause encdec = PCNCTBY(rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd)
    <-> 0b001001 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ s1sz @ encdec_pregidx(rs2) @ s2off @ s2sz @ encdec_bool(cd) @ 0x00 : bits(8)

// Opcode 10: CNCTBI (3+8+3+8+8+3+8+8+1 = 50 field bits, 8 padding)
mapping clause encdec = PCNCTBI(rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd)
    <-> 0b001010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ s1sz @ encdec_pregidx(rs2) @ s2off @ s2sz @ encdec_bool(cd) @ 0x00 : bits(8)
```

- [ ] **Step 3: Update insts.sail — add `clear_dest` to PCNCTBY and PCNCTBI**

For PCNCTBY:
```sail
function clause execute(PCNCTBY(
    rd,
    dest_offset_bytes,
    rs1,
    src1_offset_bytes,
    src1_size_bytes,
    rs2,
    src2_offset_bytes,
    src2_size_bytes,
    clear_dest,
)) = {
    ...
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    ...
```

For PCNCTBI (same pattern).

- [ ] **Step 4: Update test_cnct.sail — add `, false` to all 3 existing call sites**

Lines 9, 20: PCNCTBY. Line 31: PCNCTBI.

- [ ] **Step 5: Add .CD tests to test_cnct.sail**

```sail
val test_cnctby_with_clear_dest : unit -> unit
function test_cnctby_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0x00000000_00000000_00000000_000000CD;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PCNCTBY(PR2, 0x00, PR0, 0x00, 0x01, PR1, 0x00, 0x01, true));
    assert(PR[2] == 0x00000000_00000000_00000000_0000ABCD,
        "CNCTBY.CD should clear dest then place concatenated bytes")
}

val test_cnctbi_with_clear_dest : unit -> unit
function test_cnctbi_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_0000000B;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PCNCTBI(PR2, 0x00, PR0, 0x00, 0x04, PR1, 0x00, 0x04, true));
    assert(PR[2] == 0x00000000_00000000_00000000_000000AB,
        "CNCTBI.CD should clear dest then place concatenated bits")
}
```

Add calls to `main`.

- [ ] **Step 6: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_cnct --output-on-failure`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add model/parser/types.sail model/parser/decode.sail model/parser/insts.sail test/parser/test_cnct.sail
git commit -m "Add .CD modifier to CNCTBY and CNCTBI instructions"
```

---

### Task 7: Update remaining test files (integration, program, encoding)

These files use the modified instructions but don't need new `.CD` tests — they just need `, false` appended to preserve existing behavior.

**Files:**
- Modify: `test/parser/test_integration.sail`
- Modify: `test/parser/test_program.sail`
- Modify: `test/parser/test_encoding.sail`

- [ ] **Step 1: Update test_integration.sail — add `, false` to all 16 call sites**

Every `PMOVI(` gets `, false` appended (8 sites).
Every `PADD(` gets `, false` appended (3 sites).
Every `PSUB(` gets `, false` appended (3 sites).
Every `PANDI(` gets `, false` appended (1 site).
Every `PCNCTBY(` gets `, false` appended (1 site).

- [ ] **Step 2: Update test_program.sail — add `, false` to all 11 call sites**

Every `PMOVI(` gets `, false` appended (9 sites).
Every `PADD(` gets `, false` appended (1 site).
Every `PSUBI(` gets `, false` appended (1 site).

- [ ] **Step 3: Update test_encoding.sail — add `, false` to CNCTBY call site**

Line 53: `PCNCTBY(PR0, 0x00, PR1, 0x00, 0x04, PR2, 0x04, 0x04)` becomes `PCNCTBY(PR0, 0x00, PR1, 0x00, 0x04, PR2, 0x04, 0x04, false)`.

- [ ] **Step 4: Build and run all tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --output-on-failure`
Expected: All 24 tests PASS

- [ ] **Step 5: Commit**

```bash
git add test/parser/test_integration.sail test/parser/test_program.sail test/parser/test_encoding.sail
git commit -m "Update test call sites for .CD modifier addition"
```

---

### Task 8: Update documentation

**Files:**
- Modify: `docs/spec-coverage.md`
- Modify: `docs/todo.md`

- [ ] **Step 1: Update spec-coverage.md — remove .CD from Notes column**

Remove "No .CD modifier yet" or "No .CD modifier" from these rows:
- 3.12.5 MOVMAP: remove "No .HDR modifier yet" (keep, not .CD related — leave as-is)
- 3.12.6 CNCTBY, CNCTBI: currently has no .CD note, but confirm
- 3.12.11 MOV, MOVI: change notes to remove .CD reference
- 3.12.12 MOVL... MOVRII: already has ".CD supported", no change needed
- 3.12.13 ADD, ADDI: change "No .CD modifier" to ".CD supported"
- 3.12.14 SUB, SUBI, SUBII: change "No .CD modifier" to ".CD supported"
- 3.12.15 AND, ANDI: change "No .CD modifier" to ".CD supported"
- 3.12.16 OR, ORI: change "No .CD modifier" to ".CD supported"

Update the Notes for each row to reflect `.CD supported` or clear the `.CD` mention.

- [ ] **Step 2: Update todo.md — mark .CD as resolved**

Move the `.CD` bullet from "Current" to "Resolved":

```markdown
- **.CD modifier complete**: The .CD (clear destination) modifier is now supported on all applicable instructions: MOV, MOVI, EXT, EXTNXTP, ADD, ADDI, SUB, SUBI, SUBII, AND, ANDI, OR, ORI, CNCTBY, CNCTBI, MOVL, MOVLI, MOVLII, MOVR, MOVRI, MOVRII.
```

- [ ] **Step 3: Commit**

```bash
git add docs/spec-coverage.md docs/todo.md
git commit -m "Update docs: mark .CD modifier as complete across all instructions"
```
