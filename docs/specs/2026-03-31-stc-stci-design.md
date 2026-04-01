# STC, STCI Design Spec

## Overview

STC and STCI are cursor manipulation instructions (XISA spec section 3.12.8). They increment the parser cursor position in the packet header buffer.

- **STC**: Increment cursor by a value derived from a register sub-field, with optional additional increment and left-shift.
- **STCI**: Increment cursor by an immediate value.

Both instructions also support a JumpMode operand (transition table jump) and .SCSM/.ECSM checksum modifiers, which are deferred in this iteration.

Reference: [XISA white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf), section 3.12.8.

## Instruction Semantics

### STC

**Syntax:** `STC Rs, SrcOffset, SrcSize, SizeShift, AdditionalIncr, JumpMode`

**Operation:** `Cursor += ((SrcReg[i:j] + AdditionalIncr) << SrcShift)`

- `j` = SrcOffsetBits (range 0-127)
- `i` = SrcOffsetBits + SrcSizeBits (extracted field is 1-8 bits)
- SrcShift: range 0-7
- AdditionalIncr: range 0-3

The extracted value from the source register is zero-extended, added to AdditionalIncr, left-shifted by SrcShift, and added to the current cursor position. Arithmetic wraps at 8 bits (cursor is `bits8`).

### STCI

**Syntax:** `STCI IncrValue, JumpMode`

**Operation:** `Cursor += IncrValue`

- IncrValue: range 1-256

The cursor is incremented by the immediate value. Since the range goes up to 256, IncrValue is stored as `bits16`.

## Deferred

- **JumpMode**: Requires transition table model (deferred to step 6 in roadmap). Modeled as if JumpMode=0 (no jump).
- **.SCSM/.ECSM**: Checksum start/end modifiers require hardware checksum state not yet modeled.

## Union Clauses

```sail
// STC: Set cursor from register sub-field.
// Fields: (src_reg, src_offset_bits, src_size_bits, src_shift, additional_incr)
union clause pinstr = PSTC : (pregidx, bits8, bits8, bits8, bits8)

// STCI: Set cursor from immediate value.
// Fields: (incr_value)
union clause pinstr = PSTCI : bits16
```

## Execute Clauses

```sail
// STC: Cursor += ((SrcReg[offset+size-1:offset] + AdditionalIncr) << SrcShift)
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

// STCI: Cursor += IncrValue
function clause execute(PSTCI(incr_value)) = {
    let incr_8 : bits8 = sail_mask(8, incr_value);
    pcursor = pcursor + incr_8;
    RETIRE_SUCCESS
}
```

Note: All arithmetic is done in `bits8` to match the cursor width. `sail_mask(8, ...)` truncates wider values to 8 bits. For STCI, the value 256 wraps to 0x00 on truncation (incrementing by 256 on an 8-bit cursor is a no-op).

## Tests (test/parser/test-stc.sail)

1. **STCI basic**: cursor=0, STCI(14) -> cursor=14
2. **STCI from non-zero cursor**: cursor=10, STCI(4) -> cursor=14
3. **STC basic**: R0[7:0]=0x0A, STC(R0, 0, 8, 0, 0) -> cursor += 10
4. **STC with shift**: R0[7:0]=0x03, STC(R0, 0, 8, 2, 0) -> cursor += 12 (3 << 2)
5. **STC with additional_incr**: R0[7:0]=0x03, STC(R0, 0, 8, 0, 2) -> cursor += 5 (3 + 2)
6. **STC with shift and additional_incr**: R0[7:0]=0x02, STC(R0, 0, 8, 1, 1) -> cursor += 6 ((2+1) << 1)
7. **STC with PRN**: STC(PRN, 0, 8, 2, 1) -> cursor += 4 ((0+1) << 2)
8. **Program-level**: EXT to read bytes, STCI to advance cursor, EXT again at new position
