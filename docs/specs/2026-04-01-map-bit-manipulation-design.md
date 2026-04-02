# MAP Bit Manipulation Instructions Design Spec

## Overview

Add bit manipulation instructions to the MAP ISA: SHL, SHLI, SHR, SHRI (shift), CONCAT (concatenation), and FFI (find first non-zero field). These are 4B-mode (word-oriented) synchronous operations that extend the MAP foundation.

## Instructions

### SHL, SHLI (Section 4.13.9) — Shift Left

**SHL**: `Dest[m:k] = Source1[i1:j1] << Source2[i2:j2]`
- k = shift amount (from Source2 field)
- m = k + Source1Size
- If m <= 0, no value written; Z flag set when .F opted

**SHLI**: Same but shift amount is an immediate value (0-31).

Fields for SHL: `(dest_reg, dest_word, src1_reg, src1_word, src1_offset, src1_size, src2_reg, src2_word, src2_offset, src2_size, set_flags, clear_dest)`

Fields for SHLI: `(dest_reg, dest_word, src1_reg, src1_word, src1_offset, src1_size, shift_imm5, set_flags, clear_dest)`

Modifiers: `.F` (logic flag rules: Z, N set; C, V cleared), `.CD` (clear 4B dest word before write)

### SHR, SHRI (Section 4.13.9) — Shift Right

**SHR**: `Dest[m:0] = Source1[i1:j1] >> Source2[i2:j2]`
- k = shift amount (from Source2 field)
- m = Source1Size - k
- If m <= 0, no value written; Z flag set when .F opted

**SHRI**: Same but shift amount is an immediate value (0-31).

Same field layout as SHL/SHLI.

### CONCAT (Section 4.13.10) — Bitwise Concatenation

**CONCAT**: `DestReg[m:k] = (Src2[i2:j2] << Src1Size) | Src1[i1:j1]`
- k = DestOffset
- m = DestOffset + Src1Size + Src2Size - 1
- Constraint: m < 32

Fields: `(dest_reg, dest_word, dest_offset, src1_reg, src1_word, src1_offset, src1_size, src2_reg, src2_word, src2_offset, src2_size, clear_dest)`

Modifier: `.CD` (clear 4B dest word before write)

### FFI (Section 4.13.12) — Find First non-zero field

**FFI**: Scan a 32-bit value for the first non-zero field of a given size (1-4 bits).

- Scan start offset from OffsetReg[4:0]
- Scan direction: 0 = MSb to LSb, 1 = LSb to MSb
- If found: `DestReg[4:0]` = field offset, `DestReg[11:8]` = field content, Z cleared
- If not found: Z flag set
- Always uses `.F` (FFI.F is the only form)

Fields: `(dest_reg, dest_word, value_reg, value_word, offset_reg, offset_word, field_size_imm, scan_direction_imm)`

## File Changes

| File | Action | Change |
|------|--------|--------|
| `model/map/types.sail` | Modify | Add 6 union clauses (MSHL, MSHLI, MSHR, MSHRI, MCONCAT, MFFI) before `end minstr` |
| `model/map/insts.sail` | Modify | Add 6 execute clauses before `end mexecute` |
| `model/map/decode.sail` | Modify | Add 6 encoding mappings (opcodes 20-25) before `end mencdec` |
| `test/map/test_shift.sail` | Create | SHL, SHLI, SHR, SHRI tests |
| `test/map/test_concat.sail` | Create | CONCAT tests |
| `test/map/test_ffi.sail` | Create | FFI tests |
| `test/CMakeLists.txt` | Modify | Register 3 new tests |
| `docs/spec-coverage.md` | Modify | Update 3 rows |

## Binary Encoding (Opcodes 20-25)

| Op | Instr | Fields |
|----|-------|--------|
| 20 | SHL | rd(4) rw(2) rs1(4) sw1(2) s1off(5) s1sz(5) rs2(4) sw2(2) s2off(5) s2sz(5) f(1) cd(1) = 40, pad 18 |
| 21 | SHLI | rd(4) rw(2) rs1(4) sw1(2) s1off(5) s1sz(5) imm5(5) f(1) cd(1) = 28, pad 30 |
| 22 | SHR | same as SHL = 40, pad 18 |
| 23 | SHRI | same as SHLI = 28, pad 30 |
| 24 | CONCAT | rd(4) rw(2) doff(5) rs1(4) sw1(2) s1off(5) s1sz(5) rs2(4) sw2(2) s2off(5) s2sz(5) cd(1) = 44, pad 14 |
| 25 | FFI | rd(4) rw(2) vr(4) vw(2) or(4) ow(2) fsz(2) dir(1) = 21, pad 37 |

All fit within 58 available bits.

## Testing

| Test file | What it covers |
|-----------|---------------|
| `test/map/test_shift.sail` | SHL basic, SHLI basic, SHR basic, SHRI basic, shift-to-zero (m<=0), .F flags, .CD |
| `test/map/test_concat.sail` | CONCAT two fields, single source, .CD |
| `test/map/test_ffi.sail` | FFI found (LSb-to-MSb), FFI found (MSb-to-LSb), FFI not found (Z flag) |
