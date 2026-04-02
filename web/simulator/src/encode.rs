use crate::types::*;

/// Pack a field into `word`. `start` is the MSB bit position (0 = bit 63),
/// `width` is the number of bits. This is the inverse of `field()` in decode.rs.
fn pack(word: &mut u64, start: u8, width: u8, value: u64) {
    let shift = 63 - start as u32 - (width as u32 - 1);
    let mask = (1u64 << width) - 1;
    *word |= (value & mask) << shift;
}

fn reg_bits(r: Reg) -> u64 {
    r as u64
}

fn cond_bits(c: Condition) -> u64 {
    c as u64
}

fn btcond_bits(b: BitTestCond) -> u64 {
    b as u64
}

// Opcode constants (must match decode.rs exactly).
const OP_NOP: u8 = 0;
const OP_HALT: u8 = 1;
const OP_NXTP: u8 = 2;
const OP_PSEEK: u8 = 3;
const OP_PSEEKNXTP: u8 = 4;
const OP_EXT: u8 = 5;
const OP_EXTNXTP: u8 = 6;
const OP_EXTMAP: u8 = 7;
const OP_MOVMAP: u8 = 8;
const OP_CNCTBY: u8 = 9;
const OP_CNCTBI: u8 = 10;
const OP_STH: u8 = 11;
const OP_STC: u8 = 12;
const OP_STCI: u8 = 13;
const OP_STCH: u8 = 14;
const OP_STHC: u8 = 15;
const OP_ST: u8 = 16;
const OP_STI: u8 = 17;
const OP_MOV: u8 = 18;
const OP_MOVI: u8 = 19;
const OP_MOVL: u8 = 20;
const OP_MOVLI: u8 = 21;
const OP_MOVLII: u8 = 22;
const OP_MOVR: u8 = 23;
const OP_MOVRI: u8 = 24;
const OP_MOVRII: u8 = 25;
const OP_ADD: u8 = 26;
const OP_ADDI: u8 = 27;
const OP_SUB: u8 = 28;
const OP_SUBI: u8 = 29;
const OP_SUBII: u8 = 30;
const OP_AND: u8 = 31;
const OP_ANDI: u8 = 32;
const OP_OR: u8 = 33;
const OP_ORI: u8 = 34;
const OP_CMP: u8 = 35;
const OP_CMPIBY: u8 = 36;
const OP_CMPIBI: u8 = 37;
const OP_BR: u8 = 38;
const OP_BRBTST: u8 = 39;
const OP_BRNS: u8 = 40;
const OP_BRNXTP: u8 = 41;
const OP_BRBTSTNXTP: u8 = 42;
const OP_BRBTSTNS: u8 = 43;

/// Encode an `Instruction` into a 64-bit word.
pub fn encode(inst: &Instruction) -> u64 {
    let mut w = 0u64;

    match inst {
        Instruction::Nop => {
            pack(&mut w, 0, 6, OP_NOP as u64);
        }

        Instruction::Halt { drop } => {
            pack(&mut w, 0, 6, OP_HALT as u64);
            pack(&mut w, 6, 1, *drop as u64);
        }

        Instruction::Nxtp { rs, soff, size } => {
            pack(&mut w, 0, 6, OP_NXTP as u64);
            // rs(3) @ soff(8) @ size(8)
            pack(&mut w, 6, 3, reg_bits(*rs));
            pack(&mut w, 9, 8, *soff as u64);
            pack(&mut w, 17, 8, *size as u64);
        }

        Instruction::Pseek { rd, doff, rs, soff, size, cid } => {
            pack(&mut w, 0, 6, OP_PSEEK as u64);
            // rd(3) @ doff(8) @ rs(3) @ soff(8) @ size(8) @ cid(8)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs));
            pack(&mut w, 20, 8, *soff as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 8, *cid as u64);
        }

        Instruction::PseekNxtp { rd, doff, rs, soff, size, cid } => {
            pack(&mut w, 0, 6, OP_PSEEKNXTP as u64);
            // same layout as PSEEK
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs));
            pack(&mut w, 20, 8, *soff as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 8, *cid as u64);
        }

        Instruction::Ext { rd, doff, soff, size, cd } => {
            pack(&mut w, 0, 6, OP_EXT as u64);
            // rd(3) @ doff(8) @ soff(16) @ size(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 16, *soff as u64);
            pack(&mut w, 33, 8, *size as u64);
            pack(&mut w, 41, 1, *cd as u64);
        }

        Instruction::ExtNxtp { rd, soff, size, cd } => {
            pack(&mut w, 0, 6, OP_EXTNXTP as u64);
            // rd(3) @ soff(16) @ size(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 16, *soff as u64);
            pack(&mut w, 25, 8, *size as u64);
            pack(&mut w, 33, 1, *cd as u64);
        }

        Instruction::ExtMap { midx, doff, poff, size } => {
            pack(&mut w, 0, 6, OP_EXTMAP as u64);
            // midx(4) @ doff(8) @ poff(16) @ size(8)
            pack(&mut w, 6, 4, *midx as u64);
            pack(&mut w, 10, 8, *doff as u64);
            pack(&mut w, 18, 16, *poff as u64);
            pack(&mut w, 34, 8, *size as u64);
        }

        Instruction::MovMap { midx, doff, rs, soff, size } => {
            pack(&mut w, 0, 6, OP_MOVMAP as u64);
            // midx(4) @ doff(8) @ rs(3) @ soff(8) @ size(8)
            pack(&mut w, 6, 4, *midx as u64);
            pack(&mut w, 10, 8, *doff as u64);
            pack(&mut w, 18, 3, reg_bits(*rs));
            pack(&mut w, 21, 8, *soff as u64);
            pack(&mut w, 29, 8, *size as u64);
        }

        Instruction::CnctBy { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd } => {
            pack(&mut w, 0, 6, OP_CNCTBY as u64);
            // rd(3) @ doff(8) @ rs1(3) @ s1off(8) @ s1sz(8) @ rs2(3) @ s2off(8) @ s2sz(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs1));
            pack(&mut w, 20, 8, *s1off as u64);
            pack(&mut w, 28, 8, *s1sz as u64);
            pack(&mut w, 36, 3, reg_bits(*rs2));
            pack(&mut w, 39, 8, *s2off as u64);
            pack(&mut w, 47, 8, *s2sz as u64);
            pack(&mut w, 55, 1, *cd as u64);
        }

        Instruction::CnctBi { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd } => {
            pack(&mut w, 0, 6, OP_CNCTBI as u64);
            // same layout as CNCTBY
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs1));
            pack(&mut w, 20, 8, *s1off as u64);
            pack(&mut w, 28, 8, *s1sz as u64);
            pack(&mut w, 36, 3, reg_bits(*rs2));
            pack(&mut w, 39, 8, *s2off as u64);
            pack(&mut w, 47, 8, *s2sz as u64);
            pack(&mut w, 55, 1, *cd as u64);
        }

        Instruction::Sth { pid, oid, halt } => {
            pack(&mut w, 0, 6, OP_STH as u64);
            // pid(8) @ oid(8) @ halt(1)
            pack(&mut w, 6, 8, *pid as u64);
            pack(&mut w, 14, 8, *oid as u64);
            pack(&mut w, 22, 1, *halt as u64);
        }

        Instruction::Stc { rs, soff, ssz, shift, incr } => {
            pack(&mut w, 0, 6, OP_STC as u64);
            // rs(3) @ soff(8) @ ssz(8) @ shift(8) @ incr(8)
            pack(&mut w, 6, 3, reg_bits(*rs));
            pack(&mut w, 9, 8, *soff as u64);
            pack(&mut w, 17, 8, *ssz as u64);
            pack(&mut w, 25, 8, *shift as u64);
            pack(&mut w, 33, 8, *incr as u64);
        }

        Instruction::Stci { incr } => {
            pack(&mut w, 0, 6, OP_STCI as u64);
            // incr(16)
            pack(&mut w, 6, 16, *incr as u64);
        }

        Instruction::Stch { incr, pid, oid, halt } => {
            pack(&mut w, 0, 6, OP_STCH as u64);
            // incr(16) @ pid(8) @ oid(8) @ halt(1)
            pack(&mut w, 6, 16, *incr as u64);
            pack(&mut w, 22, 8, *pid as u64);
            pack(&mut w, 30, 8, *oid as u64);
            pack(&mut w, 38, 1, *halt as u64);
        }

        Instruction::Sthc { incr, pid, oid } => {
            pack(&mut w, 0, 6, OP_STHC as u64);
            // incr(16) @ pid(8) @ oid(8)
            pack(&mut w, 6, 16, *incr as u64);
            pack(&mut w, 22, 8, *pid as u64);
            pack(&mut w, 30, 8, *oid as u64);
        }

        Instruction::St { rs, soff, doff, size, halt } => {
            pack(&mut w, 0, 6, OP_ST as u64);
            // rs(3) @ soff(8) @ doff(8) @ size(8) @ halt(1)
            pack(&mut w, 6, 3, reg_bits(*rs));
            pack(&mut w, 9, 8, *soff as u64);
            pack(&mut w, 17, 8, *doff as u64);
            pack(&mut w, 25, 8, *size as u64);
            pack(&mut w, 33, 1, *halt as u64);
        }

        Instruction::StI { imm, doff, size } => {
            pack(&mut w, 0, 6, OP_STI as u64);
            // imm(16) @ doff(8) @ size(8)
            pack(&mut w, 6, 16, *imm as u64);
            pack(&mut w, 22, 8, *doff as u64);
            pack(&mut w, 30, 8, *size as u64);
        }

        Instruction::Mov { rd, doff, rs, soff, size, cd } => {
            pack(&mut w, 0, 6, OP_MOV as u64);
            // rd(3) @ doff(8) @ rs(3) @ soff(8) @ size(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs));
            pack(&mut w, 20, 8, *soff as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::Movi { rd, doff, imm, size, cd } => {
            pack(&mut w, 0, 6, OP_MOVI as u64);
            // rd(3) @ doff(8) @ imm(16) @ size(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 16, *imm as u64);
            pack(&mut w, 33, 8, *size as u64);
            pack(&mut w, 41, 1, *cd as u64);
        }

        Instruction::MovL { rd, rs1, o1, sz1, rs2, o2, sz2, cd } => {
            pack(&mut w, 0, 6, OP_MOVL as u64);
            // rd(3) @ rs1(3) @ o1(8) @ sz1(8) @ rs2(3) @ o2(8) @ sz2(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs1));
            pack(&mut w, 12, 8, *o1 as u64);
            pack(&mut w, 20, 8, *sz1 as u64);
            pack(&mut w, 28, 3, reg_bits(*rs2));
            pack(&mut w, 31, 8, *o2 as u64);
            pack(&mut w, 39, 8, *sz2 as u64);
            pack(&mut w, 47, 1, *cd as u64);
        }

        Instruction::MovLI { rd, rs, off, size, imm, cd } => {
            pack(&mut w, 0, 6, OP_MOVLI as u64);
            // rd(3) @ rs(3) @ off(8) @ size(8) @ imm(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 8, *off as u64);
            pack(&mut w, 20, 8, *size as u64);
            pack(&mut w, 28, 8, *imm as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::MovLII { rd, rs, off, size, imm, isz, cd } => {
            pack(&mut w, 0, 6, OP_MOVLII as u64);
            // rd(3) @ rs(3) @ off(8) @ size(8) @ imm(8) @ isz(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 8, *off as u64);
            pack(&mut w, 20, 8, *size as u64);
            pack(&mut w, 28, 8, *imm as u64);
            pack(&mut w, 36, 8, *isz as u64);
            pack(&mut w, 44, 1, *cd as u64);
        }

        Instruction::MovR { rd, rs1, o1, sz1, rs2, o2, sz2, cd } => {
            pack(&mut w, 0, 6, OP_MOVR as u64);
            // same layout as MOVL
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs1));
            pack(&mut w, 12, 8, *o1 as u64);
            pack(&mut w, 20, 8, *sz1 as u64);
            pack(&mut w, 28, 3, reg_bits(*rs2));
            pack(&mut w, 31, 8, *o2 as u64);
            pack(&mut w, 39, 8, *sz2 as u64);
            pack(&mut w, 47, 1, *cd as u64);
        }

        Instruction::MovRI { rd, rs, off, size, imm, cd } => {
            pack(&mut w, 0, 6, OP_MOVRI as u64);
            // same layout as MOVLI
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 8, *off as u64);
            pack(&mut w, 20, 8, *size as u64);
            pack(&mut w, 28, 8, *imm as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::MovRII { rd, rs, off, size, imm, isz, cd } => {
            pack(&mut w, 0, 6, OP_MOVRII as u64);
            // same layout as MOVLII
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 8, *off as u64);
            pack(&mut w, 20, 8, *size as u64);
            pack(&mut w, 28, 8, *imm as u64);
            pack(&mut w, 36, 8, *isz as u64);
            pack(&mut w, 44, 1, *cd as u64);
        }

        Instruction::Add { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            pack(&mut w, 0, 6, OP_ADD as u64);
            // rd(3) @ doff(8) @ rs1(3) @ s1off(8) @ rs2(3) @ s2off(8) @ size(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs1));
            pack(&mut w, 20, 8, *s1off as u64);
            pack(&mut w, 28, 3, reg_bits(*rs2));
            pack(&mut w, 31, 8, *s2off as u64);
            pack(&mut w, 39, 8, *size as u64);
            pack(&mut w, 47, 1, *cd as u64);
        }

        Instruction::AddI { rd, rs, imm, size, cd } => {
            pack(&mut w, 0, 6, OP_ADDI as u64);
            // rd(3) @ rs(3) @ imm(16) @ size(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 16, *imm as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::Sub { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            pack(&mut w, 0, 6, OP_SUB as u64);
            // same layout as ADD
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs1));
            pack(&mut w, 20, 8, *s1off as u64);
            pack(&mut w, 28, 3, reg_bits(*rs2));
            pack(&mut w, 31, 8, *s2off as u64);
            pack(&mut w, 39, 8, *size as u64);
            pack(&mut w, 47, 1, *cd as u64);
        }

        Instruction::SubI { rd, rs, imm, size, cd } => {
            pack(&mut w, 0, 6, OP_SUBI as u64);
            // same layout as ADDI
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 16, *imm as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::SubII { rd, imm, rs, size, cd } => {
            pack(&mut w, 0, 6, OP_SUBII as u64);
            // rd(3) @ imm(16) @ rs(3) @ size(8) @ cd(1)
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 16, *imm as u64);
            pack(&mut w, 25, 3, reg_bits(*rs));
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::And { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            pack(&mut w, 0, 6, OP_AND as u64);
            // same layout as ADD
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs1));
            pack(&mut w, 20, 8, *s1off as u64);
            pack(&mut w, 28, 3, reg_bits(*rs2));
            pack(&mut w, 31, 8, *s2off as u64);
            pack(&mut w, 39, 8, *size as u64);
            pack(&mut w, 47, 1, *cd as u64);
        }

        Instruction::AndI { rd, rs, imm, size, cd } => {
            pack(&mut w, 0, 6, OP_ANDI as u64);
            // same layout as ADDI
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 16, *imm as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::Or { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            pack(&mut w, 0, 6, OP_OR as u64);
            // same layout as ADD
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs1));
            pack(&mut w, 20, 8, *s1off as u64);
            pack(&mut w, 28, 3, reg_bits(*rs2));
            pack(&mut w, 31, 8, *s2off as u64);
            pack(&mut w, 39, 8, *size as u64);
            pack(&mut w, 47, 1, *cd as u64);
        }

        Instruction::OrI { rd, rs, imm, size, cd } => {
            pack(&mut w, 0, 6, OP_ORI as u64);
            // same layout as ADDI
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 16, *imm as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::Cmp { rs1, s1off, rs2, s2off, size } => {
            pack(&mut w, 0, 6, OP_CMP as u64);
            // rs1(3) @ s1off(8) @ rs2(3) @ s2off(8) @ size(8)
            pack(&mut w, 6, 3, reg_bits(*rs1));
            pack(&mut w, 9, 8, *s1off as u64);
            pack(&mut w, 17, 3, reg_bits(*rs2));
            pack(&mut w, 20, 8, *s2off as u64);
            pack(&mut w, 28, 8, *size as u64);
        }

        Instruction::CmpIBy { rs, soff, imm, size } => {
            pack(&mut w, 0, 6, OP_CMPIBY as u64);
            // rs(3) @ soff(8) @ imm(16) @ size(8)
            pack(&mut w, 6, 3, reg_bits(*rs));
            pack(&mut w, 9, 8, *soff as u64);
            pack(&mut w, 17, 16, *imm as u64);
            pack(&mut w, 33, 8, *size as u64);
        }

        Instruction::CmpIBi { rs, soff, imm, size } => {
            pack(&mut w, 0, 6, OP_CMPIBI as u64);
            // same layout as CMPIBY
            pack(&mut w, 6, 3, reg_bits(*rs));
            pack(&mut w, 9, 8, *soff as u64);
            pack(&mut w, 17, 16, *imm as u64);
            pack(&mut w, 33, 8, *size as u64);
        }

        Instruction::Br { cc, target } => {
            pack(&mut w, 0, 6, OP_BR as u64);
            // cc(3) @ target(16)
            pack(&mut w, 6, 3, cond_bits(*cc));
            pack(&mut w, 9, 16, *target as u64);
        }

        Instruction::BrBtst { btcc, rs, boff, target } => {
            pack(&mut w, 0, 6, OP_BRBTST as u64);
            // btcc(1) @ rs(3) @ boff(8) @ target(16)
            pack(&mut w, 6, 1, btcond_bits(*btcc));
            pack(&mut w, 7, 3, reg_bits(*rs));
            pack(&mut w, 10, 8, *boff as u64);
            pack(&mut w, 18, 16, *target as u64);
        }

        Instruction::BrNs { cc, rule } => {
            pack(&mut w, 0, 6, OP_BRNS as u64);
            // cc(3) @ rule(8)
            pack(&mut w, 6, 3, cond_bits(*cc));
            pack(&mut w, 9, 8, *rule as u64);
        }

        Instruction::BrNxtp { cc, jm, addr_or_rule } => {
            pack(&mut w, 0, 6, OP_BRNXTP as u64);
            // cc(3) @ jm(8) @ addr_or_rule(16)
            pack(&mut w, 6, 3, cond_bits(*cc));
            pack(&mut w, 9, 8, *jm as u64);
            pack(&mut w, 17, 16, *addr_or_rule as u64);
        }

        Instruction::BrBtstNxtp { btcc, rs, boff, jm, addr_or_rule } => {
            pack(&mut w, 0, 6, OP_BRBTSTNXTP as u64);
            // btcc(1) @ rs(3) @ boff(8) @ jm(8) @ addr_or_rule(16)
            pack(&mut w, 6, 1, btcond_bits(*btcc));
            pack(&mut w, 7, 3, reg_bits(*rs));
            pack(&mut w, 10, 8, *boff as u64);
            pack(&mut w, 18, 8, *jm as u64);
            pack(&mut w, 26, 16, *addr_or_rule as u64);
        }

        Instruction::BrBtstNs { btcc, rs, boff, rule } => {
            pack(&mut w, 0, 6, OP_BRBTSTNS as u64);
            // btcc(1) @ rs(3) @ boff(8) @ rule(8)
            pack(&mut w, 6, 1, btcond_bits(*btcc));
            pack(&mut w, 7, 3, reg_bits(*rs));
            pack(&mut w, 10, 8, *boff as u64);
            pack(&mut w, 18, 8, *rule as u64);
        }
    }

    w
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(inst: Instruction) {
        let word = encode(&inst);
        let decoded = crate::decode::decode(word).expect("decode failed");
        assert_eq!(decoded, inst);
    }

    #[test]
    fn test_roundtrip_nop() {
        roundtrip(Instruction::Nop);
    }

    #[test]
    fn test_roundtrip_halt_no_drop() {
        roundtrip(Instruction::Halt { drop: false });
    }

    #[test]
    fn test_roundtrip_halt_drop() {
        roundtrip(Instruction::Halt { drop: true });
    }

    #[test]
    fn test_roundtrip_ext() {
        roundtrip(Instruction::Ext {
            rd: Reg::PR1,
            doff: 4,
            soff: 0x1234,
            size: 8,
            cd: true,
        });
    }

    #[test]
    fn test_roundtrip_mov() {
        roundtrip(Instruction::Mov {
            rd: Reg::PR0,
            doff: 0,
            rs: Reg::PR2,
            soff: 2,
            size: 4,
            cd: false,
        });
    }

    #[test]
    fn test_roundtrip_add() {
        roundtrip(Instruction::Add {
            rd: Reg::PR1,
            doff: 0,
            rs1: Reg::PR0,
            s1off: 0,
            rs2: Reg::PR2,
            s2off: 0,
            size: 4,
            cd: true,
        });
    }

    #[test]
    fn test_roundtrip_br() {
        roundtrip(Instruction::Br {
            cc: Condition::Eq,
            target: 0xABCD,
        });
    }

    #[test]
    fn test_roundtrip_brbtst() {
        roundtrip(Instruction::BrBtst {
            btcc: BitTestCond::Set,
            rs: Reg::PR3,
            boff: 7,
            target: 0x1000,
        });
    }

    #[test]
    fn test_roundtrip_cnctby() {
        roundtrip(Instruction::CnctBy {
            rd: Reg::PR0,
            doff: 0,
            rs1: Reg::PR1,
            s1off: 1,
            s1sz: 4,
            rs2: Reg::PR2,
            s2off: 2,
            s2sz: 4,
            cd: false,
        });
    }

    #[test]
    fn test_roundtrip_sth() {
        roundtrip(Instruction::Sth {
            pid: 0x12,
            oid: 0x34,
            halt: true,
        });
    }

    #[test]
    fn test_roundtrip_all_variants() {
        // Exhaustive roundtrip of every Instruction variant with sample values.
        let instructions = vec![
            Instruction::Nop,
            Instruction::Halt { drop: false },
            Instruction::Halt { drop: true },
            Instruction::Nxtp { rs: Reg::PR0, soff: 2, size: 6 },
            Instruction::Pseek {
                rd: Reg::PR1, doff: 0, rs: Reg::PR2, soff: 4, size: 8, cid: 3,
            },
            Instruction::PseekNxtp {
                rd: Reg::PR0, doff: 1, rs: Reg::PR3, soff: 5, size: 4, cid: 7,
            },
            Instruction::Ext { rd: Reg::PR1, doff: 4, soff: 0x1234, size: 8, cd: true },
            Instruction::ExtNxtp { rd: Reg::PR2, soff: 0xFFFF, size: 4, cd: false },
            Instruction::ExtMap { midx: 3, doff: 8, poff: 0x5678, size: 16 },
            Instruction::MovMap { midx: 2, doff: 4, rs: Reg::PR1, soff: 0, size: 8 },
            Instruction::CnctBy {
                rd: Reg::PR0, doff: 0,
                rs1: Reg::PR1, s1off: 1, s1sz: 4,
                rs2: Reg::PR2, s2off: 2, s2sz: 4,
                cd: false,
            },
            Instruction::CnctBi {
                rd: Reg::PR3, doff: 2,
                rs1: Reg::PR0, s1off: 0, s1sz: 8,
                rs2: Reg::PR1, s2off: 4, s2sz: 8,
                cd: true,
            },
            Instruction::Sth { pid: 0x12, oid: 0x34, halt: true },
            Instruction::Sth { pid: 0xFF, oid: 0x00, halt: false },
            Instruction::Stc { rs: Reg::PR2, soff: 3, ssz: 4, shift: 2, incr: 10 },
            Instruction::Stci { incr: 0xABCD },
            Instruction::Stch { incr: 0x1234, pid: 5, oid: 6, halt: false },
            Instruction::Sthc { incr: 0x5678, pid: 9, oid: 10 },
            Instruction::St { rs: Reg::PR1, soff: 0, doff: 8, size: 4, halt: true },
            Instruction::StI { imm: 0xBEEF, doff: 0, size: 2 },
            Instruction::Mov { rd: Reg::PR0, doff: 0, rs: Reg::PR2, soff: 2, size: 4, cd: false },
            Instruction::Movi { rd: Reg::PR3, doff: 1, imm: 0x1234, size: 2, cd: true },
            Instruction::MovL {
                rd: Reg::PR0, rs1: Reg::PR1, o1: 0, sz1: 4,
                rs2: Reg::PR2, o2: 4, sz2: 4, cd: false,
            },
            Instruction::MovLI {
                rd: Reg::PR1, rs: Reg::PR0, off: 2, size: 4, imm: 0xAB, cd: true,
            },
            Instruction::MovLII {
                rd: Reg::PR2, rs: Reg::PR3, off: 0, size: 8, imm: 0x12, isz: 4, cd: false,
            },
            Instruction::MovR {
                rd: Reg::PR0, rs1: Reg::PR1, o1: 0, sz1: 4,
                rs2: Reg::PR2, o2: 4, sz2: 4, cd: true,
            },
            Instruction::MovRI {
                rd: Reg::PR1, rs: Reg::PR0, off: 2, size: 4, imm: 0xCD, cd: false,
            },
            Instruction::MovRII {
                rd: Reg::PR2, rs: Reg::PR3, off: 0, size: 8, imm: 0x34, isz: 4, cd: true,
            },
            Instruction::Add {
                rd: Reg::PR1, doff: 0, rs1: Reg::PR0, s1off: 0,
                rs2: Reg::PR2, s2off: 0, size: 4, cd: true,
            },
            Instruction::AddI { rd: Reg::PR0, rs: Reg::PR1, imm: 100, size: 4, cd: false },
            Instruction::Sub {
                rd: Reg::PR2, doff: 0, rs1: Reg::PR1, s1off: 0,
                rs2: Reg::PR0, s2off: 0, size: 4, cd: false,
            },
            Instruction::SubI { rd: Reg::PR3, rs: Reg::PR0, imm: 50, size: 2, cd: true },
            Instruction::SubII { rd: Reg::PR0, imm: 200, rs: Reg::PR1, size: 4, cd: false },
            Instruction::And {
                rd: Reg::PR1, doff: 0, rs1: Reg::PR2, s1off: 0,
                rs2: Reg::PR3, s2off: 0, size: 4, cd: true,
            },
            Instruction::AndI { rd: Reg::PR0, rs: Reg::PR2, imm: 0xFF00, size: 2, cd: false },
            Instruction::Or {
                rd: Reg::PR2, doff: 0, rs1: Reg::PR0, s1off: 0,
                rs2: Reg::PR1, s2off: 0, size: 4, cd: false,
            },
            Instruction::OrI { rd: Reg::PR3, rs: Reg::PR1, imm: 0x00FF, size: 2, cd: true },
            Instruction::Cmp { rs1: Reg::PR0, s1off: 0, rs2: Reg::PR1, s2off: 0, size: 4 },
            Instruction::CmpIBy { rs: Reg::PR2, soff: 0, imm: 0x1234, size: 2 },
            Instruction::CmpIBi { rs: Reg::PR3, soff: 1, imm: 0x5678, size: 4 },
            Instruction::Br { cc: Condition::Eq, target: 0xABCD },
            Instruction::Br { cc: Condition::Al, target: 0x0001 },
            Instruction::BrBtst { btcc: BitTestCond::Set, rs: Reg::PR3, boff: 7, target: 0x1000 },
            Instruction::BrBtst { btcc: BitTestCond::Clear, rs: Reg::PR0, boff: 0, target: 0x0100 },
            Instruction::BrNs { cc: Condition::Neq, rule: 5 },
            Instruction::BrNxtp { cc: Condition::Gt, jm: 2, addr_or_rule: 0x00FF },
            Instruction::BrBtstNxtp {
                btcc: BitTestCond::Set, rs: Reg::PR1, boff: 3, jm: 1, addr_or_rule: 0x1234,
            },
            Instruction::BrBtstNs {
                btcc: BitTestCond::Clear, rs: Reg::PR2, boff: 5, rule: 7,
            },
        ];

        for inst in instructions {
            roundtrip(inst);
        }
    }
}
