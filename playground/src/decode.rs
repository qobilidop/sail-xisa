use crate::types::*;

/// Error returned when a 64-bit word cannot be decoded to a known instruction.
#[derive(Debug, Clone)]
pub struct DecodeError {
    pub word: u64,
    pub message: String,
}

// Opcode constants (6-bit values occupying bits [63:58]).
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

/// Extract a field from `word`. `start` is the MSB bit position (0 = bit 63),
/// `width` is the number of bits. Returns zero-extended value.
fn field(word: u64, start: u8, width: u8) -> u64 {
    let shift = 63 - start - (width - 1);
    (word >> shift) & ((1u64 << width) - 1)
}

fn decode_reg(bits: u64, word: u64) -> Result<Reg, DecodeError> {
    match bits {
        0 => Ok(Reg::PR0),
        1 => Ok(Reg::PR1),
        2 => Ok(Reg::PR2),
        3 => Ok(Reg::PR3),
        4 => Ok(Reg::PRN),
        _ => Err(DecodeError {
            word,
            message: format!("invalid register index: {}", bits),
        }),
    }
}

fn decode_cond(bits: u64, word: u64) -> Result<Condition, DecodeError> {
    match bits {
        0 => Ok(Condition::Eq),
        1 => Ok(Condition::Neq),
        2 => Ok(Condition::Lt),
        3 => Ok(Condition::Gt),
        4 => Ok(Condition::Ge),
        5 => Ok(Condition::Le),
        6 => Ok(Condition::Al),
        _ => Err(DecodeError {
            word,
            message: format!("invalid condition code: {}", bits),
        }),
    }
}

fn decode_btcond(bits: u64) -> BitTestCond {
    if bits == 0 {
        BitTestCond::Clear
    } else {
        BitTestCond::Set
    }
}

/// Decode a 64-bit encoded instruction word to an `Instruction`.
pub fn decode(word: u64) -> Result<Instruction, DecodeError> {
    let opcode = field(word, 0, 6) as u8;

    match opcode {
        OP_NOP => Ok(Instruction::Nop),

        OP_HALT => {
            let drop = field(word, 6, 1) != 0;
            Ok(Instruction::Halt { drop })
        }

        OP_NXTP => {
            // rs(3) @ soff(8) @ size(8)
            let rs = decode_reg(field(word, 6, 3), word)?;
            let soff = field(word, 9, 8) as u8;
            let size = field(word, 17, 8) as u8;
            Ok(Instruction::Nxtp { rs, soff, size })
        }

        OP_PSEEK => {
            // rd(3) @ doff(8) @ rs(3) @ soff(8) @ size(8) @ cid(8)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let rs = decode_reg(field(word, 17, 3), word)?;
            let soff = field(word, 20, 8) as u8;
            let size = field(word, 28, 8) as u8;
            let cid = field(word, 36, 8) as u8;
            Ok(Instruction::Pseek { rd, doff, rs, soff, size, cid })
        }

        OP_PSEEKNXTP => {
            // same layout as PSEEK
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let rs = decode_reg(field(word, 17, 3), word)?;
            let soff = field(word, 20, 8) as u8;
            let size = field(word, 28, 8) as u8;
            let cid = field(word, 36, 8) as u8;
            Ok(Instruction::PseekNxtp { rd, doff, rs, soff, size, cid })
        }

        OP_EXT => {
            // rd(3) @ doff(8) @ soff(16) @ size(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let soff = field(word, 17, 16) as u16;
            let size = field(word, 33, 8) as u8;
            let cd = field(word, 41, 1) != 0;
            Ok(Instruction::Ext { rd, doff, soff, size, cd })
        }

        OP_EXTNXTP => {
            // rd(3) @ soff(16) @ size(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let soff = field(word, 9, 16) as u16;
            let size = field(word, 25, 8) as u8;
            let cd = field(word, 33, 1) != 0;
            Ok(Instruction::ExtNxtp { rd, soff, size, cd })
        }

        OP_EXTMAP => {
            // midx(4) @ doff(8) @ poff(16) @ size(8)
            let midx = field(word, 6, 4) as u8;
            let doff = field(word, 10, 8) as u8;
            let poff = field(word, 18, 16) as u16;
            let size = field(word, 34, 8) as u8;
            Ok(Instruction::ExtMap { midx, doff, poff, size })
        }

        OP_MOVMAP => {
            // midx(4) @ doff(8) @ rs(3) @ soff(8) @ size(8)
            let midx = field(word, 6, 4) as u8;
            let doff = field(word, 10, 8) as u8;
            let rs = decode_reg(field(word, 18, 3), word)?;
            let soff = field(word, 21, 8) as u8;
            let size = field(word, 29, 8) as u8;
            Ok(Instruction::MovMap { midx, doff, rs, soff, size })
        }

        OP_CNCTBY => {
            // rd(3) @ doff(8) @ rs1(3) @ s1off(8) @ s1sz(8) @ rs2(3) @ s2off(8) @ s2sz(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let rs1 = decode_reg(field(word, 17, 3), word)?;
            let s1off = field(word, 20, 8) as u8;
            let s1sz = field(word, 28, 8) as u8;
            let rs2 = decode_reg(field(word, 36, 3), word)?;
            let s2off = field(word, 39, 8) as u8;
            let s2sz = field(word, 47, 8) as u8;
            let cd = field(word, 55, 1) != 0;
            Ok(Instruction::CnctBy { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd })
        }

        OP_CNCTBI => {
            // same layout as CNCTBY
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let rs1 = decode_reg(field(word, 17, 3), word)?;
            let s1off = field(word, 20, 8) as u8;
            let s1sz = field(word, 28, 8) as u8;
            let rs2 = decode_reg(field(word, 36, 3), word)?;
            let s2off = field(word, 39, 8) as u8;
            let s2sz = field(word, 47, 8) as u8;
            let cd = field(word, 55, 1) != 0;
            Ok(Instruction::CnctBi { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd })
        }

        OP_STH => {
            // pid(8) @ oid(8) @ halt(1)
            let pid = field(word, 6, 8) as u8;
            let oid = field(word, 14, 8) as u8;
            let halt = field(word, 22, 1) != 0;
            Ok(Instruction::Sth { pid, oid, halt })
        }

        OP_STC => {
            // rs(3) @ soff(8) @ ssz(8) @ shift(8) @ incr(8)
            let rs = decode_reg(field(word, 6, 3), word)?;
            let soff = field(word, 9, 8) as u8;
            let ssz = field(word, 17, 8) as u8;
            let shift = field(word, 25, 8) as u8;
            let incr = field(word, 33, 8) as u8;
            Ok(Instruction::Stc { rs, soff, ssz, shift, incr })
        }

        OP_STCI => {
            // incr(16)
            let incr = field(word, 6, 16) as u16;
            Ok(Instruction::Stci { incr })
        }

        OP_STCH => {
            // incr(16) @ pid(8) @ oid(8) @ halt(1)
            let incr = field(word, 6, 16) as u16;
            let pid = field(word, 22, 8) as u8;
            let oid = field(word, 30, 8) as u8;
            let halt = field(word, 38, 1) != 0;
            Ok(Instruction::Stch { incr, pid, oid, halt })
        }

        OP_STHC => {
            // incr(16) @ pid(8) @ oid(8)
            let incr = field(word, 6, 16) as u16;
            let pid = field(word, 22, 8) as u8;
            let oid = field(word, 30, 8) as u8;
            Ok(Instruction::Sthc { incr, pid, oid })
        }

        OP_ST => {
            // rs(3) @ soff(8) @ doff(8) @ size(8) @ halt(1)
            let rs = decode_reg(field(word, 6, 3), word)?;
            let soff = field(word, 9, 8) as u8;
            let doff = field(word, 17, 8) as u8;
            let size = field(word, 25, 8) as u8;
            let halt = field(word, 33, 1) != 0;
            Ok(Instruction::St { rs, soff, doff, size, halt })
        }

        OP_STI => {
            // imm(16) @ doff(8) @ size(8)
            let imm = field(word, 6, 16) as u16;
            let doff = field(word, 22, 8) as u8;
            let size = field(word, 30, 8) as u8;
            Ok(Instruction::StI { imm, doff, size })
        }

        OP_MOV => {
            // rd(3) @ doff(8) @ rs(3) @ soff(8) @ size(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let rs = decode_reg(field(word, 17, 3), word)?;
            let soff = field(word, 20, 8) as u8;
            let size = field(word, 28, 8) as u8;
            let cd = field(word, 36, 1) != 0;
            Ok(Instruction::Mov { rd, doff, rs, soff, size, cd })
        }

        OP_MOVI => {
            // rd(3) @ doff(8) @ imm(16) @ size(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let imm = field(word, 17, 16) as u16;
            let size = field(word, 33, 8) as u8;
            let cd = field(word, 41, 1) != 0;
            Ok(Instruction::Movi { rd, doff, imm, size, cd })
        }

        OP_MOVL => {
            // rd(3) @ rs1(3) @ o1(8) @ sz1(8) @ rs2(3) @ o2(8) @ sz2(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let rs1 = decode_reg(field(word, 9, 3), word)?;
            let o1 = field(word, 12, 8) as u8;
            let sz1 = field(word, 20, 8) as u8;
            let rs2 = decode_reg(field(word, 28, 3), word)?;
            let o2 = field(word, 31, 8) as u8;
            let sz2 = field(word, 39, 8) as u8;
            let cd = field(word, 47, 1) != 0;
            Ok(Instruction::MovL { rd, rs1, o1, sz1, rs2, o2, sz2, cd })
        }

        OP_MOVLI => {
            // rd(3) @ rs(3) @ off(8) @ size(8) @ imm(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let rs = decode_reg(field(word, 9, 3), word)?;
            let off = field(word, 12, 8) as u8;
            let size = field(word, 20, 8) as u8;
            let imm = field(word, 28, 8) as u8;
            let cd = field(word, 36, 1) != 0;
            Ok(Instruction::MovLI { rd, rs, off, size, imm, cd })
        }

        OP_MOVLII => {
            // rd(3) @ rs(3) @ off(8) @ size(8) @ imm(8) @ isz(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let rs = decode_reg(field(word, 9, 3), word)?;
            let off = field(word, 12, 8) as u8;
            let size = field(word, 20, 8) as u8;
            let imm = field(word, 28, 8) as u8;
            let isz = field(word, 36, 8) as u8;
            let cd = field(word, 44, 1) != 0;
            Ok(Instruction::MovLII { rd, rs, off, size, imm, isz, cd })
        }

        OP_MOVR => {
            // same layout as MOVL
            let rd = decode_reg(field(word, 6, 3), word)?;
            let rs1 = decode_reg(field(word, 9, 3), word)?;
            let o1 = field(word, 12, 8) as u8;
            let sz1 = field(word, 20, 8) as u8;
            let rs2 = decode_reg(field(word, 28, 3), word)?;
            let o2 = field(word, 31, 8) as u8;
            let sz2 = field(word, 39, 8) as u8;
            let cd = field(word, 47, 1) != 0;
            Ok(Instruction::MovR { rd, rs1, o1, sz1, rs2, o2, sz2, cd })
        }

        OP_MOVRI => {
            // same layout as MOVLI
            let rd = decode_reg(field(word, 6, 3), word)?;
            let rs = decode_reg(field(word, 9, 3), word)?;
            let off = field(word, 12, 8) as u8;
            let size = field(word, 20, 8) as u8;
            let imm = field(word, 28, 8) as u8;
            let cd = field(word, 36, 1) != 0;
            Ok(Instruction::MovRI { rd, rs, off, size, imm, cd })
        }

        OP_MOVRII => {
            // same layout as MOVLII
            let rd = decode_reg(field(word, 6, 3), word)?;
            let rs = decode_reg(field(word, 9, 3), word)?;
            let off = field(word, 12, 8) as u8;
            let size = field(word, 20, 8) as u8;
            let imm = field(word, 28, 8) as u8;
            let isz = field(word, 36, 8) as u8;
            let cd = field(word, 44, 1) != 0;
            Ok(Instruction::MovRII { rd, rs, off, size, imm, isz, cd })
        }

        OP_ADD => {
            // rd(3) @ doff(8) @ rs1(3) @ s1off(8) @ rs2(3) @ s2off(8) @ size(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let rs1 = decode_reg(field(word, 17, 3), word)?;
            let s1off = field(word, 20, 8) as u8;
            let rs2 = decode_reg(field(word, 28, 3), word)?;
            let s2off = field(word, 31, 8) as u8;
            let size = field(word, 39, 8) as u8;
            let cd = field(word, 47, 1) != 0;
            Ok(Instruction::Add { rd, doff, rs1, s1off, rs2, s2off, size, cd })
        }

        OP_ADDI => {
            // rd(3) @ rs(3) @ imm(16) @ size(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let rs = decode_reg(field(word, 9, 3), word)?;
            let imm = field(word, 12, 16) as u16;
            let size = field(word, 28, 8) as u8;
            let cd = field(word, 36, 1) != 0;
            Ok(Instruction::AddI { rd, rs, imm, size, cd })
        }

        OP_SUB => {
            // same layout as ADD
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let rs1 = decode_reg(field(word, 17, 3), word)?;
            let s1off = field(word, 20, 8) as u8;
            let rs2 = decode_reg(field(word, 28, 3), word)?;
            let s2off = field(word, 31, 8) as u8;
            let size = field(word, 39, 8) as u8;
            let cd = field(word, 47, 1) != 0;
            Ok(Instruction::Sub { rd, doff, rs1, s1off, rs2, s2off, size, cd })
        }

        OP_SUBI => {
            // same layout as ADDI
            let rd = decode_reg(field(word, 6, 3), word)?;
            let rs = decode_reg(field(word, 9, 3), word)?;
            let imm = field(word, 12, 16) as u16;
            let size = field(word, 28, 8) as u8;
            let cd = field(word, 36, 1) != 0;
            Ok(Instruction::SubI { rd, rs, imm, size, cd })
        }

        OP_SUBII => {
            // rd(3) @ imm(16) @ rs(3) @ size(8) @ cd(1)
            let rd = decode_reg(field(word, 6, 3), word)?;
            let imm = field(word, 9, 16) as u16;
            let rs = decode_reg(field(word, 25, 3), word)?;
            let size = field(word, 28, 8) as u8;
            let cd = field(word, 36, 1) != 0;
            Ok(Instruction::SubII { rd, imm, rs, size, cd })
        }

        OP_AND => {
            // same layout as ADD
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let rs1 = decode_reg(field(word, 17, 3), word)?;
            let s1off = field(word, 20, 8) as u8;
            let rs2 = decode_reg(field(word, 28, 3), word)?;
            let s2off = field(word, 31, 8) as u8;
            let size = field(word, 39, 8) as u8;
            let cd = field(word, 47, 1) != 0;
            Ok(Instruction::And { rd, doff, rs1, s1off, rs2, s2off, size, cd })
        }

        OP_ANDI => {
            // same layout as ADDI
            let rd = decode_reg(field(word, 6, 3), word)?;
            let rs = decode_reg(field(word, 9, 3), word)?;
            let imm = field(word, 12, 16) as u16;
            let size = field(word, 28, 8) as u8;
            let cd = field(word, 36, 1) != 0;
            Ok(Instruction::AndI { rd, rs, imm, size, cd })
        }

        OP_OR => {
            // same layout as ADD
            let rd = decode_reg(field(word, 6, 3), word)?;
            let doff = field(word, 9, 8) as u8;
            let rs1 = decode_reg(field(word, 17, 3), word)?;
            let s1off = field(word, 20, 8) as u8;
            let rs2 = decode_reg(field(word, 28, 3), word)?;
            let s2off = field(word, 31, 8) as u8;
            let size = field(word, 39, 8) as u8;
            let cd = field(word, 47, 1) != 0;
            Ok(Instruction::Or { rd, doff, rs1, s1off, rs2, s2off, size, cd })
        }

        OP_ORI => {
            // same layout as ADDI
            let rd = decode_reg(field(word, 6, 3), word)?;
            let rs = decode_reg(field(word, 9, 3), word)?;
            let imm = field(word, 12, 16) as u16;
            let size = field(word, 28, 8) as u8;
            let cd = field(word, 36, 1) != 0;
            Ok(Instruction::OrI { rd, rs, imm, size, cd })
        }

        OP_CMP => {
            // rs1(3) @ s1off(8) @ rs2(3) @ s2off(8) @ size(8)
            let rs1 = decode_reg(field(word, 6, 3), word)?;
            let s1off = field(word, 9, 8) as u8;
            let rs2 = decode_reg(field(word, 17, 3), word)?;
            let s2off = field(word, 20, 8) as u8;
            let size = field(word, 28, 8) as u8;
            Ok(Instruction::Cmp { rs1, s1off, rs2, s2off, size })
        }

        OP_CMPIBY => {
            // rs(3) @ soff(8) @ imm(16) @ size(8)
            let rs = decode_reg(field(word, 6, 3), word)?;
            let soff = field(word, 9, 8) as u8;
            let imm = field(word, 17, 16) as u16;
            let size = field(word, 33, 8) as u8;
            Ok(Instruction::CmpIBy { rs, soff, imm, size })
        }

        OP_CMPIBI => {
            // same layout as CMPIBY
            let rs = decode_reg(field(word, 6, 3), word)?;
            let soff = field(word, 9, 8) as u8;
            let imm = field(word, 17, 16) as u16;
            let size = field(word, 33, 8) as u8;
            Ok(Instruction::CmpIBi { rs, soff, imm, size })
        }

        OP_BR => {
            // cc(3) @ target(16)
            let cc = decode_cond(field(word, 6, 3), word)?;
            let target = field(word, 9, 16) as u16;
            Ok(Instruction::Br { cc, target })
        }

        OP_BRBTST => {
            // btcc(1) @ rs(3) @ boff(8) @ target(16)
            let btcc = decode_btcond(field(word, 6, 1));
            let rs = decode_reg(field(word, 7, 3), word)?;
            let boff = field(word, 10, 8) as u8;
            let target = field(word, 18, 16) as u16;
            Ok(Instruction::BrBtst { btcc, rs, boff, target })
        }

        OP_BRNS => {
            // cc(3) @ rule(8)
            let cc = decode_cond(field(word, 6, 3), word)?;
            let rule = field(word, 9, 8) as u8;
            Ok(Instruction::BrNs { cc, rule })
        }

        OP_BRNXTP => {
            // cc(3) @ jm(8) @ addr_or_rule(16)
            let cc = decode_cond(field(word, 6, 3), word)?;
            let jm = field(word, 9, 8) as u8;
            let addr_or_rule = field(word, 17, 16) as u16;
            Ok(Instruction::BrNxtp { cc, jm, addr_or_rule })
        }

        OP_BRBTSTNXTP => {
            // btcc(1) @ rs(3) @ boff(8) @ jm(8) @ addr_or_rule(16)
            let btcc = decode_btcond(field(word, 6, 1));
            let rs = decode_reg(field(word, 7, 3), word)?;
            let boff = field(word, 10, 8) as u8;
            let jm = field(word, 18, 8) as u8;
            let addr_or_rule = field(word, 26, 16) as u16;
            Ok(Instruction::BrBtstNxtp { btcc, rs, boff, jm, addr_or_rule })
        }

        OP_BRBTSTNS => {
            // btcc(1) @ rs(3) @ boff(8) @ rule(8)
            let btcc = decode_btcond(field(word, 6, 1));
            let rs = decode_reg(field(word, 7, 3), word)?;
            let boff = field(word, 10, 8) as u8;
            let rule = field(word, 18, 8) as u8;
            Ok(Instruction::BrBtstNs { btcc, rs, boff, rule })
        }

        _ => Err(DecodeError {
            word,
            message: format!("unknown opcode: {}", opcode),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decode_nop() {
        assert_eq!(decode(0).unwrap(), Instruction::Nop);
    }

    #[test]
    fn test_decode_halt() {
        assert_eq!(
            decode(1u64 << 58).unwrap(),
            Instruction::Halt { drop: false }
        );
    }

    #[test]
    fn test_decode_halt_drop() {
        assert_eq!(
            decode((1u64 << 58) | (1u64 << 57)).unwrap(),
            Instruction::Halt { drop: true }
        );
    }

    #[test]
    fn test_decode_unknown_opcode() {
        // opcode 63 (all 6 opcode bits set) is not defined
        assert!(decode(63u64 << 58).is_err());
    }
}
