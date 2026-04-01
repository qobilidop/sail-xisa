# ST, STI Design Spec

## Overview

ST and STI are store-to-struct instructions (XISA spec section 3.12.10). They write data into Struct-0, a 128-bit register that holds the Standard Metadata (SMD) passed from the parser to the MAP.

- **ST**: Copy a bit-field from a parser register into Struct-0. Supports .H (halt after).
- **STI**: Store an immediate value (up to 16 bits) into Struct-0.

Reference: [XISA white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf), section 3.12.10.

## Struct-0 Model

A single 128-bit register representing the Standard Metadata (SMD):

- `register struct0 : bits128`
- Initialized to zero in `parser_init()`
- Bits numbered [0,...,127] with bit 0 = LSB, matching parser register convention

**Assumption:** The white paper notes bits 6-31 are HW-controlled. We model the full 128-bit register with no write restrictions — the HW-controlled region is a hardware detail that doesn't affect instruction semantics.

## Instruction Semantics

### ST (3.12.10)

**Syntax:** `ST[.H] Rs, SrcOffsetBits, StructOffsetBits, SizeBits`

**Operation:** `Struct0[l:k] = SrcReg[i:j]`

- `j` = SrcOffsetBits (range 0-127)
- `i` = SrcOffsetBits + SizeBits
- `l` = StructOffsetBits (range 0-5 and 32-127, but not enforced in model)
- `k` = StructOffsetBits + SizeBits
- SizeBits: range 1-128
- If .H: halt after the store

### STI (3.12.10)

**Syntax:** `STI ImmediateValue, StructOffsetBits, SizeBits`

**Operation:** `Struct0[l:k] = ImmediateValue`

- `l` = StructOffsetBits (range 0-127)
- `k` = StructOffsetBits + SizeBits
- SizeBits: range 1-16
- ImmediateValue: max 16-bit value

## Deferred

- HW-controlled bits 6-31 restriction (hardware detail, not instruction semantics)
- Full PMEM model with multiple structures (only Struct-0 needed for parser)

## Union Clauses

```sail
// ST: Store register sub-field into Struct-0.
// Fields: (src_reg, src_offset_bits, struct_offset_bits, size_bits, halt)
union clause pinstr = PST : (pregidx, bits8, bits8, bits8, bool)

// STI: Store immediate value into Struct-0.
// Fields: (immediate_value, struct_offset_bits, size_bits)
union clause pinstr = PSTI : (bits16, bits8, bits8)
```

## Execute Clauses

```sail
// ST: Struct0[struct_off + size - 1 : struct_off] = SrcReg[src_off + size - 1 : src_off]
function clause execute(PST(rs, src_offset_bits, struct_offset_bits, size_bits, halt)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let doff : nat = unsigned(struct_offset_bits);
    let sz : nat = unsigned(size_bits);
    let extracted = extract_bits(src_val, soff, sz);
    struct0 = insert_bits(struct0, doff, sz, extracted);
    if halt then {
        parser_halted = true;
        RETIRE_HALT
    } else {
        RETIRE_SUCCESS
    }
}

// STI: Struct0[struct_off + size - 1 : struct_off] = ImmediateValue[size-1:0]
function clause execute(PSTI(immediate, struct_offset_bits, size_bits)) = {
    let doff : nat = unsigned(struct_offset_bits);
    let sz : nat = unsigned(size_bits);
    let imm_128 : bits128 = sail_zero_extend(immediate, 128);
    struct0 = insert_bits(struct0, doff, sz, imm_128);
    RETIRE_SUCCESS
}
```

## Tests (test/parser/test_st.sail)

1. **ST basic**: R0[7:0]=0xAB, ST(R0, 0, 0, 8, false) -> struct0[7:0]=0xAB
2. **ST with offsets**: R0[15:8]=0xCD, ST(R0, 8, 32, 8, false) -> struct0[39:32]=0xCD
3. **ST with halt**: ST(R0, 0, 0, 8, true) -> stores and returns RETIRE_HALT
4. **ST 16-bit copy**: R0[15:0]=0x1234, ST(R0, 0, 0, 16, false) -> struct0[15:0]=0x1234
5. **STI basic**: STI(0x00AB, 0, 8) -> struct0[7:0]=0xAB
6. **STI at offset**: STI(0x00FF, 32, 8) -> struct0[39:32]=0xFF
7. **Program-level**: EXT packet data into R0, ST into struct0, verify struct0 contents
