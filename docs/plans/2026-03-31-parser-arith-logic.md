# Parser Arithmetic, Logic, and Compare Instructions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 12 Parser ISA instructions (ADD/ADDI, SUB/SUBI/SUBII, AND/ANDI, OR/ORI, CMP/CMPIBY/CMPIBI, CNCTBY/CNCTBI) with condition flag support and tests.

**Architecture:** Each instruction group follows the established TDD pattern: add union clauses to types.sail, write tests, add execute clauses to insts.sail. All arithmetic/logic instructions operate on sub-fields of 128-bit registers via the existing `extract_bits`/`insert_bits` helpers. Condition flags (`pflag_z`, `pflag_n`) are already declared in state.sail.

**Tech Stack:** Sail language, CMake/CTest, devcontainer

---

## File Map

| File | Responsibility |
|------|---------------|
| `model/parser/types.sail` | Add union clauses for all 12 new instructions |
| `model/parser/insts.sail` | Add execute clauses for all 12 new instructions |
| `test/parser/test_add.sail` | ADD/ADDI tests |
| `test/parser/test_sub.sail` | SUB/SUBI/SUBII tests |
| `test/parser/test_and.sail` | AND/ANDI tests |
| `test/parser/test_or.sail` | OR/ORI tests |
| `test/parser/test_cmp.sail` | CMP/CMPIBY/CMPIBI tests |
| `test/parser/test_cnct.sail` | CNCTBY/CNCTBI tests |
| `test/CMakeLists.txt` | Register 6 new tests |
| `docs/coverage.md` | Update instruction status |
| `docs/todo.md` | Note simplifications |

---

### Task 1: Add All Union Clauses to types.sail

**Files:**
- Modify: `model/parser/types.sail`

- [ ] **Step 1: Add all 12 union clauses before `end pinstr`**

Add these clauses before the `end pinstr` line in `model/parser/types.sail`:

```sail
// ADD: Unsigned addition of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits)
union clause pinstr = PADD : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8)

// ADDI: Unsigned addition of register sub-field and immediate.
// Fields: (dest_reg, src_reg, immediate_value, size_bits)
union clause pinstr = PADDI : (pregidx, pregidx, bits16, bits8)

// SUB: Subtraction of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits)
union clause pinstr = PSUB : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8)

// SUBI: Subtraction of immediate from register sub-field.
// Fields: (dest_reg, src_reg, immediate_value, size_bits)
union clause pinstr = PSUBI : (pregidx, pregidx, bits16, bits8)

// SUBII: Subtraction of register sub-field from immediate (reversed).
// Fields: (dest_reg, immediate_value, src_reg, size_bits)
union clause pinstr = PSUBII : (pregidx, bits16, pregidx, bits8)

// AND: Bitwise AND of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits)
union clause pinstr = PAND : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8)

// ANDI: Bitwise AND of register sub-field and immediate.
// Fields: (dest_reg, src_reg, immediate_value, size_bits)
union clause pinstr = PANDI : (pregidx, pregidx, bits16, bits8)

// OR: Bitwise OR of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits)
union clause pinstr = POR : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8)

// ORI: Bitwise OR of register sub-field and immediate.
// Fields: (dest_reg, src_reg, immediate_value, size_bits)
union clause pinstr = PORI : (pregidx, pregidx, bits16, bits8)

// CMP: Compare two register sub-fields (subtract, set flags, discard result).
// Fields: (src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits)
union clause pinstr = PCMP : (pregidx, bits8, pregidx, bits8, bits8)

// CMPIBY: Compare register sub-field (byte offset) with immediate.
// Fields: (src_reg, src_offset_bytes, immediate_value, size_bits)
union clause pinstr = PCMPIBY : (pregidx, bits8, bits16, bits8)

// CMPIBI: Compare register sub-field (bit offset) with immediate.
// Fields: (src_reg, src_offset_bits, immediate_value, size_bits)
union clause pinstr = PCMPIBI : (pregidx, bits8, bits16, bits8)

// CNCTBY: Concatenate from two source registers (byte granularity).
// Fields: (dest_reg, dest_offset_bytes, src1_reg, src1_offset_bytes, src1_size_bytes,
//          src2_reg, src2_offset_bytes, src2_size_bytes)
union clause pinstr = PCNCTBY : (pregidx, bits8, pregidx, bits8, bits8, pregidx, bits8, bits8)

// CNCTBI: Concatenate from two source registers (bit granularity).
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src1_size_bits,
//          src2_reg, src2_offset_bits, src2_size_bits)
union clause pinstr = PCNCTBI : (pregidx, bits8, pregidx, bits8, bits8, pregidx, bits8, bits8)
```

- [ ] **Step 2: Type-check**

Run: `devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa cmake --build build --target check`
Expected: Type-check passes (warnings about unmatched patterns in execute are expected).

- [ ] **Step 3: Commit**

```bash
git add model/parser/types.sail
git commit -m "Add union clauses for arithmetic, logic, compare, and concatenate instructions"
```

---

### Task 2: ADD/ADDI Instructions

**Files:**
- Modify: `model/parser/insts.sail`
- Create: `test/parser/test_add.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Write ADD/ADDI tests**

Create `test/parser/test_add.sail`:

```sail
// Tests for ADD and ADDI instructions.
// Per XISA spec (Section 3.12.13):
//   ADD: DestReg[k:l] = Src1Reg[i1:j1] + Src2Reg[i2:j2], 16-bit unsigned
//   ADDI: DestReg[i:0] = SrcReg[i-1:0] + ImmediateValue
//   Flags: Z set if result is zero

val test_add_basic : unit -> unit
function test_add_basic() = {
    parser_init();
    // R0[7:0] = 0x03, R1[7:0] = 0x05
    PR[0] = 0x00000000_00000000_00000000_00000003;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    // ADD R2, dest_off=0, R0, src1_off=0, R1, src2_off=0, size=8
    let _ = execute(PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(PR[2] == 0x00000000_00000000_00000000_00000008,
           "ADD: 3 + 5 = 8");
    assert(pflag_z == false, "ADD: result is not zero");
}

val test_add_with_offsets : unit -> unit
function test_add_with_offsets() = {
    parser_init();
    // R0[15:8] = 0x0A
    PR[0] = 0x00000000_00000000_00000000_00000A00;
    // R1[7:0] = 0x14
    PR[1] = 0x00000000_00000000_00000000_00000014;

    // ADD R2, dest_off=0, R0, src1_off=8, R1, src2_off=0, size=8
    // Extracts R0[15:8]=0x0A and R1[7:0]=0x14, result=0x1E, stored at R2[7:0]
    let _ = execute(PADD(PR2, 0x00, PR0, 0x08, PR1, 0x00, 0x08));

    assert(PR[2] == 0x00000000_00000000_00000000_0000001E,
           "ADD with offsets: 0x0A + 0x14 = 0x1E");
}

val test_add_zero_flag : unit -> unit
function test_add_zero_flag() = {
    parser_init();
    PR[0] = sail_zeros(128);
    PR[1] = sail_zeros(128);

    let _ = execute(PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(pflag_z == true, "ADD: 0 + 0 should set Z flag");
}

val test_add_16bit_overflow : unit -> unit
function test_add_16bit_overflow() = {
    parser_init();
    // 0xFFFF + 0x0001 = 0x10000, but only 16 bits stored = 0x0000
    PR[0] = 0x00000000_00000000_00000000_0000FFFF;
    PR[1] = 0x00000000_00000000_00000000_00000001;

    let _ = execute(PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x10));

    assert(PR[2] == 0x00000000_00000000_00000000_00000000,
           "ADD: 16-bit overflow wraps to 0");
    assert(pflag_z == true, "ADD: overflow to zero sets Z flag");
}

val test_addi_basic : unit -> unit
function test_addi_basic() = {
    parser_init();
    // R0[7:0] = 0x0A
    PR[0] = 0x00000000_00000000_00000000_0000000A;

    // ADDI R1, R0, imm=5, size=8
    // R1[7:0] = R0[7:0] + 5 = 0x0F
    let _ = execute(PADDI(PR1, PR0, 0x0005, 0x08));

    assert(PR[1] == 0x00000000_00000000_00000000_0000000F,
           "ADDI: 0x0A + 5 = 0x0F");
    assert(pflag_z == false, "ADDI: result is not zero");
}

val test_addi_zero_flag : unit -> unit
function test_addi_zero_flag() = {
    parser_init();
    PR[0] = sail_zeros(128);

    let _ = execute(PADDI(PR1, PR0, 0x0000, 0x08));

    assert(pflag_z == true, "ADDI: 0 + 0 sets Z flag");
}

val main : unit -> unit
function main() = {
    test_add_basic();
    test_add_with_offsets();
    test_add_zero_flag();
    test_add_16bit_overflow();
    test_addi_basic();
    test_addi_zero_flag();
}
```

- [ ] **Step 2: Add execute clauses to model/parser/insts.sail**

Add before `end execute`:

```sail
// ADD: DestReg[dest_off + sz - 1 : dest_off] = Src1Reg[s1_off + sz - 1 : s1_off] + Src2Reg[s2_off + sz - 1 : s2_off]
// Unsigned 16-bit addition. Sets Z flag.
function clause execute(PADD(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
    let doff : nat = unsigned(dest_offset);
    let s1off : nat = unsigned(src1_offset);
    let s2off : nat = unsigned(src2_offset);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(s1_val, s1off, sz);
    let op2 = extract_bits(s2_val, s2off, sz);
    let sum : bits128 = sail_mask(128, sail_ones(sz)) & (op1 + op2);
    pflag_z = (sum == sail_zeros(128));
    let result = insert_bits(dst_val, doff, sz, sum);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// ADDI: DestReg[sz - 1 : 0] = SrcReg[sz - 1 : 0] + ImmediateValue
// Unsigned addition with immediate. Sets Z flag.
function clause execute(PADDI(rd, rs, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, 0, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let sum : bits128 = sail_mask(128, sail_ones(sz)) & (op1 + op2);
    pflag_z = (sum == sail_zeros(128));
    let result = insert_bits(dst_val, 0, sz, sum);
    write_preg(rd, result);
    RETIRE_SUCCESS
}
```

- [ ] **Step 3: Register test and run**

Add to `test/CMakeLists.txt`:
```cmake
add_sail_test(test_add test/parser/test_add.sail)
```

Run:
```bash
devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa cmake -B build
devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa cmake --build build
devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa ctest --test-dir build --verbose
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add model/parser/insts.sail test/parser/test_add.sail test/CMakeLists.txt
git commit -m "Add ADD and ADDI instructions with tests"
```

---

### Task 3: SUB/SUBI/SUBII Instructions

**Files:**
- Modify: `model/parser/insts.sail`
- Create: `test/parser/test_sub.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Write SUB/SUBI/SUBII tests**

Create `test/parser/test_sub.sail`:

```sail
// Tests for SUB, SUBI, and SUBII instructions.
// Per XISA spec (Section 3.12.14):
//   SUB: DestReg[k:l] = Src1Reg[i1:j1] - Src2Reg[i2:j2]
//   SUBI: DestReg[i-1:0] = SrcReg[i-1:0] - ImmediateValue
//   SUBII: DestReg[i-1:0] = ImmediateValue - SrcReg[i-1:0]
//   Flags: Z (zero), N (negative)

val test_sub_basic : unit -> unit
function test_sub_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_00000003;

    let _ = execute(PSUB(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(PR[2] == 0x00000000_00000000_00000000_00000007,
           "SUB: 10 - 3 = 7");
    assert(pflag_z == false, "SUB: result not zero");
    assert(pflag_n == false, "SUB: result not negative");
}

val test_sub_zero_result : unit -> unit
function test_sub_zero_result() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000005;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = execute(PSUB(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(pflag_z == true, "SUB: 5 - 5 sets Z flag");
    assert(pflag_n == false, "SUB: 5 - 5 does not set N flag");
}

val test_sub_negative_result : unit -> unit
function test_sub_negative_result() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    // 3 - 5 = -2 (wraps to 0xFE in 8 bits)
    let _ = execute(PSUB(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(PR[2] == 0x00000000_00000000_00000000_000000FE,
           "SUB: 3 - 5 wraps to 0xFE");
    assert(pflag_z == false, "SUB: result not zero");
    assert(pflag_n == true, "SUB: 3 - 5 sets N flag");
}

val test_subi_basic : unit -> unit
function test_subi_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000F;

    let _ = execute(PSUBI(PR1, PR0, 0x0005, 0x08));

    assert(PR[1] == 0x00000000_00000000_00000000_0000000A,
           "SUBI: 15 - 5 = 10");
    assert(pflag_z == false, "SUBI: result not zero");
    assert(pflag_n == false, "SUBI: result not negative");
}

val test_subii_basic : unit -> unit
function test_subii_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;

    // SUBII: imm - reg = 10 - 3 = 7
    let _ = execute(PSUBII(PR1, 0x000A, PR0, 0x08));

    assert(PR[1] == 0x00000000_00000000_00000000_00000007,
           "SUBII: 10 - 3 = 7");
    assert(pflag_n == false, "SUBII: result not negative");
}

val test_subii_negative : unit -> unit
function test_subii_negative() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;

    // SUBII: 3 - 10 = -7 (wraps to 0xF9 in 8 bits)
    let _ = execute(PSUBII(PR1, 0x0003, PR0, 0x08));

    assert(PR[1] == 0x00000000_00000000_00000000_000000F9,
           "SUBII: 3 - 10 wraps to 0xF9");
    assert(pflag_n == true, "SUBII: 3 - 10 sets N flag");
}

val main : unit -> unit
function main() = {
    test_sub_basic();
    test_sub_zero_result();
    test_sub_negative_result();
    test_subi_basic();
    test_subii_basic();
    test_subii_negative();
}
```

- [ ] **Step 2: Add execute clauses**

Add before `end execute` in `model/parser/insts.sail`:

```sail
// SUB: DestReg[dest_off + sz - 1 : dest_off] = Src1Reg[s1_off...] - Src2Reg[s2_off...]
// 16-bit subtraction. Sets Z and N flags.
function clause execute(PSUB(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
    let doff : nat = unsigned(dest_offset);
    let s1off : nat = unsigned(src1_offset);
    let s2off : nat = unsigned(src2_offset);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(s1_val, s1off, sz);
    let op2 = extract_bits(s2_val, s2off, sz);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & (op1 - op2);
    pflag_z = (diff == sail_zeros(128));
    // N flag: MSB of the sz-bit result indicates negative (signed interpretation)
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    let result = insert_bits(dst_val, doff, sz, diff);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// SUBI: DestReg[sz - 1 : 0] = SrcReg[sz - 1 : 0] - ImmediateValue
function clause execute(PSUBI(rd, rs, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, 0, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & (op1 - op2);
    pflag_z = (diff == sail_zeros(128));
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    let result = insert_bits(dst_val, 0, sz, diff);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// SUBII: DestReg[sz - 1 : 0] = ImmediateValue - SrcReg[sz - 1 : 0]
function clause execute(PSUBII(rd, immediate, rs, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
    let sz : nat = unsigned(size_bits);
    let op1 : bits128 = sail_zero_extend(immediate, 128);
    let op2 = extract_bits(src_val, 0, sz);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & (op1 - op2);
    pflag_z = (diff == sail_zeros(128));
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    let result = insert_bits(dst_val, 0, sz, diff);
    write_preg(rd, result);
    RETIRE_SUCCESS
}
```

- [ ] **Step 3: Register test and run**

Add to `test/CMakeLists.txt`:
```cmake
add_sail_test(test_sub test/parser/test_sub.sail)
```

Run: `devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa cmake -B build && devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa cmake --build build && devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa ctest --test-dir build --verbose`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add model/parser/insts.sail test/parser/test_sub.sail test/CMakeLists.txt
git commit -m "Add SUB, SUBI, and SUBII instructions with tests"
```

---

### Task 4: AND/ANDI Instructions

**Files:**
- Modify: `model/parser/insts.sail`
- Create: `test/parser/test_and.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Write AND/ANDI tests**

Create `test/parser/test_and.sail`:

```sail
// Tests for AND and ANDI instructions.
// Per XISA spec (Section 3.12.15):
//   AND: DestReg[k:l] = Src1Reg[i1:j1] & Src2Reg[i2:j2]
//   ANDI: DestReg[i-1:0] = SrcReg[i-1:0] & ImmediateValue
//   Flags: Z (zero)

val test_and_basic : unit -> unit
function test_and_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000FF;
    PR[1] = 0x00000000_00000000_00000000_0000000F;

    let _ = execute(PAND(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(PR[2] == 0x00000000_00000000_00000000_0000000F,
           "AND: 0xFF & 0x0F = 0x0F");
    assert(pflag_z == false, "AND: result not zero");
}

val test_and_zero_result : unit -> unit
function test_and_zero_result() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000F0;
    PR[1] = 0x00000000_00000000_00000000_0000000F;

    let _ = execute(PAND(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(PR[2] == 0x00000000_00000000_00000000_00000000,
           "AND: 0xF0 & 0x0F = 0x00");
    assert(pflag_z == true, "AND: zero result sets Z flag");
}

val test_andi_basic : unit -> unit
function test_andi_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;

    let _ = execute(PANDI(PR1, PR0, 0x000F, 0x08));

    assert(PR[1] == 0x00000000_00000000_00000000_0000000B,
           "ANDI: 0xAB & 0x0F = 0x0B");
    assert(pflag_z == false, "ANDI: result not zero");
}

val test_andi_zero_result : unit -> unit
function test_andi_zero_result() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000F0;

    let _ = execute(PANDI(PR1, PR0, 0x000F, 0x08));

    assert(pflag_z == true, "ANDI: 0xF0 & 0x0F sets Z flag");
}

val main : unit -> unit
function main() = {
    test_and_basic();
    test_and_zero_result();
    test_andi_basic();
    test_andi_zero_result();
}
```

- [ ] **Step 2: Add execute clauses**

Add before `end execute`:

```sail
// AND: DestReg[dest_off + sz - 1 : dest_off] = Src1Reg[s1_off...] & Src2Reg[s2_off...]
// Bitwise AND. Sets Z flag.
function clause execute(PAND(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
    let doff : nat = unsigned(dest_offset);
    let s1off : nat = unsigned(src1_offset);
    let s2off : nat = unsigned(src2_offset);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(s1_val, s1off, sz);
    let op2 = extract_bits(s2_val, s2off, sz);
    let res : bits128 = op1 & op2;
    pflag_z = (res == sail_zeros(128));
    let result = insert_bits(dst_val, doff, sz, res);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// ANDI: DestReg[sz - 1 : 0] = SrcReg[sz - 1 : 0] & ImmediateValue
function clause execute(PANDI(rd, rs, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, 0, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let res : bits128 = op1 & op2;
    pflag_z = (res == sail_zeros(128));
    let result = insert_bits(dst_val, 0, sz, res);
    write_preg(rd, result);
    RETIRE_SUCCESS
}
```

- [ ] **Step 3: Register test and run**

Add to `test/CMakeLists.txt`:
```cmake
add_sail_test(test_and test/parser/test_and.sail)
```

Run: build and test as before.
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add model/parser/insts.sail test/parser/test_and.sail test/CMakeLists.txt
git commit -m "Add AND and ANDI instructions with tests"
```

---

### Task 5: OR/ORI Instructions

**Files:**
- Modify: `model/parser/insts.sail`
- Create: `test/parser/test_or.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Write OR/ORI tests**

Create `test/parser/test_or.sail`:

```sail
// Tests for OR and ORI instructions.
// Per XISA spec (Section 3.12.16):
//   OR: DestReg[k:l] = Src1Reg[i1:j1] | Src2Reg[i2:j2]
//   ORI: DestReg[i-1:0] = SrcReg[i-1:0] | ImmediateValue
//   Flags: Z (zero)

val test_or_basic : unit -> unit
function test_or_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000F0;
    PR[1] = 0x00000000_00000000_00000000_0000000F;

    let _ = execute(POR(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(PR[2] == 0x00000000_00000000_00000000_000000FF,
           "OR: 0xF0 | 0x0F = 0xFF");
    assert(pflag_z == false, "OR: result not zero");
}

val test_or_zero_result : unit -> unit
function test_or_zero_result() = {
    parser_init();
    PR[0] = sail_zeros(128);
    PR[1] = sail_zeros(128);

    let _ = execute(POR(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(pflag_z == true, "OR: 0 | 0 sets Z flag");
}

val test_ori_basic : unit -> unit
function test_ori_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000A0;

    let _ = execute(PORI(PR1, PR0, 0x000F, 0x08));

    assert(PR[1] == 0x00000000_00000000_00000000_000000AF,
           "ORI: 0xA0 | 0x0F = 0xAF");
    assert(pflag_z == false, "ORI: result not zero");
}

val main : unit -> unit
function main() = {
    test_or_basic();
    test_or_zero_result();
    test_ori_basic();
}
```

- [ ] **Step 2: Add execute clauses**

Add before `end execute`:

```sail
// OR: DestReg[dest_off + sz - 1 : dest_off] = Src1Reg[s1_off...] | Src2Reg[s2_off...]
// Bitwise OR. Sets Z flag.
function clause execute(POR(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
    let doff : nat = unsigned(dest_offset);
    let s1off : nat = unsigned(src1_offset);
    let s2off : nat = unsigned(src2_offset);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(s1_val, s1off, sz);
    let op2 = extract_bits(s2_val, s2off, sz);
    let res : bits128 = op1 | op2;
    pflag_z = (res == sail_zeros(128));
    let result = insert_bits(dst_val, doff, sz, res);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// ORI: DestReg[sz - 1 : 0] = SrcReg[sz - 1 : 0] | ImmediateValue
function clause execute(PORI(rd, rs, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, 0, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let res : bits128 = op1 | op2;
    pflag_z = (res == sail_zeros(128));
    let result = insert_bits(dst_val, 0, sz, res);
    write_preg(rd, result);
    RETIRE_SUCCESS
}
```

- [ ] **Step 3: Register test and run**

Add to `test/CMakeLists.txt`:
```cmake
add_sail_test(test_or test/parser/test_or.sail)
```

Run: build and test. Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add model/parser/insts.sail test/parser/test_or.sail test/CMakeLists.txt
git commit -m "Add OR and ORI instructions with tests"
```

---

### Task 6: CMP/CMPIBY/CMPIBI Instructions

**Files:**
- Modify: `model/parser/insts.sail`
- Create: `test/parser/test_cmp.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Write CMP tests**

Create `test/parser/test_cmp.sail`:

```sail
// Tests for CMP, CMPIBY, and CMPIBI instructions.
// Per XISA spec (Section 3.12.17):
//   CMP: Result = Source1[i1:j1] - Source2[i2:j2] (flags only, no store)
//   CMPIBY: Result = SourceReg[i-1:j] - ImmediateValue (byte offset)
//   CMPIBI: Result = SourceReg[i-1:j] - ImmediateValue (bit offset)
//   Flags: Z (zero), N (negative)

val test_cmp_equal : unit -> unit
function test_cmp_equal() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000042;
    PR[1] = 0x00000000_00000000_00000000_00000042;

    let _ = execute(PCMP(PR0, 0x00, PR1, 0x00, 0x08));

    assert(pflag_z == true, "CMP: equal values set Z flag");
    assert(pflag_n == false, "CMP: equal values do not set N flag");
}

val test_cmp_greater : unit -> unit
function test_cmp_greater() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = execute(PCMP(PR0, 0x00, PR1, 0x00, 0x08));

    assert(pflag_z == false, "CMP: 10 > 5, Z not set");
    assert(pflag_n == false, "CMP: 10 > 5, N not set");
}

val test_cmp_less : unit -> unit
function test_cmp_less() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = execute(PCMP(PR0, 0x00, PR1, 0x00, 0x08));

    assert(pflag_z == false, "CMP: 3 < 5, Z not set");
    assert(pflag_n == true, "CMP: 3 < 5, N set");
}

val test_cmp_does_not_store : unit -> unit
function test_cmp_does_not_store() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = execute(PCMP(PR0, 0x00, PR1, 0x00, 0x08));

    // Registers should not be modified
    assert(PR[0] == 0x00000000_00000000_00000000_0000000A,
           "CMP should not modify source registers");
    assert(PR[1] == 0x00000000_00000000_00000000_00000005,
           "CMP should not modify source registers");
}

val test_cmpiby_equal : unit -> unit
function test_cmpiby_equal() = {
    parser_init();
    // R0 byte 2 (bits [23:16]) = 0x42
    PR[0] = 0x00000000_00000000_00000000_00420000;

    // CMPIBY R0, offset_bytes=2, imm=0x42, size=8
    let _ = execute(PCMPIBY(PR0, 0x02, 0x0042, 0x08));

    assert(pflag_z == true, "CMPIBY: equal values set Z flag");
    assert(pflag_n == false, "CMPIBY: equal values do not set N flag");
}

val test_cmpibi_less : unit -> unit
function test_cmpibi_less() = {
    parser_init();
    // R0[7:0] = 0x03
    PR[0] = 0x00000000_00000000_00000000_00000003;

    // CMPIBI R0, offset_bits=0, imm=0x0A, size=8
    // 3 - 10 = negative
    let _ = execute(PCMPIBI(PR0, 0x00, 0x000A, 0x08));

    assert(pflag_z == false, "CMPIBI: 3 < 10, Z not set");
    assert(pflag_n == true, "CMPIBI: 3 < 10, N set");
}

val main : unit -> unit
function main() = {
    test_cmp_equal();
    test_cmp_greater();
    test_cmp_less();
    test_cmp_does_not_store();
    test_cmpiby_equal();
    test_cmpibi_less();
}
```

- [ ] **Step 2: Add execute clauses**

Add before `end execute`:

```sail
// CMP: Compare two register sub-fields. Sets Z and N flags. Does not store result.
function clause execute(PCMP(rs1, src1_offset, rs2, src2_offset, size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let s1off : nat = unsigned(src1_offset);
    let s2off : nat = unsigned(src2_offset);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(s1_val, s1off, sz);
    let op2 = extract_bits(s2_val, s2off, sz);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & (op1 - op2);
    pflag_z = (diff == sail_zeros(128));
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    RETIRE_SUCCESS
}

// CMPIBY: Compare register sub-field (byte offset) with immediate.
function clause execute(PCMPIBY(rs, src_offset_bytes, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bytes) * 8;
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, soff, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & (op1 - op2);
    pflag_z = (diff == sail_zeros(128));
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    RETIRE_SUCCESS
}

// CMPIBI: Compare register sub-field (bit offset) with immediate.
function clause execute(PCMPIBI(rs, src_offset_bits, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, soff, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & (op1 - op2);
    pflag_z = (diff == sail_zeros(128));
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    RETIRE_SUCCESS
}
```

- [ ] **Step 3: Register test and run**

Add to `test/CMakeLists.txt`:
```cmake
add_sail_test(test_cmp test/parser/test_cmp.sail)
```

Run: build and test. Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add model/parser/insts.sail test/parser/test_cmp.sail test/CMakeLists.txt
git commit -m "Add CMP, CMPIBY, and CMPIBI instructions with tests"
```

---

### Task 7: CNCTBY/CNCTBI Instructions

**Files:**
- Modify: `model/parser/insts.sail`
- Create: `test/parser/test_cnct.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Write CNCTBY/CNCTBI tests**

Create `test/parser/test_cnct.sail`:

```sail
// Tests for CNCTBY and CNCTBI instructions.
// Per XISA spec (Section 3.12.6):
//   CNCTBY: Concatenate from two source registers (byte granularity).
//     DestReg[dest_off...] = Src1Reg[s1_off:s1_size] || Src2Reg[s2_off:s2_size]
//     Src1 data is placed at higher bits, Src2 at lower bits.
//   CNCTBI: Same but offsets and sizes in bit granularity.

val test_cnctby_basic : unit -> unit
function test_cnctby_basic() = {
    parser_init();
    // R0 byte 0 (bits [7:0]) = 0xAA
    PR[0] = 0x00000000_00000000_00000000_000000AA;
    // R1 byte 0 (bits [7:0]) = 0xBB
    PR[1] = 0x00000000_00000000_00000000_000000BB;

    // CNCTBY R2, dest_off_bytes=0, R0, src1_off_bytes=0, src1_size_bytes=1,
    //                               R1, src2_off_bytes=0, src2_size_bytes=1
    // Result: R2[15:0] = 0xAA || 0xBB = 0xAABB (src1 high, src2 low)
    let _ = execute(PCNCTBY(PR2, 0x00, PR0, 0x00, 0x01, PR1, 0x00, 0x01));

    assert(PR[2] == 0x00000000_00000000_00000000_0000AABB,
           "CNCTBY: concatenate two bytes");
}

val test_cnctby_with_offsets : unit -> unit
function test_cnctby_with_offsets() = {
    parser_init();
    // R0 byte 1 (bits [15:8]) = 0xCC
    PR[0] = 0x00000000_00000000_00000000_0000CC00;
    // R1 byte 2 (bits [23:16]) = 0xDD
    PR[1] = 0x00000000_00000000_00000000_00DD0000;

    // CNCTBY R2, dest=0, R0, src1_off=1, src1_size=1, R1, src2_off=2, src2_size=1
    let _ = execute(PCNCTBY(PR2, 0x00, PR0, 0x01, 0x01, PR1, 0x02, 0x01));

    assert(PR[2] == 0x00000000_00000000_00000000_0000CCDD,
           "CNCTBY: concatenate bytes from different offsets");
}

val test_cnctbi_basic : unit -> unit
function test_cnctbi_basic() = {
    parser_init();
    // R0[3:0] = 0xA (4 bits)
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    // R1[3:0] = 0x5 (4 bits)
    PR[1] = 0x00000000_00000000_00000000_00000005;

    // CNCTBI R2, dest_off_bits=0, R0, src1_off=0, src1_size=4, R1, src2_off=0, src2_size=4
    // Result: R2[7:0] = 0xA || 0x5 = 0xA5
    let _ = execute(PCNCTBI(PR2, 0x00, PR0, 0x00, 0x04, PR1, 0x00, 0x04));

    assert(PR[2] == 0x00000000_00000000_00000000_000000A5,
           "CNCTBI: concatenate two 4-bit fields");
}

val main : unit -> unit
function main() = {
    test_cnctby_basic();
    test_cnctby_with_offsets();
    test_cnctbi_basic();
}
```

- [ ] **Step 2: Add execute clauses**

Add before `end execute`:

```sail
// CNCTBY: Concatenate from two source registers (byte granularity).
// DestReg[dest_off*8 + (s1_size + s2_size)*8 - 1 : dest_off*8] = Src1[...] || Src2[...]
// Src1 data is placed at higher bits, Src2 at lower bits.
function clause execute(PCNCTBY(rd, dest_offset_bytes, rs1, src1_offset_bytes, src1_size_bytes,
                                rs2, src2_offset_bytes, src2_size_bytes)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
    let doff : nat = unsigned(dest_offset_bytes) * 8;
    let s1off : nat = unsigned(src1_offset_bytes) * 8;
    let s1sz : nat = unsigned(src1_size_bytes) * 8;
    let s2off : nat = unsigned(src2_offset_bytes) * 8;
    let s2sz : nat = unsigned(src2_size_bytes) * 8;
    let part1 = extract_bits(s1_val, s1off, s1sz);
    let part2 = extract_bits(s2_val, s2off, s2sz);
    // Concatenate: part1 at high bits, part2 at low bits
    let combined : bits128 = sail_shiftleft(part1, s2sz) | part2;
    let total_sz : nat = s1sz + s2sz;
    let result = insert_bits(dst_val, doff, total_sz, combined);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// CNCTBI: Concatenate from two source registers (bit granularity).
function clause execute(PCNCTBI(rd, dest_offset_bits, rs1, src1_offset_bits, src1_size_bits,
                                rs2, src2_offset_bits, src2_size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
    let doff : nat = unsigned(dest_offset_bits);
    let s1off : nat = unsigned(src1_offset_bits);
    let s1sz : nat = unsigned(src1_size_bits);
    let s2off : nat = unsigned(src2_offset_bits);
    let s2sz : nat = unsigned(src2_size_bits);
    let part1 = extract_bits(s1_val, s1off, s1sz);
    let part2 = extract_bits(s2_val, s2off, s2sz);
    let combined : bits128 = sail_shiftleft(part1, s2sz) | part2;
    let total_sz : nat = s1sz + s2sz;
    let result = insert_bits(dst_val, doff, total_sz, combined);
    write_preg(rd, result);
    RETIRE_SUCCESS
}
```

- [ ] **Step 3: Register test and run**

Add to `test/CMakeLists.txt`:
```cmake
add_sail_test(test_cnct test/parser/test_cnct.sail)
```

Run: build and test. Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add model/parser/insts.sail test/parser/test_cnct.sail test/CMakeLists.txt
git commit -m "Add CNCTBY and CNCTBI instructions with tests"
```

---

### Task 8: Update Documentation

**Files:**
- Modify: `docs/coverage.md`
- Modify: `docs/todo.md`

- [ ] **Step 1: Update coverage.md**

Change the status for rows 13-14 (CNCTBY/CNCTBI), 23-27 (ADD through CMP) from "Not started" to "Done":

| # | Instruction | Status | Notes |
|---|-------------|--------|-------|
| 13 | CNCTBY | Done | |
| 14 | CNCTBI | Done | |
| 23 | ADD/ADDI | Done | No .CD modifier |
| 24 | SUB/SUBI/SUBII | Done | No .CD modifier |
| 25 | AND/ANDI | Done | No .CD modifier |
| 26 | OR/ORI | Done | No .CD modifier |
| 27 | CMP/CMPIBY/CMPIBI | Done | |

- [ ] **Step 2: Update todo.md**

Add under "Current":

```markdown
- **Arithmetic/logic .CD modifier not modeled**: The .CD (clear destination) modifier is not yet supported for ADD, SUB, AND, OR instructions. It should clear the destination register before writing.
```

- [ ] **Step 3: Commit**

```bash
git add docs/coverage.md docs/todo.md
git commit -m "Update coverage and todo for arithmetic/logic/compare instructions"
```

---

### Task 9: Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Clean build**

```bash
devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa bash -c "rm -rf build && cmake -B build && cmake --build build"
```

- [ ] **Step 2: Run all tests**

```bash
devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa ctest --test-dir build --verbose
```

Expected: All 10 tests pass (test_nop, test_halt, test_mov, test_ext, test_add, test_sub, test_and, test_or, test_cmp, test_cnct).

- [ ] **Step 3: Run format check**

```bash
devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa tools/format.sh --check
```

Expected: All files formatted.

- [ ] **Step 4: Fix formatting if needed and commit**

```bash
devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa tools/format.sh
git add -A
git commit -m "Apply Sail formatter"
```
