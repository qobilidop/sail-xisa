# EXTMAP, MOVMAP Design Spec

## Overview

EXTMAP and MOVMAP are parser instructions that write into MAP registers (XISA spec sections 3.12.4 and 3.12.5). They allow the parser to pre-load MAP registers before handing off to a MAP thread (see section 4.7).

- **EXTMAP**: Extract data from the packet header buffer directly into a MAP register. Similar to EXT but targeting MAP registers instead of parser registers.
- **MOVMAP**: Move data from a parser register into a MAP register. Similar to MOV but targeting MAP registers.

Reference: [XISA white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf), sections 3.12.4, 3.12.5, 4.2, 4.7.

## MAP Register File Model

The MAP has 14 registers (R0-R13), each 128 bits (section 4.2). From the parser's perspective, these are write-only targets for EXTMAP and MOVMAP. The MAP register file is MAP-owned state that the parser has cross-domain write access to.

The register file lives in `model/map/state.sail`:

- `register MAP : vector(14, bits128)`
- `write_mapreg(idx, val)` / `read_mapreg(idx)` helpers
- Initialized to zero (section 4.7: MAP registers are initialized to 0 for each new packet)
- MAP register init is called from `parser_init()`

**Architectural note:** Section 4.7 describes HW pre-loading of R7.0 (SMD bytes 0-3) and R11-R13 (HDR data) after parsing completes. We don't model this HW pre-loading step; we only model the parser's ability to write MAP registers via EXTMAP/MOVMAP.

## Instruction Semantics

### EXTMAP (3.12.4)

**Syntax:** `EXTMAP[.PR] MAPRd, DestOffsetBits, PacketOffsetBits, SizeBits`

**Operation:** `MAPReg[i-1:j] = Packet[l:k-1]`

- **MAPReg**: MAP register number; range 0-13.
- **j** = DestOffsetBits; range 0-127.
- **i** = DestOffsetBits + SizeBits; range 1-128.
- **l** = PacketOffsetBits (offset from current cursor position); range 0-511.
- **k** = PacketOffsetBits + SizeBits; range 1-128.

The packet extraction logic is identical to EXT: big-endian byte accumulation from cursor-relative bit offset, then shift/mask to extract the field.

### MOVMAP (3.12.5)

**Syntax:** `MOVMAP[.HDR] MAPRd, DestOffsetBits, SrcReg, SrcOffsetBits, SizeBits`

**Operation:** `MAPReg[di-1:dj] = SrcReg[si-1:sj]`

- **MAPReg**: MAP register number; range 0-13.
- **SrcReg**: Parser register (R0-R3).
- **dj** = DestOffsetBits; range 0-127.
- **di** = DestOffsetBits + SizeBits; range 1-128.
- **sj** = SrcOffsetBits; range 0-127.
- **si** = SrcOffsetBits + SizeBits; range 1-128.

## Deferred

- **EXTMAP .PR modifier**: Appends 1 as MSbit to the extracted field. Deferred for simplicity.
- **EXTMAP .SCSM/.ECSM**: Checksum accelerator modifiers. Deferred (requires checksum model).
- **MOVMAP .HDR modifier**: Selects parser result registers (HDR.PRESENT, HDR.OFFSET0/1, SMD first 4 bytes) as source instead of parser registers. Tied to the reparse flow (section 3.9). Deferred.

## Union Clauses

```sail
// EXTMAP: Extract data from packet into a MAP register.
// Fields: (map_reg_idx, dest_offset_bits, packet_offset_bits, size_bits)
union clause pinstr = PEXTMAP : (bits4, bits8, bits16, bits8)

// MOVMAP: Move data from a parser register into a MAP register.
// Fields: (map_reg_idx, dest_offset_bits, src_reg, src_offset_bits, size_bits)
union clause pinstr = PMOVMAP : (bits4, bits8, pregidx, bits8, bits8)
```

## Execute Clauses

```sail
// EXTMAP: MAPReg[dest_off + size - 1 : dest_off] = Packet[cursor*8 + pkt_off + size - 1 : cursor*8 + pkt_off]
function clause execute(PEXTMAP(map_idx, dest_offset, pkt_offset_bits, size_bits)) = {
    let midx : int = unsigned(map_idx);
    let doff = unsigned(dest_offset);
    let soff = unsigned(pkt_offset_bits);
    let sz = unsigned(size_bits);
    let cursor_bit_offset = unsigned(pcursor) * 8;
    let packet_bit_offset = cursor_bit_offset + soff;

    // Packet extraction logic (same as EXT)
    let pbo_bv : bits(20) = get_slice_int(20, packet_bit_offset, 0);
    let start_byte = unsigned(sail_shiftright(pbo_bv, 3));
    let bit_in_byte = unsigned(pbo_bv & 0x00007);

    let sum_bv : bits(20) = get_slice_int(20, bit_in_byte + sz + 7, 0);
    let bytes_needed = unsigned(sail_shiftright(sum_bv, 3));

    var acc : bits128 = sail_zeros(128);
    var i : int = 0;
    while i < bytes_needed do {
        let byte_idx : int = start_byte + i;
        let byte_val : bits128 = sail_zero_extend(read_packet_byte(byte_idx), 128);
        acc = acc | sail_shiftleft(byte_val, 8 * (bytes_needed - 1 - i));
        i = i + 1
    };

    let shift_amount : int = bytes_needed * 8 - bit_in_byte - sz;
    let extracted : bits128 = sail_shiftright(acc, shift_amount) & sail_mask(128, sail_ones(sz));

    // Write to MAP register
    let dst_val = read_mapreg(midx);
    let result = insert_bits(dst_val, doff, sz, extracted);
    write_mapreg(midx, result);
    RETIRE_SUCCESS
}

// MOVMAP: MAPReg[dest_off + size - 1 : dest_off] = SrcReg[src_off + size - 1 : src_off]
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

## Tests (test/parser/test_extmap_movmap.sail)

### EXTMAP tests
1. **Basic extract**: cursor=0, packet byte 0xAB, EXTMAP(MAP0, 0, 0, 8) -> MAP0[7:0]=0xAB
2. **Extract with dest offset**: EXTMAP(MAP0, 32, 0, 8) -> MAP0[39:32]=0xAB
3. **Extract with packet offset**: EXTMAP(MAP0, 0, 16, 8) -> reads byte at cursor bit 16
4. **Multi-byte extract**: EXTMAP(MAP1, 0, 0, 16) -> 16-bit value from packet into MAP1

### MOVMAP tests
5. **Basic move**: R0[7:0]=0xCD, MOVMAP(MAP0, 0, R0, 0, 8) -> MAP0[7:0]=0xCD
6. **Move with offsets**: R1[15:8]=0xEF, MOVMAP(MAP2, 16, R1, 8, 8) -> MAP2[23:16]=0xEF
7. **Different MAP registers**: verify writes to MAP regs 0 and 13

### Program-level test
8. **Combined**: EXT packet data into R0, MOVMAP from R0 into MAP0, EXTMAP packet data directly into MAP1, verify both MAP registers
