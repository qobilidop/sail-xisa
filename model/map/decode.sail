
// MAP instruction encoding/decoding.
// 64-bit fixed-width instruction word. Same conventions as parser encoding.

// Sub-mapping: MAP register index <-> 4 bits.
mapping encdec_mregidx : mregidx <-> bits(4) = {
    MR0  <-> 0x0, MR1  <-> 0x1, MR2  <-> 0x2, MR3  <-> 0x3,
    MR4  <-> 0x4, MR5  <-> 0x5, MR6  <-> 0x6, MR7  <-> 0x7,
    MR8  <-> 0x8, MR9  <-> 0x9, MR10 <-> 0xA, MR11 <-> 0xB,
    MR12 <-> 0xC, MR13 <-> 0xD, MR14 <-> 0xE, MRN  <-> 0xF,
}

// Sub-mapping: MAP word select <-> 2 bits.
mapping encdec_mwordsel : mwordsel <-> bits(2) = {
    MW0 <-> 0b00, MW1 <-> 0b01, MW2 <-> 0b10, MW3 <-> 0b11,
}

// Sub-mapping: MAP branch condition code <-> 4 bits.
mapping encdec_mcond : mcond <-> bits(4) = {
    MCC_EQ  <-> 0x0, MCC_NEQ <-> 0x1, MCC_LT  <-> 0x2, MCC_GT  <-> 0x3,
    MCC_GE  <-> 0x4, MCC_LE  <-> 0x5, MCC_C   <-> 0x6, MCC_NC  <-> 0x7,
    MCC_V   <-> 0x8, MCC_NV  <-> 0x9, MCC_AL  <-> 0xA,
}

// Sub-mapping: MAP bit-test condition <-> 1 bit.
mapping encdec_mbtcond : mbtcond <-> bits(1) = {
    MBT_CLR <-> 0b0, MBT_SET <-> 0b1,
}

// Sub-mapping: bool <-> 1 bit (MAP-prefixed to avoid conflict with parser's encdec_bool).
mapping encdec_mbool : bool <-> bits(1) = {
    false <-> 0b0,
    true  <-> 0b1,
}

// Main instruction encoding: minstr <-> bits(64).
// 6-bit opcode at [63:58], fields packed MSB-first, zero-padded at LSB.
val mencdec : minstr <-> bits(64)
scattered mapping mencdec

// Opcode  0: NOP (0 field bits, 58 padding)
mapping clause mencdec = MNOP()
    <-> 0b000000 @ 0b00 : bits(2) @ 0x00000000000000 : bits(56)

// Opcode  1: HALT (0 field bits, 58 padding)
mapping clause mencdec = MHALT()
    <-> 0b000001 @ 0b00 : bits(2) @ 0x00000000000000 : bits(56)

// Opcode  2: MOV (rd4+rw2+rs4+sw2+cd1 = 13 field bits, 45 padding)
mapping clause mencdec = MMOV(rd, rw, rs, sw, cd)
    <-> 0b000010 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs) @ encdec_mwordsel(sw) @ encdec_mbool(cd) @ 0b0 : bits(1) @ 0x00000000000 : bits(44)

// Opcode  3: MOVI (rd4+rw2+imm32+cd1 = 39 field bits, 19 padding)
mapping clause mencdec = MMOVI(rd, rw, imm32, cd)
    <-> 0b000011 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ imm32 @ encdec_mbool(cd) @ 0b000 : bits(3) @ 0x0000 : bits(16)

// Opcode  4: ADD (rd4+rw2+rs14+sw12+s1off5+s1sz5+rs24+sw22+s2off5+s2sz5+f1+sx1+sh1 = 41, pad 17)
mapping clause mencdec = MADD(rd, rw, rs1, sw1, s1off, s1sz, rs2, sw2, s2off, s2sz, f, sx, sh)
    <-> 0b000100 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ s1sz @ encdec_mregidx(rs2) @ encdec_mwordsel(sw2) @ s2off @ s2sz @ encdec_mbool(f) @ encdec_mbool(sx) @ encdec_mbool(sh) @ 0b0 : bits(1) @ 0x0000 : bits(16)

// Opcode  5: ADDI (rd4+rw2+rs14+sw12+s1off5+s1sz5+imm16+f1+sx1+sh1 = 41, pad 17)
mapping clause mencdec = MADDI(rd, rw, rs1, sw1, s1off, s1sz, imm16, f, sx, sh)
    <-> 0b000101 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ s1sz @ imm16 @ encdec_mbool(f) @ encdec_mbool(sx) @ encdec_mbool(sh) @ 0b0 : bits(1) @ 0x0000 : bits(16)

// Opcode  6: SUB (same layout as ADD = 41, pad 17)
mapping clause mencdec = MSUB(rd, rw, rs1, sw1, s1off, s1sz, rs2, sw2, s2off, s2sz, f, sx, sh)
    <-> 0b000110 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ s1sz @ encdec_mregidx(rs2) @ encdec_mwordsel(sw2) @ s2off @ s2sz @ encdec_mbool(f) @ encdec_mbool(sx) @ encdec_mbool(sh) @ 0b0 : bits(1) @ 0x0000 : bits(16)

// Opcode  7: SUBI (same layout as ADDI = 41, pad 17)
mapping clause mencdec = MSUBI(rd, rw, rs1, sw1, s1off, s1sz, imm16, f, sx, sh)
    <-> 0b000111 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ s1sz @ imm16 @ encdec_mbool(f) @ encdec_mbool(sx) @ encdec_mbool(sh) @ 0b0 : bits(1) @ 0x0000 : bits(16)

// Opcode  8: CMP (rs14+sw12+s1off5+rs24+sw22+s2off5+sz5 = 27, pad 31)
mapping clause mencdec = MCMP(rs1, sw1, s1off, rs2, sw2, s2off, sz)
    <-> 0b001000 @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ encdec_mregidx(rs2) @ encdec_mwordsel(sw2) @ s2off @ sz @ 0b000 : bits(3) @ 0x0000000 : bits(28)

// Opcode  9: CMPI (rs14+sw12+s1off5+imm16+sz5 = 32, pad 26)
mapping clause mencdec = MCMPI(rs1, sw1, s1off, imm16, sz)
    <-> 0b001001 @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ imm16 @ sz @ 0b00 : bits(2) @ 0x000000 : bits(24)

// Opcode 10: AND (rd4+rw2+rs14+sw12+s1off5+rs24+sw22+s2off5+sz5+f1 = 34, pad 24)
mapping clause mencdec = MAND(rd, rw, rs1, sw1, s1off, rs2, sw2, s2off, sz, f)
    <-> 0b001010 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ encdec_mregidx(rs2) @ encdec_mwordsel(sw2) @ s2off @ sz @ encdec_mbool(f) @ 0x000000 : bits(24)

// Opcode 11: ANDI (rd4+rw2+rs14+sw12+s1off5+imm16+sz5+f1 = 39, pad 19)
mapping clause mencdec = MANDI(rd, rw, rs1, sw1, s1off, imm16, sz, f)
    <-> 0b001011 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ imm16 @ sz @ encdec_mbool(f) @ 0b000 : bits(3) @ 0x0000 : bits(16)

// Opcode 12: OR (same layout as AND = 34, pad 24)
mapping clause mencdec = MOR(rd, rw, rs1, sw1, s1off, rs2, sw2, s2off, sz, f)
    <-> 0b001100 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ encdec_mregidx(rs2) @ encdec_mwordsel(sw2) @ s2off @ sz @ encdec_mbool(f) @ 0x000000 : bits(24)

// Opcode 13: ORI (same layout as ANDI = 39, pad 19)
mapping clause mencdec = MORI(rd, rw, rs1, sw1, s1off, imm16, sz, f)
    <-> 0b001101 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ imm16 @ sz @ encdec_mbool(f) @ 0b000 : bits(3) @ 0x0000 : bits(16)

// Opcode 14: XOR (same layout as AND = 34, pad 24)
mapping clause mencdec = MXOR(rd, rw, rs1, sw1, s1off, rs2, sw2, s2off, sz, f)
    <-> 0b001110 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ encdec_mregidx(rs2) @ encdec_mwordsel(sw2) @ s2off @ sz @ encdec_mbool(f) @ 0x000000 : bits(24)

// Opcode 15: XORI (same layout as ANDI = 39, pad 19)
mapping clause mencdec = MXORI(rd, rw, rs1, sw1, s1off, imm16, sz, f)
    <-> 0b001111 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs1) @ encdec_mwordsel(sw1) @ s1off @ imm16 @ sz @ encdec_mbool(f) @ 0b000 : bits(3) @ 0x0000 : bits(16)

// Opcode 16: NOT (rd4+rw2+rs4+sw2+soff5+sz5+f1 = 23, pad 35)
mapping clause mencdec = MNOT(rd, rw, rs, sw, soff, sz, f)
    <-> 0b010000 @ encdec_mregidx(rd) @ encdec_mwordsel(rw) @ encdec_mregidx(rs) @ encdec_mwordsel(sw) @ soff @ sz @ encdec_mbool(f) @ 0b000 : bits(3) @ 0x00000000 : bits(32)

// Opcode 17: BR (cc4+rs4+sw2 = 10, pad 48)
mapping clause mencdec = MBR(cc, rs, sw)
    <-> 0b010001 @ encdec_mcond(cc) @ encdec_mregidx(rs) @ encdec_mwordsel(sw) @ 0x000000000000 : bits(48)

// Opcode 18: BRI (cc4+offset16 = 20, pad 38)
mapping clause mencdec = MBRI(cc, offset16)
    <-> 0b010010 @ encdec_mcond(cc) @ offset16 @ 0b00 : bits(2) @ 0x000000000 : bits(36)

// Opcode 19: BRBTST (btcc1+rs4+sw2+boff5+target16 = 28, pad 30)
mapping clause mencdec = MBRBTST(btcc, rs, sw, boff, target16)
    <-> 0b010011 @ encdec_mbtcond(btcc) @ encdec_mregidx(rs) @ encdec_mwordsel(sw) @ boff @ target16 @ 0b00 : bits(2) @ 0x0000000 : bits(28)

end mencdec

// Encode a minstr to bits(64).
val encode_minstr : minstr -> bits(64)
function encode_minstr(instr) = mencdec(instr)

// Decode bits(64) to minstr.
val decode_minstr : bits(64) -> minstr
function decode_minstr(bv) = mencdec(bv)
