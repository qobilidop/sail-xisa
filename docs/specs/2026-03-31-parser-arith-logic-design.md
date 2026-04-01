# Parser Arithmetic, Logic, and Compare Instructions Design Spec

## Overview

Add 12 Parser ISA instructions across 6 groups: arithmetic (ADD, SUB), logic (AND, OR), compare (CMP), and concatenation (CNCT). These operate on 16-bit-or-less sub-fields of the 128-bit parser registers and set condition flags (Z, N).

## Instructions

### ADD/ADDI (Section 3.12.13)

- **ADD:** `DestReg[k:l] = Src1Reg[i1:j1] + Src2Reg[i2:j2]`
  - Offsets 0-15, size 1-16 bits. Unsigned 16-bit addition.
- **ADDI:** `DestReg[i:0] = SrcReg[i-1:0] + ImmediateValue`
  - Size 1-15 bits. 15-bit immediate.
- **Flags:** Z (set if result is zero).

### SUB/SUBI/SUBII (Section 3.12.14)

- **SUB:** `DestReg[k:l] = Src1Reg[i1:j1] - Src2Reg[i2:j2]`
  - Offsets 0-15, size 1-16 bits.
- **SUBI:** `DestReg[i-1:0] = SrcReg[i-1:0] - ImmediateValue`
  - Size 1-15 bits. 15-bit immediate.
- **SUBII:** `DestReg[i-1:0] = ImmediateValue - SrcReg[i-1:0]`
  - Reversed operand order.
- **Flags:** Z (zero), N (negative).

### AND/ANDI (Section 3.12.15)

- **AND:** `DestReg[k:l] = Src1Reg[i1:j1] & Src2Reg[i2:j2]`
  - Offsets 0-15, size 1-16 bits.
- **ANDI:** `DestReg[i-1:0] = SrcReg[i-1:0] & ImmediateValue`
  - Size 1-15 bits. 15-bit immediate.
- **Flags:** Z (zero).

### OR/ORI (Section 3.12.16)

- **OR:** `DestReg[k:l] = Src1Reg[i1:j1] | Src2Reg[i2:j2]`
  - Offsets 0-15, size 1-16 bits.
- **ORI:** `DestReg[i-1:0] = SrcReg[i-1:0] | ImmediateValue`
  - Size 1-15 bits. 15-bit immediate.
- **Flags:** Z (zero).

### CMP/CMPIBY/CMPIBI (Section 3.12.17)

- **CMP:** `Result = Source1[i1:j1] - Source2[i2:j2]`
  - Offsets 0-127, size 1-32 bits. Result not stored.
- **CMPIBY:** `Result = SourceReg[i-1:j] - ImmediateValue`
  - Offset in bytes (0-15), size 1-16 bits. 16-bit immediate.
- **CMPIBI:** `Result = SourceReg[i-1:j] - ImmediateValue`
  - Offset in bits (0-15), size 1-16 bits. 16-bit immediate.
- **Flags:** Z (zero), N (negative). No result stored — flags only.

### CNCTBY/CNCTBI (Section 3.12.6)

- **CNCTBY:** Concatenate from two source registers into destination. Offsets and sizes in byte granularity (8-bit units).
  - `DestReg[dest_off...] = Src1Reg[s1_off:s1_size] || Src2Reg[s2_off:s2_size]`
  - All offsets 0-15 (bytes), sizes 1-16 (bytes).
- **CNCTBI:** Same but offsets and sizes in bit granularity (1-bit units).
  - All offsets 0-15 (bits), sizes 1-16 (bits).
- **Flags:** None.

## Code Changes

- **`model/parser/types.sail`**: Add union clauses for all 12 instructions.
- **`model/parser/insts.sail`**: Add execute clauses. The register-register variants (ADD, SUB, AND, OR) share a common pattern: extract two sub-fields, operate, insert result, set flags. The immediate variants are similar but with one operand from the instruction.
- **`test/parser/`**: One test file per instruction group (6 test files).
- **`test/CMakeLists.txt`**: Register 6 new tests.
- **`docs/coverage.md`**: Update status for all 12 instructions.
- **`docs/todo.md`**: Note any simplifications.

## Flag Implementation

The `pflag_z` and `pflag_n` registers are already declared in `state.sail`. The execute clauses will set them directly:
- `pflag_z = (result == sail_zeros(sz))` or equivalent
- `pflag_n = (result[sz-1] == bitone)` (MSB of result, for signed interpretation)

## Simplifications

- No .CD (clear destination) modifier for arithmetic/logic instructions. The spec mentions it in the syntax but it's not critical for correctness. Track in todo.md.
- CMP has a wider offset range (0-127) and size range (1-32) than the arithmetic instructions. We model this with the same `bits8` fields.
