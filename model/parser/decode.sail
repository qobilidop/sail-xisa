
// Parser instruction encoding/decoding.
// 64-bit fixed-width instruction word. See docs/specs/2026-04-01-binary-encoding-design.md.

// Sub-mapping: parser register index <-> 3 bits.
mapping encdec_pregidx : pregidx <-> bits(3) = {
    PR0 <-> 0b000,
    PR1 <-> 0b001,
    PR2 <-> 0b010,
    PR3 <-> 0b011,
    PRN <-> 0b100,
}

// Sub-mapping: branch condition code <-> 3 bits.
mapping encdec_pcond : pcond <-> bits(3) = {
    PCC_EQ  <-> 0b000,
    PCC_NEQ <-> 0b001,
    PCC_LT  <-> 0b010,
    PCC_GT  <-> 0b011,
    PCC_GE  <-> 0b100,
    PCC_LE  <-> 0b101,
    PCC_AL  <-> 0b110,
}

// Sub-mapping: bit-test condition <-> 1 bit.
mapping encdec_pbtcond : pbtcond <-> bits(1) = {
    PBT_CLR <-> 0b0,
    PBT_SET <-> 0b1,
}

// Sub-mapping: bool <-> 1 bit.
mapping encdec_bool : bool <-> bits(1) = {
    false <-> 0b0,
    true  <-> 0b1,
}

// Main instruction encoding: pinstr <-> bits(64).
// 6-bit opcode at [63:58], fields packed MSB-first, zero-padded at LSB.
val encdec : pinstr <-> bits(64)
scattered mapping encdec

// Opcode  0: NOP (0 field bits, 58 padding)
mapping clause encdec = PNOP()
    <-> 0b000000 @ 0b00 : bits(2) @ 0x00000000000000 : bits(56)

// Opcode  1: HALT (1 field bit, 57 padding)
mapping clause encdec = PHALT(drop)
    <-> 0b000001 @ encdec_bool(drop) @ 0b0 : bits(1) @ 0x00000000000000 : bits(56)

// Opcode  2: NXTP (3+8+8 = 19 field bits, 39 padding)
mapping clause encdec = PNXTP(rs, soff, sz)
    <-> 0b000010 @ encdec_pregidx(rs) @ soff @ sz @ 0b000 : bits(3) @ 0x000000000 : bits(36)

// Opcode  3: PSEEK (3+8+3+8+8+8 = 38 field bits, 20 padding)
mapping clause encdec = PPSEEK(rd, doff, rs, soff, sz, cid)
    <-> 0b000011 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs) @ soff @ sz @ cid @ 0x00000 : bits(20)

// Opcode  4: PSEEKNXTP (3+8+3+8+8+8 = 38 field bits, 20 padding)
mapping clause encdec = PPSEEKNXTP(rd, doff, rs, soff, sz, cid)
    <-> 0b000100 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs) @ soff @ sz @ cid @ 0x00000 : bits(20)

// Opcode  5: EXT (3+8+16+8+1 = 36 field bits, 22 padding)
mapping clause encdec = PEXT(rd, doff, soff, sz, cd)
    <-> 0b000101 @ encdec_pregidx(rd) @ doff @ soff @ sz @ encdec_bool(cd) @ 0b00 : bits(2) @ 0x00000 : bits(20)

// Opcode  6: EXTNXTP (3+16+8+1 = 28 field bits, 30 padding)
mapping clause encdec = PEXTNXTP(rd, soff, sz, cd)
    <-> 0b000110 @ encdec_pregidx(rd) @ soff @ sz @ encdec_bool(cd) @ 0b00 : bits(2) @ 0x0000000 : bits(28)

// Opcode  7: EXTMAP (4+8+16+8 = 36 field bits, 22 padding)
mapping clause encdec = PEXTMAP(midx, doff, poff, sz)
    <-> 0b000111 @ midx @ doff @ poff @ sz @ 0b00 : bits(2) @ 0x00000 : bits(20)

// Opcode  8: MOVMAP (4+8+3+8+8 = 31 field bits, 27 padding)
mapping clause encdec = PMOVMAP(midx, doff, rs, soff, sz)
    <-> 0b001000 @ midx @ doff @ encdec_pregidx(rs) @ soff @ sz @ 0b000 : bits(3) @ 0x000000 : bits(24)

// Opcode  9: CNCTBY (3+8+3+8+8+3+8+8 = 49 field bits, 9 padding)
mapping clause encdec = PCNCTBY(rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz)
    <-> 0b001001 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ s1sz @ encdec_pregidx(rs2) @ s2off @ s2sz @ 0b0 : bits(1) @ 0x00 : bits(8)

// Opcode 10: CNCTBI (3+8+3+8+8+3+8+8 = 49 field bits, 9 padding)
mapping clause encdec = PCNCTBI(rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz)
    <-> 0b001010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ s1sz @ encdec_pregidx(rs2) @ s2off @ s2sz @ 0b0 : bits(1) @ 0x00 : bits(8)

// Opcode 11: STH (8+8+1 = 17 field bits, 41 padding)
mapping clause encdec = PSTH(pid, oid, halt)
    <-> 0b001011 @ pid @ oid @ encdec_bool(halt) @ 0b0 : bits(1) @ 0x0000000000 : bits(40)

// Opcode 12: STC (3+8+8+8+8 = 35 field bits, 23 padding)
mapping clause encdec = PSTC(rs, soff, ssz, shift, incr)
    <-> 0b001100 @ encdec_pregidx(rs) @ soff @ ssz @ shift @ incr @ 0b000 : bits(3) @ 0x00000 : bits(20)

// Opcode 13: STCI (16 field bits, 42 padding)
mapping clause encdec = PSTCI(incr)
    <-> 0b001101 @ incr @ 0b00 : bits(2) @ 0x0000000000 : bits(40)

// Opcode 14: STCH (16+8+8+1 = 33 field bits, 25 padding)
mapping clause encdec = PSTCH(incr, pid, oid, halt)
    <-> 0b001110 @ incr @ pid @ oid @ encdec_bool(halt) @ 0b0 : bits(1) @ 0x000000 : bits(24)

// Opcode 15: STHC (16+8+8 = 32 field bits, 26 padding)
mapping clause encdec = PSTHC(incr, pid, oid)
    <-> 0b001111 @ incr @ pid @ oid @ 0b00 : bits(2) @ 0x000000 : bits(24)

// Opcode 16: ST (3+8+8+8+1 = 28 field bits, 30 padding)
mapping clause encdec = PST(rs, soff, doff, sz, halt)
    <-> 0b010000 @ encdec_pregidx(rs) @ soff @ doff @ sz @ encdec_bool(halt) @ 0b00 : bits(2) @ 0x0000000 : bits(28)

// Opcode 17: STI (16+8+8 = 32 field bits, 26 padding)
mapping clause encdec = PSTI(imm, doff, sz)
    <-> 0b010001 @ imm @ doff @ sz @ 0b00 : bits(2) @ 0x000000 : bits(24)

// Opcode 18: MOV (3+8+3+8+8 = 30 field bits, 28 padding)
mapping clause encdec = PMOV(rd, doff, rs, soff, sz)
    <-> 0b010010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs) @ soff @ sz @ 0x0000000 : bits(28)

// Opcode 19: MOVI (3+8+16+8 = 35 field bits, 23 padding)
mapping clause encdec = PMOVI(rd, doff, imm, sz)
    <-> 0b010011 @ encdec_pregidx(rd) @ doff @ imm @ sz @ 0b000 : bits(3) @ 0x00000 : bits(20)

// Opcode 20: MOVL (3+3+8+8+3+8+8+1 = 42 field bits, 16 padding)
mapping clause encdec = PMOVL(rd, rs1, o1, sz1, rs2, o2, sz2, cd)
    <-> 0b010100 @ encdec_pregidx(rd) @ encdec_pregidx(rs1) @ o1 @ sz1 @ encdec_pregidx(rs2) @ o2 @ sz2 @ encdec_bool(cd) @ 0x0000 : bits(16)

// Opcode 21: MOVLI (3+3+8+8+8+1 = 31 field bits, 27 padding)
mapping clause encdec = PMOVLI(rd, rs, off, sz, imm, cd)
    <-> 0b010101 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ off @ sz @ imm @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x000000 : bits(24)

// Opcode 22: MOVLII (3+3+8+8+8+8+1 = 39 field bits, 19 padding)
mapping clause encdec = PMOVLII(rd, rs, off, sz, imm, isz, cd)
    <-> 0b010110 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ off @ sz @ imm @ isz @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x0000 : bits(16)

// Opcode 23: MOVR (3+3+8+8+3+8+8+1 = 42 field bits, 16 padding)
mapping clause encdec = PMOVR(rd, rs1, o1, sz1, rs2, o2, sz2, cd)
    <-> 0b010111 @ encdec_pregidx(rd) @ encdec_pregidx(rs1) @ o1 @ sz1 @ encdec_pregidx(rs2) @ o2 @ sz2 @ encdec_bool(cd) @ 0x0000 : bits(16)

// Opcode 24: MOVRI (3+3+8+8+8+1 = 31 field bits, 27 padding)
mapping clause encdec = PMOVRI(rd, rs, off, sz, imm, cd)
    <-> 0b011000 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ off @ sz @ imm @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x000000 : bits(24)

// Opcode 25: MOVRII (3+3+8+8+8+8+1 = 39 field bits, 19 padding)
mapping clause encdec = PMOVRII(rd, rs, off, sz, imm, isz, cd)
    <-> 0b011001 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ off @ sz @ imm @ isz @ encdec_bool(cd) @ 0b000 : bits(3) @ 0x0000 : bits(16)

// Opcode 26: ADD (3+8+3+8+3+8+8 = 41 field bits, 17 padding)
mapping clause encdec = PADD(rd, doff, rs1, s1off, rs2, s2off, sz)
    <-> 0b011010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ 0b0 : bits(1) @ 0x0000 : bits(16)

// Opcode 27: ADDI (3+3+16+8 = 30 field bits, 28 padding)
mapping clause encdec = PADDI(rd, rs, imm, sz)
    <-> 0b011011 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ 0x0000000 : bits(28)

// Opcode 28: SUB (3+8+3+8+3+8+8 = 41 field bits, 17 padding)
mapping clause encdec = PSUB(rd, doff, rs1, s1off, rs2, s2off, sz)
    <-> 0b011100 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ 0b0 : bits(1) @ 0x0000 : bits(16)

// Opcode 29: SUBI (3+3+16+8 = 30 field bits, 28 padding)
mapping clause encdec = PSUBI(rd, rs, imm, sz)
    <-> 0b011101 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ 0x0000000 : bits(28)

// Opcode 30: SUBII (3+16+3+8 = 30 field bits, 28 padding)
mapping clause encdec = PSUBII(rd, imm, rs, sz)
    <-> 0b011110 @ encdec_pregidx(rd) @ imm @ encdec_pregidx(rs) @ sz @ 0x0000000 : bits(28)

// Opcode 31: AND (3+8+3+8+3+8+8 = 41 field bits, 17 padding)
mapping clause encdec = PAND(rd, doff, rs1, s1off, rs2, s2off, sz)
    <-> 0b011111 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ 0b0 : bits(1) @ 0x0000 : bits(16)

// Opcode 32: ANDI (3+3+16+8 = 30 field bits, 28 padding)
mapping clause encdec = PANDI(rd, rs, imm, sz)
    <-> 0b100000 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ 0x0000000 : bits(28)

// Opcode 33: OR (3+8+3+8+3+8+8 = 41 field bits, 17 padding)
mapping clause encdec = POR(rd, doff, rs1, s1off, rs2, s2off, sz)
    <-> 0b100001 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ 0b0 : bits(1) @ 0x0000 : bits(16)

// Opcode 34: ORI (3+3+16+8 = 30 field bits, 28 padding)
mapping clause encdec = PORI(rd, rs, imm, sz)
    <-> 0b100010 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ 0x0000000 : bits(28)

// Opcode 35: CMP (3+8+3+8+8 = 30 field bits, 28 padding)
mapping clause encdec = PCMP(rs1, s1off, rs2, s2off, sz)
    <-> 0b100011 @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ 0x0000000 : bits(28)

// Opcode 36: CMPIBY (3+8+16+8 = 35 field bits, 23 padding)
mapping clause encdec = PCMPIBY(rs, soff, imm, sz)
    <-> 0b100100 @ encdec_pregidx(rs) @ soff @ imm @ sz @ 0b000 : bits(3) @ 0x00000 : bits(20)

// Opcode 37: CMPIBI (3+8+16+8 = 35 field bits, 23 padding)
mapping clause encdec = PCMPIBI(rs, soff, imm, sz)
    <-> 0b100101 @ encdec_pregidx(rs) @ soff @ imm @ sz @ 0b000 : bits(3) @ 0x00000 : bits(20)

// Opcode 38: BR (3+16 = 19 field bits, 39 padding)
mapping clause encdec = PBR(cc, target)
    <-> 0b100110 @ encdec_pcond(cc) @ target @ 0b000 : bits(3) @ 0x000000000 : bits(36)

// Opcode 39: BRBTST (1+3+8+16 = 28 field bits, 30 padding)
mapping clause encdec = PBRBTST(btcc, rs, boff, target)
    <-> 0b100111 @ encdec_pbtcond(btcc) @ encdec_pregidx(rs) @ boff @ target @ 0b00 : bits(2) @ 0x0000000 : bits(28)

// Opcode 40: BRNS (3+8 = 11 field bits, 47 padding)
mapping clause encdec = PBRNS(cc, rule)
    <-> 0b101000 @ encdec_pcond(cc) @ rule @ 0b000 : bits(3) @ 0x00000000000 : bits(44)

// Opcode 41: BRNXTP (3+8+16 = 27 field bits, 31 padding)
mapping clause encdec = PBRNXTP(cc, jm, addr)
    <-> 0b101001 @ encdec_pcond(cc) @ jm @ addr @ 0b000 : bits(3) @ 0x0000000 : bits(28)

// Opcode 42: BRBTSTNXTP (1+3+8+8+16 = 36 field bits, 22 padding)
mapping clause encdec = PBRBTSTNXTP(btcc, rs, boff, jm, addr)
    <-> 0b101010 @ encdec_pbtcond(btcc) @ encdec_pregidx(rs) @ boff @ jm @ addr @ 0b00 : bits(2) @ 0x00000 : bits(20)

// Opcode 43: BRBTSTNS (1+3+8+8 = 20 field bits, 38 padding)
mapping clause encdec = PBRBTSTNS(btcc, rs, boff, rule)
    <-> 0b101011 @ encdec_pbtcond(btcc) @ encdec_pregidx(rs) @ boff @ rule @ 0b00 : bits(2) @ 0x000000000 : bits(36)

end encdec

// Encode a pinstr to bits(64).
val encode_pinstr : pinstr -> bits(64)
function encode_pinstr(instr) = encdec(instr)

// Decode bits(64) to pinstr.
val decode_pinstr : bits(64) -> pinstr
function decode_pinstr(bv) = encdec(bv)
