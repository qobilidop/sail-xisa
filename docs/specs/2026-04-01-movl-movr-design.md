# MOVL/MOVR Design Spec

## Overview

MOVL, MOVLI, MOVLII, MOVR, MOVRI, MOVRII are parser instructions that move data between register sub-fields with a **dynamically computed destination offset** (XISA spec section 3.12.12). They form two families: "left" (add to offset) and "right" (subtract from offset), each with three offset-computation variants.

Reference: [XISA white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf), section 3.12.12.

## Instruction Families

All 6 variants perform: `DestReg[m:k] = SrcReg[i1:j1]` — copy a bit-field from source to destination. They differ only in how `k` (destination bit offset) and `m` (top bit) are computed.

### Left family (offset increases)

| Variant | k (dest offset) | m (top bit) | Source data |
|---------|----------------|-------------|-------------|
| MOVL | SrcReg2[i2:j2] + OffsBits1 | k + SizeBits1 - 1 | SrcReg1[i1:j1] |
| MOVLI | ImmValue + OffsBits | k + SizeBits - 1 | SrcReg[i:j] |
| MOVLII | SrcReg[i:j] (register is offset) | k + ImmValueSize | ImmValue[n-1:0] |

Overflow: if m > 63 (MOVL/MOVR use 64-bit range) or m > 127, MSbits of source data are truncated.

### Right family (offset decreases)

| Variant | k (dest offset) | m (top bit) | Source data |
|---------|----------------|-------------|-------------|
| MOVR | OffsBits1 - SrcReg2[i2:j2] | k + SizeBits1 - 1 | SrcReg1[i1:j1] |
| MOVRI | OffsBits - ImmValue | k + SizeBits - 1 | SrcReg[i:j] |
| MOVRII | ImmValueSize - SrcReg[i:j] | k + ImmValueSize (?) | ImmValue[n-1:0] |

Underflow: if k < 0, LSbits of source data are truncated (k clamped to 0).

### .CD modifier

All 6 variants support `.CD` (clear destination): zero the destination register before writing. Modeled as a bool field.

## Instruction Semantics

### MOVL (3.12.12)

**Syntax:** `MOVL[.CD] Rd, Rs1, OffsBits1, SizeBits1, Rs2, OffsBits2, SizeBits2`

**Operation:** `DestReg[m:k] = SrcReg1[i1:j1]`
- `k = SrcReg2[i2:j2] + OffsBits1` (dynamic offset from register + static base)
- `m = k + SizeBits1 - 1`, clamped to 63 max
- `j1, j2` = OffsBits1, OffsBits2; range 0-63
- `i1` = OffsBits1 + SizeBits1; range 1-32
- `i2` = OffsBits2 + SizeBits2; range 1-8

### MOVLI (3.12.12)

**Syntax:** `MOVLI[.CD] Rd, Rs, OffsBits, SizeBits, ImmVal`

**Operation:** `DestReg[m:k] = SrcReg[i1:j1]`
- `k = ImmValue + OffsBits`
- `m = k + SizeBits - 1`
- `j` = OffsBits; range 0-127
- `i` = OffsBits + SizeBits; range 1-32
- ImmValue: range 0-127

### MOVLII (3.12.12)

**Syntax:** `MOVLII[.CD] Rd, Rs, OffsBits, SizeBits, ImmVal, ImmValSize`

**Operation:** `DestReg[m-1:k] = ImmValue[n-1:0]`
- `k = SrcReg[i:j]` (register sub-field is the offset)
- `m = k + ImmValueSize`
- `j` = OffsBits; range 0-127
- `i` = OffsBits + SizeBits; range 1-7
- ImmValue: range 0-127
- ImmValueSize: range 1-7 bits

### MOVR (3.12.12)

**Syntax:** `MOVR[.CD] Rd, Rs1, OffsBits1, SizeBits1, Rs2, OffsBits2, SizeBits2`

**Operation:** `DestReg[m:k] = SrcReg1[i1:j1]`
- `k = OffsBits1 - SrcReg2[i2:j2]` (static base - dynamic offset)
- `m = k + SizeBits1 - 1`; if underflow (k < 0), k clamped to 0 and LSbits truncated
- Same field ranges as MOVL

### MOVRI (3.12.12)

**Syntax:** `MOVRI[.CD] Rd, Rs, OffsBits, SizeBits, ImmVal`

**Operation:** `DestReg[m:k] = SrcReg[i1:j1]`
- `k = OffsBits - ImmValue`
- `m = k + SizeBits - 1`
- Same field ranges as MOVLI

### MOVRII (3.12.12)

**Syntax:** `MOVRII[.CD] Rd, Rs, OffsBits, SizeBits, ImmVal, ImmValSize`

**Operation:** `DestReg[m-1:0] = ImmValue[n-1:k]`
- `k = SrcReg[i:j]` (register sub-field)
- `n` = ImmValueSize
- `m = ImmValueSize - SrcReg[i:j]`
- Same field ranges as MOVLII

## Union Clauses

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

## Deferred

- Overflow/underflow truncation: The spec describes MSbit/LSbit truncation when the computed offset pushes data beyond register bounds. For the initial implementation, we assume operands are in-range and use `insert_bits` which naturally handles the bit manipulation. Full truncation semantics can be added later if needed for compliance testing.

## Tests (test/parser/test_movl_movr.sail)

### MOVL tests
1. **MOVL basic**: R0[7:0]=0xAB, R1[2:0]=4 → MOVL(R2, R0, 0, 8, R1, 0, 3, false) → R2 at offset 4, R2[11:4]=0xAB
2. **MOVL with .CD**: Same but clear_dest=true → only the moved bits are set

### MOVLI test
3. **MOVLI basic**: R0[7:0]=0xCD, MOVLI(R1, R0, 0, 8, 16, false) → R1 at offset 16, R1[23:16]=0xCD

### MOVLII test
4. **MOVLII basic**: R0[2:0]=8, MOVLII(R1, R0, 0, 3, 0x1F, 5, false) → R1 at offset 8, R1[12:8]=0x1F

### MOVR tests
5. **MOVR basic**: R0[7:0]=0xAB, R1[2:0]=4 → MOVR(R2, R0, 0, 8, R1, 0, 3, false) → offset = 0-4 clamped to 0 (if offs1=0), or use offs1=32 → R2 at offset 28, R2[35:28]=0xAB
6. Revised: R0[7:0]=0xAB, R1[2:0]=4, offs1=32 → MOVR(R2, R0, 32, 8, R1, 0, 3, false) → k=32-4=28 → R2[35:28]=0xAB

### MOVRI test
7. **MOVRI basic**: R0[7:0]=0xEF, MOVRI(R1, R0, 32, 8, 16, false) → k=32-16=16 → R1[23:16]=0xEF

### MOVRII test
8. **MOVRII basic**: R0[2:0]=2, MOVRII(R1, R0, 0, 3, 0x1F, 5, false) → k=SrcReg=2, m=5-2=3 → R1[2:0]=ImmValue[4:2]=0x07

### Program-level test
9. **Dynamic placement**: EXT protocol type from packet, use value as offset for MOVL to place a marker at a data-dependent position
