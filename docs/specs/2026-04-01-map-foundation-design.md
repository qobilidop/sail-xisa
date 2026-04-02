# MAP ISA Foundation Design Spec

## Overview

First vertical slice of the MAP (Match-Action Processor) ISA. Establishes the MAP execution model — register file with word addressing, ZNCV condition flags, fetch-decode-execute loop, and a foundational instruction set covering arithmetic, logic, data movement, branching, and control.

This is sub-project 1 of the MAP ISA. Later sub-projects will add load/store (with PMEM), lookup (HASH/LKP), packet operations (CP/SEND), and remaining instructions.

## Scope

### In scope
- MAP state model: registers, ZNCV flags, PC, instruction memory, halted flag
- MAP fetch-decode-execute loop
- 64-bit binary instruction encoding
- Instructions (22 variants):
  - Arithmetic: ADD, ADDI, SUB, SUBI (with .F, .SX, .SH modifiers)
  - Compare: CMP, CMPI (always sets Z, C flags)
  - Logic: AND, ANDI, OR, ORI, XOR, XORI, NOT (with .F modifier)
  - Data movement: MOV, MOVI (with .CD modifier)
  - Branch: BR, BRI, BRBTST (11 condition codes + 2 bit-test codes)
  - Control: HALT, NOP

### Out of scope (later sub-projects)
- SHL/SHR, CONCAT, FFI (bit manipulation)
- LD/ST variants, PMEM, RAM, scratchpad (load/store)
- JTL, CALL, RET (subroutine support)
- HASH, LKP (lookup)
- SYNC, LFLAG (async operations)
- Dependency checker (HW pipeline model)
- COUNTER, METER, CAS/TAS, BW, DLB (atomic operations)
- CP, CHKSUM, SEND/DROP (packet operations)
- All miscellaneous instructions (STALLOC, REPARSE, IREQ, etc.)
- MOD, MODI (modulo — async, needs LFLAG)
- R14 debug register

## Architecture

### Register File (Section 4.2-4.3)

16 registers, each 128 bits, big-endian:
- **R0-R10**: General-purpose
- **R11**: HDR.PRESENT (preloaded by parser via STH)
- **R12-R13**: HDR.OFFSET0/1 (preloaded by parser via STH)
- **R14**: Debug virtual register (deferred)
- **R15/RN**: Null register — reads as zero, writes are discarded

Each register is divided into 4 words of 32 bits:

```
Bits:   127 .............. 96  95 .............. 64  63 .............. 32  31 .............. 0
Words:       Word 0 (MSW)           Word 1                Word 2              Word 3 (LSW)
Bytes:    00  01  02  03        04  05  06  07        08  09  10  11       12  13  14  15
```

**Addressing modes:**
- **Full register (16B)**: `Ri` — all 128 bits. Used only by MOV.CD and future 16B-mode instructions.
- **Word select (4B)**: `Ri.N` where N=0..3 — selects a 32-bit word. This is the primary mode for arithmetic/logic.

The register index needs 4 bits (0-15). Word select needs 2 bits (0-3).

### Operand Model

For arithmetic and logic instructions, operands work within a 32-bit word:

1. **Source extraction**: Extract a bit-field from a word: `Source[offset+size-1:offset]`
   - StartOffset: 0-31 (bits within the 32-bit word)
   - Size: 1-32 bits
   - The extracted value is zero-extended to 32 bits (or sign-extended with `.SX`)

2. **Result destination**: Written to `Dest[N:0]`
   - Normal operation: N=31 (full 32-bit word)
   - Short operation (`.SH`): N=15 (low 16 bits; upper 16 bits of the word are unchanged)

3. **Immediate values**: Up to 16 bits for arithmetic (ADDI, SUBI), up to 32 bits for MOVI.

### Condition Code Flags (Section 4.8.2)

Four flags: Z (zero), N (negative), C (carry), V (overflow). Only updated when `.F` modifier is used.

**Addition (ADD):**
- Z = 1 when result is 0
- N = 1 when result MSbit is 1 (bit 31 for normal, bit 15 for .SH)
- C = 1 when result doesn't fit in 32b/16b (carry out)
- V = 1 when signed overflow occurs

**Subtraction/Compare (SUB, CMP):**
- Z = 1 when result is 0
- N = 1 when result MSbit is 1
- C = 1 on borrow (when A < B, treating as unsigned)
- V = 1 when signed overflow occurs

**Logic (AND, OR, XOR, NOT):**
- Z = 1 when result is 0
- N = 1 when bit 31 is 1
- C = 0 (cleared)
- V = 0 (cleared)

**CMP/CMPI** always update Z and C flags (no `.F` needed — it's implicit).

### Modifiers

| Modifier | Meaning | Applies to |
|----------|---------|------------|
| `.F` | Update ZNCV flags | ADD, SUB, AND, OR, XOR, NOT |
| `.SX` | Sign-extend operands | ADD, SUB |
| `.SH` | Short (16b) operation | ADD, SUB |
| `.CD` | Clear destination (entire 16B register) before write | MOV, MOVI |

Modifiers are encoded as bool fields in the instruction union.

### Branch Conditions (Section 4.13.18)

11 condition codes for BR/BRI:

| Code | Mnemonic | Condition |
|------|----------|-----------|
| 0000 | EQ | Z = 1 |
| 0001 | NEQ | Z = 0 |
| 0010 | LT | N = 1 |
| 0011 | GT | N = 0 and Z = 0 |
| 0100 | GE | N = 0 |
| 0101 | LE | N = 1 or Z = 1 |
| 0110 | C | C = 1 |
| 0111 | NC | C = 0 |
| 1000 | V | V = 1 |
| 1001 | NV | V = 0 |
| 1010 | AL | Always (unconditional) |

BR takes target from a register (absolute). BRI takes target as immediate (relative to current PC).

BRBTST tests a single bit in a register word:
- BRBTSTSET: branch if bit is set
- BRBTSTCLR: branch if bit is clear

## File Structure

| File | Purpose |
|------|---------|
| `model/map/state.sail` | Extend existing file: add ZNCV flags, MAP PC, instruction memory, halted flag, init/helpers |
| `model/map/types.sail` | New: register index enum, word select, condition codes, instruction union |
| `model/map/decode.sail` | New: 64-bit binary encoding mappings |
| `model/map/insts.sail` | New: execute clauses for all instructions |
| `model/main.sail` | Extend: add MAP fetch-decode-execute loop, `$include` new files |

### Naming Conventions

MAP types/names use `M` or `map_` prefix to avoid collisions with parser (which uses `P`/`parser_`):
- Register index enum: `MR0..MR15, MRN`
- Instruction union: `minstr` with clauses like `MADD`, `MSUB`, `MMOV`, etc.
- State registers: `map_pc`, `map_halted`, `mflag_z`, `mflag_n`, `mflag_c`, `mflag_v`
- Functions: `map_step()`, `map_run()`, `map_init()`

### Existing model/map/state.sail

Already defines:
- `MAP : vector(14, bits128)` — register file (R0-R13)
- `read_mapreg(idx)` / `write_mapreg(idx, v)` — accessor functions
- `init_map()` — initialization

Needs extension:
- Expand register file to 16 entries (add R14, R15)
- R15 always reads as zero, writes discarded (null register behavior in accessors)
- Add word-select read/write helpers: `read_mapword(reg_idx, word_sel)` / `write_mapword(...)`
- Add ZNCV flag registers
- Add MAP PC and instruction memory
- Add `map_halted` flag

## Instruction Details

### NOP (4.13.51)
No operation. No fields.

### HALT (4.13.22)
End MAP execution. Sets `map_halted = true`. No fields.

### MOV, MOVI (4.13.11)
- **MOV**: Copy 4B word. `DestReg.W = SourceReg.W`. If `.CD`, clear entire 16B DestReg first.
- **MOVI**: Load immediate (up to 32 bits) into 4B word. If `.CD`, clear entire 16B DestReg first.

Fields:
- MOV: `(dest_reg, dest_word, src_reg, src_word, clear_dest)`
- MOVI: `(dest_reg, dest_word, immediate32, clear_dest)`

### ADD, ADDI (4.13.1)
- **ADD**: `Dest[N:0] = Source1[i1:j1] + Source2[i2:j2]`
- **ADDI**: `Dest[N:0] = Source1[i1:j1] + ImmediateValue`

Fields for ADD: `(dest_reg, dest_word, src1_reg, src1_word, src1_offset, src1_size, src2_reg, src2_word, src2_offset, src2_size, set_flags, sign_extend, short_mode)`

Fields for ADDI: `(dest_reg, dest_word, src1_reg, src1_word, src1_offset, src1_size, immediate16, set_flags, sign_extend, short_mode)`

Operand sizes: up to 4 bytes (32 bits). Result is 32 bits (or 16 bits with `.SH`).

### SUB, SUBI (4.13.2)
Same structure as ADD/ADDI but subtraction. `Dest[N:0] = Source1 - Source2`.

### CMP, CMPI (4.13.4)
Compare — like SUB but result is discarded, flags always updated (no `.F` needed).
- Z = 1 when equal, C = 1 when Source1 < Source2 (unsigned borrow).
- Operands are from 4B registers. Size: 1-32 bits.

Fields for CMP: `(src1_reg, src1_word, src1_offset, src2_reg, src2_word, src2_offset, size)`
Fields for CMPI: `(src1_reg, src1_word, src1_offset, immediate16, size)`

### AND, ANDI (4.13.5)
Bitwise AND. `Dest[Size-1:0] = Source1[i1:j1] & Source2[i2:j2]`. Only written bits are modified in dest; rest unchanged.

Fields for AND: `(dest_reg, dest_word, src1_reg, src1_word, src1_offset, src2_reg, src2_word, src2_offset, size, set_flags)`
Fields for ANDI: `(dest_reg, dest_word, src1_reg, src1_word, src1_offset, immediate16, size, set_flags)`

### OR, ORI (4.13.6)
Same structure as AND/ANDI but bitwise OR.

### XOR, XORI (4.13.7)
Same structure as AND/ANDI but bitwise XOR.

### NOT (4.13.8)
Bitwise negate. `Dest[Size-1:0] = ~Source[i:j]`. Single source operand.

Fields: `(dest_reg, dest_word, src_reg, src_word, src_offset, size, set_flags)`

### BR, BRI, BRBTST (4.13.18)
- **BR**: Branch to address in register if condition met. Address is absolute.
  Fields: `(condition, src_reg, src_word)`
- **BRI**: Branch to PC-relative immediate if condition met.
  Fields: `(condition, offset16)`
- **BRBTST**: Test bit in register word and branch.
  Fields: `(bit_test_cond, src_reg, src_word, bit_offset, target16)`

## Binary Encoding

64-bit fixed-width instruction word, same format as parser: 6-bit opcode at [63:58], fields packed MSB-first, zero-padded LSB.

### Opcode Assignments

| Opcode | Instruction | Field bits (est.) |
|--------|-------------|-------------------|
| 0 | NOP | 0 |
| 1 | HALT | 0 |
| 2 | MOV | 4+2+4+2+1 = 13 |
| 3 | MOVI | 4+2+32+1 = 39 |
| 4 | ADD | 4+2+4+2+5+5+4+2+5+5+1+1+1 = 41 |
| 5 | ADDI | 4+2+4+2+5+5+16+1+1+1 = 41 |
| 6 | SUB | 41 (same as ADD) |
| 7 | SUBI | 41 (same as ADDI) |
| 8 | CMP | 4+2+5+4+2+5+5 = 27 |
| 9 | CMPI | 4+2+5+16+5 = 32 |
| 10 | AND | 4+2+4+2+5+4+2+5+5+1 = 34 |
| 11 | ANDI | 4+2+4+2+5+16+5+1 = 39 |
| 12 | OR | 34 (same as AND) |
| 13 | ORI | 39 (same as ANDI) |
| 14 | XOR | 34 (same as AND) |
| 15 | XORI | 39 (same as ANDI) |
| 16 | NOT | 4+2+4+2+5+5+1 = 23 |
| 17 | BR | 4+4+2 = 10 |
| 18 | BRI | 4+16 = 20 |
| 19 | BRBTST | 1+4+2+5+16 = 28 |

All fit within 58 available field bits (64 - 6 opcode). Exact bit layouts will be defined during implementation, following the same conventions as the parser encoding.

## Testing

One test file per instruction group, mirroring the parser test structure:

| Test file | Instructions tested |
|-----------|-------------------|
| `test/map/test_nop.sail` | NOP |
| `test/map/test_halt.sail` | HALT |
| `test/map/test_mov.sail` | MOV, MOVI, .CD |
| `test/map/test_add.sail` | ADD, ADDI, .F, .SX, .SH |
| `test/map/test_sub.sail` | SUB, SUBI, .F, .SX, .SH |
| `test/map/test_cmp.sail` | CMP, CMPI, flag behavior |
| `test/map/test_and.sail` | AND, ANDI, .F |
| `test/map/test_or.sail` | OR, ORI, .F |
| `test/map/test_xor.sail` | XOR, XORI, NOT, .F |
| `test/map/test_br.sail` | BR, BRI, BRBTST, all condition codes |
| `test/map/test_program.sail` | Multi-instruction programs using MAP step/run loop |
| `test/map/test_encoding.sail` | Encoding round-trip tests |

Each test follows the established pattern: init state, execute instruction, assert results.

## Deferred Decisions

- **R14 debug register**: Virtual register for debug mode. Not modeled in this slice.
- **Dependency checker**: HW pipeline hazard detection. Irrelevant for sequential ISA-level model.
- **LFLAG/async**: No async instructions in this slice, so no LFLAG needed.
- **Pre-loading scheme (4.7)**: R7.0 with SMD bytes 0-3, R11-R13 with HDR data. Modeled as explicit initialization in tests; automatic pre-loading deferred to parser-MAP integration.
- **`.H` modifier on arithmetic**: Halts program after the operation. Straightforward to add later.
