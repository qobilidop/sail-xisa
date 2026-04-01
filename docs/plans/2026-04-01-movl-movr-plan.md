# MOVL/MOVR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 6 MOVL/MOVR parser instruction variants that move data with dynamically computed destination offsets.

**Architecture:** Add 6 union clauses to `types.sail` and 6 execute clauses to `insts.sail`. Each variant computes a destination offset differently (register-based, immediate-based, or mixed), then uses `extract_bits`/`insert_bits` for the actual data move. All support `.CD` (clear destination). No new models needed.

**Tech Stack:** Sail, CMake/CTest

---

### Task 1: Add union clauses for all 6 variants

**Files:**
- Modify: `model/parser/types.sail` (before `end pinstr`)

- [ ] **Step 1: Add union clauses to `model/parser/types.sail`**

Insert before the `end pinstr` line:

```sail
// MOVL: Move left — dest offset = SrcReg2 sub-field + OffsBits1.
// Fields: (dest_reg, src1_reg, offs1, size1, src2_reg, offs2, size2, clear_dest)
union clause pinstr = PMOVL : (pregidx, pregidx, bits8, bits8, pregidx, bits8, bits8, bool)

// MOVLI: Move left immediate — dest offset = ImmValue + OffsBits.
// Fields: (dest_reg, src_reg, offs, size, imm_value, clear_dest)
union clause pinstr = PMOVLI : (pregidx, pregidx, bits8, bits8, bits8, bool)

// MOVLII: Move left immediate with immediate data — dest offset from register, data from immediate.
// Fields: (dest_reg, src_reg, offs, size, imm_value, imm_value_size, clear_dest)
union clause pinstr = PMOVLII : (pregidx, pregidx, bits8, bits8, bits8, bits8, bool)

// MOVR: Move right — dest offset = OffsBits1 - SrcReg2 sub-field.
// Fields: (dest_reg, src1_reg, offs1, size1, src2_reg, offs2, size2, clear_dest)
union clause pinstr = PMOVR : (pregidx, pregidx, bits8, bits8, pregidx, bits8, bits8, bool)

// MOVRI: Move right immediate — dest offset = OffsBits - ImmValue.
// Fields: (dest_reg, src_reg, offs, size, imm_value, clear_dest)
union clause pinstr = PMOVRI : (pregidx, pregidx, bits8, bits8, bits8, bool)

// MOVRII: Move right immediate with immediate data — dest from ImmValueSize - register sub-field.
// Fields: (dest_reg, src_reg, offs, size, imm_value, imm_value_size, clear_dest)
union clause pinstr = PMOVRII : (pregidx, pregidx, bits8, bits8, bits8, bits8, bool)
```

- [ ] **Step 2: Commit**

```bash
git add model/parser/types.sail
git commit -m "Add union clauses for MOVL/MOVR instruction variants"
```

---

### Task 2: Add execute clauses for all 6 variants

**Files:**
- Modify: `model/parser/insts.sail` (before `end execute`)

- [ ] **Step 1: Add all 6 execute clauses to `model/parser/insts.sail`**

Insert before the `end execute` line:

```sail
// MOVL: DestReg[m:k] = SrcReg1[i1:j1]
// k = SrcReg2[i2:j2] + OffsBits1 (dynamic offset, shift left)
// m = k + SizeBits1 - 1
function clause execute(PMOVL(rd, rs1, offs1, size1, rs2, offs2, size2, clear_dest)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let o1 : nat = unsigned(offs1);
    let sz1 : nat = unsigned(size1);
    let o2 : nat = unsigned(offs2);
    let sz2 : nat = unsigned(size2);
    let dynamic_offset : nat = unsigned(extract_bits(s2_val, o2, sz2));
    let k : nat = dynamic_offset + o1;
    let extracted = extract_bits(s1_val, o1, sz1);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, k, sz1, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVLI: DestReg[m:k] = SrcReg[i:j]
// k = ImmValue + OffsBits (immediate offset, shift left)
// m = k + SizeBits - 1
function clause execute(PMOVLI(rd, rs, offs, size_bits, imm_value, clear_dest)) = {
    let src_val = read_preg(rs);
    let o : nat = unsigned(offs);
    let sz : nat = unsigned(size_bits);
    let imm : nat = unsigned(imm_value);
    let k : nat = imm + o;
    let extracted = extract_bits(src_val, o, sz);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, k, sz, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVLII: DestReg[m-1:k] = ImmValue[n-1:0]
// k = SrcReg[i:j] (register sub-field is the dest offset)
// m = k + ImmValueSize
function clause execute(PMOVLII(rd, rs, offs, size_bits, imm_value, imm_value_size, clear_dest)) = {
    let src_val = read_preg(rs);
    let o : nat = unsigned(offs);
    let sz : nat = unsigned(size_bits);
    let imm_sz : nat = unsigned(imm_value_size);
    let k : nat = unsigned(extract_bits(src_val, o, sz));
    let imm_128 : bits128 = sail_zero_extend(sail_mask(128, imm_value), 128);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, k, imm_sz, imm_128);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVR: DestReg[m:k] = SrcReg1[i1:j1]
// k = OffsBits1 - SrcReg2[i2:j2] (dynamic offset, shift right)
// m = k + SizeBits1 - 1
function clause execute(PMOVR(rd, rs1, offs1, size1, rs2, offs2, size2, clear_dest)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let o1 : nat = unsigned(offs1);
    let sz1 : nat = unsigned(size1);
    let o2 : nat = unsigned(offs2);
    let sz2 : nat = unsigned(size2);
    let dynamic_offset : nat = unsigned(extract_bits(s2_val, o2, sz2));
    let k : int = o1 - dynamic_offset;
    let k_clamped : nat = if k < 0 then 0 else k;
    let extracted = extract_bits(s1_val, o1, sz1);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, k_clamped, sz1, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVRI: DestReg[m:k] = SrcReg[i:j]
// k = OffsBits - ImmValue (immediate offset, shift right)
// m = k + SizeBits - 1
function clause execute(PMOVRI(rd, rs, offs, size_bits, imm_value, clear_dest)) = {
    let src_val = read_preg(rs);
    let o : nat = unsigned(offs);
    let sz : nat = unsigned(size_bits);
    let imm : nat = unsigned(imm_value);
    let k : int = o - imm;
    let k_clamped : nat = if k < 0 then 0 else k;
    let extracted = extract_bits(src_val, o, sz);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, k_clamped, sz, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVRII: DestReg[m-1:0] = ImmValue[n-1:k]
// k = SrcReg[i:j] (register sub-field)
// m = ImmValueSize - SrcReg[i:j]
function clause execute(PMOVRII(rd, rs, offs, size_bits, imm_value, imm_value_size, clear_dest)) = {
    let src_val = read_preg(rs);
    let o : nat = unsigned(offs);
    let sz : nat = unsigned(size_bits);
    let imm_sz : nat = unsigned(imm_value_size);
    let reg_offset : nat = unsigned(extract_bits(src_val, o, sz));
    let data_size : int = imm_sz - reg_offset;
    let data_size_nat : nat = if data_size < 0 then 0 else data_size;
    // Extract from ImmValue starting at bit reg_offset, for data_size_nat bits
    let imm_128 : bits128 = sail_zero_extend(sail_mask(128, imm_value), 128);
    let extracted = extract_bits(imm_128, reg_offset, data_size_nat);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, 0, data_size_nat, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Type-check**

Run: `./dev.sh cmake --build build --target check`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add model/parser/insts.sail
git commit -m "Add execute clauses for MOVL/MOVR instruction variants"
```

---

### Task 3: Add tests and register with CTest

**Files:**
- Create: `test/parser/test_movl_movr.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create `test/parser/test_movl_movr.sail`**

```sail
// Tests for MOVL/MOVR (dynamic offset move) instruction variants.

// MOVL: R0[7:0]=0xAB, R1[2:0]=4, MOVL to R2 at dynamic offset 4+0=4.
// R2[11:4] should be 0xAB.
val test_movl_basic : unit -> unit
function test_movl_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0x00000000_00000000_00000000_00000004;
    // PMOVL(rd, rs1, offs1, size1, rs2, offs2, size2, clear_dest)
    // Extract R0[7:0] (offs1=0, size1=8), offset = R1[2:0] + 0 = 4
    let _ = execute(PMOVL(PR2, PR0, 0x00, 0x08, PR1, 0x00, 0x03, false));
    assert(read_preg(PR2) == 0x00000000_00000000_00000000_00000AB0,
        "MOVL should place 0xAB at R2[11:4]")
}

// MOVL with .CD: same as above but destination cleared first.
val test_movl_cd : unit -> unit
function test_movl_cd() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0x00000000_00000000_00000000_00000004;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PMOVL(PR2, PR0, 0x00, 0x08, PR1, 0x00, 0x03, true));
    assert(read_preg(PR2) == 0x00000000_00000000_00000000_00000AB0,
        "MOVL.CD should clear dest then place 0xAB at R2[11:4]")
}

// MOVLI: R0[7:0]=0xCD, MOVLI with imm_value=16 and offs=0.
// k = 16 + 0 = 16, R1[23:16] = 0xCD.
val test_movli_basic : unit -> unit
function test_movli_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000CD;
    // PMOVLI(rd, rs, offs, size, imm_value, clear_dest)
    let _ = execute(PMOVLI(PR1, PR0, 0x00, 0x08, 0x10, false));
    assert(read_preg(PR1) == 0x00000000_00000000_00000000_00CD0000,
        "MOVLI should place 0xCD at R1[23:16]")
}

// MOVLII: R0[2:0]=8, place imm 0x1F (5 bits) at offset 8.
// k = R0[2:0] = 8, R1[12:8] = 0x1F.
val test_movlii_basic : unit -> unit
function test_movlii_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000008;
    // PMOVLII(rd, rs, offs, size, imm_value, imm_value_size, clear_dest)
    let _ = execute(PMOVLII(PR1, PR0, 0x00, 0x03, 0x1F, 0x05, false));
    assert(read_preg(PR1) == 0x00000000_00000000_00000000_00001F00,
        "MOVLII should place 0x1F at R1[12:8]")
}

// MOVR: R0[7:0]=0xAB, R1[2:0]=4, offs1=32.
// k = 32 - 4 = 28, R2[35:28] = 0xAB.
val test_movr_basic : unit -> unit
function test_movr_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0x00000000_00000000_00000000_00000004;
    // PMOVR(rd, rs1, offs1, size1, rs2, offs2, size2, clear_dest)
    let _ = execute(PMOVR(PR2, PR0, 0x20, 0x08, PR1, 0x00, 0x03, false));
    assert(read_preg(PR2) == 0x00000000_00000000_000000AB_00000000,
        "MOVR should place 0xAB at R2[35:28]")
}

// MOVRI: R0[7:0]=0xEF, offs=32, imm=16.
// k = 32 - 16 = 16, R1[23:16] = 0xEF.
val test_movri_basic : unit -> unit
function test_movri_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000EF;
    // PMOVRI(rd, rs, offs, size, imm_value, clear_dest)
    let _ = execute(PMOVRI(PR1, PR0, 0x20, 0x08, 0x10, false));
    assert(read_preg(PR1) == 0x00000000_00000000_00000000_00EF0000,
        "MOVRI should place 0xEF at R1[23:16]")
}

// MOVRII: R0[2:0]=2, imm=0x1F (5 bits), imm_size=5.
// k = R0[2:0] = 2, m = 5 - 2 = 3, DestReg[2:0] = ImmValue[4:2] = 0b111 = 7.
val test_movrii_basic : unit -> unit
function test_movrii_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000002;
    // PMOVRII(rd, rs, offs, size, imm_value, imm_value_size, clear_dest)
    let _ = execute(PMOVRII(PR1, PR0, 0x00, 0x03, 0x1F, 0x05, false));
    assert(read_preg(PR1) == 0x00000000_00000000_00000000_00000007,
        "MOVRII should place ImmValue[4:2]=7 at R1[2:0]")
}

// Program: EXT a 3-bit offset value from packet, use MOVL to dynamically
// place 8 bits of data at that offset.
// Packet: [0x04, 0xAB]  (byte 0 has offset=4, byte 1 has data=0xAB)
val test_movl_program : unit -> unit
function test_movl_program() = {
    parser_init();
    packet_hdr[0] = 0x04;
    packet_hdr[1] = 0xAB;

    parser_load_program(
        [|
            // EXT 3 bits from packet[2:0] into R0[2:0] (the offset value = 4)
            PEXT(PR0, 0x00, 0x0005, 0x03, true),
            // EXT 8 bits from packet byte 1 into R1[7:0] (the data = 0xAB)
            PEXT(PR1, 0x00, 0x0008, 0x08, true),
            // MOVL: place R1[7:0] at dynamic offset R0[2:0] + 0 = 4 into R2
            PMOVL(PR2, PR1, 0x00, 0x08, PR0, 0x00, 0x03, true),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(read_preg(PR2) == 0x00000000_00000000_00000000_00000AB0,
        "R2 should have 0xAB at bits [11:4]")
}

val main : unit -> unit
function main() = {
    test_movl_basic();
    test_movl_cd();
    test_movli_basic();
    test_movlii_basic();
    test_movr_basic();
    test_movri_basic();
    test_movrii_basic();
    test_movl_program()
}
```

- [ ] **Step 2: Register test in `test/CMakeLists.txt`**

Add at the end:

```cmake
add_sail_test(test_movl_movr test/parser/test_movl_movr.sail)
```

- [ ] **Step 3: Build and run new test**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_movl_movr -V`
Expected: PASS

- [ ] **Step 4: Run full test suite for regressions**

Run: `./dev.sh ctest --test-dir build`
Expected: all 20 tests pass

- [ ] **Step 5: Commit**

```bash
git add test/parser/test_movl_movr.sail test/CMakeLists.txt
git commit -m "Add tests for MOVL/MOVR instruction variants"
```

---

### Task 4: Update coverage

**Files:**
- Modify: `docs/coverage.md`

- [ ] **Step 1: Update `docs/coverage.md`**

Change line 30 from:

```markdown
| 22 | MOVL/MOVR variants | 3.12.12 | Not started | 6 sub-variants |
```

to:

```markdown
| 22 | MOVL/MOVR variants | 3.12.12 | Done | .CD supported. 6 sub-variants: MOVL, MOVLI, MOVLII, MOVR, MOVRI, MOVRII |
```

- [ ] **Step 2: Commit**

```bash
git add docs/coverage.md
git commit -m "Update coverage for MOVL/MOVR instruction variants"
```
