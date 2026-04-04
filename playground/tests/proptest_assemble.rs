mod common;

use proptest::prelude::*;
use xisa::assembler::assemble;
use xisa::decode::decode;
use xisa::types::*;

/// Helper: format a Reg as assembly text (e.g., "PR0", "PR1.5").
fn fmt_reg(r: Reg, off: u8) -> String {
    let name = match r {
        Reg::PR0 => "PR0",
        Reg::PR1 => "PR1",
        Reg::PR2 => "PR2",
        Reg::PR3 => "PR3",
        Reg::PRN => "PRN",
    };
    if off == 0 {
        name.to_string()
    } else {
        format!("{}.{}", name, off)
    }
}

/// Helper: format a condition code as assembly suffix.
fn fmt_cc(cc: Condition) -> &'static str {
    match cc {
        Condition::Eq => "EQ",
        Condition::Neq => "NEQ",
        Condition::Lt => "LT",
        Condition::Gt => "GT",
        Condition::Ge => "GE",
        Condition::Le => "LE",
        Condition::Al => "AL",
    }
}

/// Helper: format a bit-test condition.
fn fmt_btcc(btcc: BitTestCond) -> &'static str {
    match btcc {
        BitTestCond::Clear => "CLR",
        BitTestCond::Set => "SET",
    }
}

/// Helper: format the .CD suffix.
fn fmt_cd(cd: bool) -> &'static str {
    if cd { ".CD" } else { "" }
}

proptest! {
    // --- Control ---

    #[test]
    fn asm_nop(_dummy in 0..1u8) {
        let result = assemble("NOP").unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Nop);
    }

    #[test]
    fn asm_halt(_dummy in 0..1u8) {
        let result = assemble("HALT").unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Halt { drop: false });
    }

    #[test]
    fn asm_haltdrop(_dummy in 0..1u8) {
        let result = assemble("HALTDROP").unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Halt { drop: true });
    }

    // --- Data movement ---

    #[test]
    fn asm_mov(
        rd in common::arb_dst_reg(),
        doff in any::<u8>(),
        rs in common::arb_reg(),
        soff in any::<u8>(),
        cd in any::<bool>(),
    ) {
        let src = format!("MOV{} {}, {}", fmt_cd(cd), fmt_reg(rd, doff), fmt_reg(rs, soff));
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Mov { rd, doff, rs, soff, size: 128, cd });
    }

    #[test]
    fn asm_movi(
        rd in common::arb_dst_reg(),
        doff in any::<u8>(),
        imm in any::<u16>(),
        size in any::<u8>(),
        cd in any::<bool>(),
    ) {
        let src = format!("MOVI{} {}, {}, {}", fmt_cd(cd), fmt_reg(rd, doff), imm, size);
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Movi { rd, doff, imm, size, cd });
    }

    #[test]
    fn asm_ext(
        rd in common::arb_dst_reg(),
        soff in any::<u16>(),
        size in any::<u8>(),
        cd in any::<bool>(),
    ) {
        // EXT assembler ignores doff from register and always sets doff: 0
        let src = format!("EXT{} {}, {}, {}", fmt_cd(cd), fmt_reg(rd, 0), soff, size);
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Ext { rd, doff: 0, soff, size, cd });
    }

    // --- Arithmetic ---

    #[test]
    fn asm_add(
        rd in common::arb_dst_reg(),
        doff in any::<u8>(),
        rs1 in common::arb_reg(),
        s1off in any::<u8>(),
        rs2 in common::arb_reg(),
        s2off in any::<u8>(),
        cd in any::<bool>(),
    ) {
        let src = format!("ADD{} {}, {}, {}",
            fmt_cd(cd), fmt_reg(rd, doff), fmt_reg(rs1, s1off), fmt_reg(rs2, s2off));
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Add { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd });
    }

    #[test]
    fn asm_addi(
        rd in common::arb_dst_reg(),
        rs in common::arb_reg(),
        imm in any::<u16>(),
        cd in any::<bool>(),
    ) {
        // ADDI assembler ignores register offsets and always sets size: 128
        let src = format!("ADDI{} {}, {}, {}", fmt_cd(cd), fmt_reg(rd, 0), fmt_reg(rs, 0), imm);
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::AddI { rd, rs, imm, size: 128, cd });
    }

    #[test]
    fn asm_sub(
        rd in common::arb_dst_reg(),
        doff in any::<u8>(),
        rs1 in common::arb_reg(),
        s1off in any::<u8>(),
        rs2 in common::arb_reg(),
        s2off in any::<u8>(),
        cd in any::<bool>(),
    ) {
        let src = format!("SUB{} {}, {}, {}",
            fmt_cd(cd), fmt_reg(rd, doff), fmt_reg(rs1, s1off), fmt_reg(rs2, s2off));
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Sub { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd });
    }

    #[test]
    fn asm_subi(
        rd in common::arb_dst_reg(),
        rs in common::arb_reg(),
        imm in any::<u16>(),
        cd in any::<bool>(),
    ) {
        let src = format!("SUBI{} {}, {}, {}", fmt_cd(cd), fmt_reg(rd, 0), fmt_reg(rs, 0), imm);
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::SubI { rd, rs, imm, size: 128, cd });
    }

    // --- Logic ---

    #[test]
    fn asm_and(
        rd in common::arb_dst_reg(),
        doff in any::<u8>(),
        rs1 in common::arb_reg(),
        s1off in any::<u8>(),
        rs2 in common::arb_reg(),
        s2off in any::<u8>(),
        cd in any::<bool>(),
    ) {
        let src = format!("AND{} {}, {}, {}",
            fmt_cd(cd), fmt_reg(rd, doff), fmt_reg(rs1, s1off), fmt_reg(rs2, s2off));
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::And { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd });
    }

    #[test]
    fn asm_or(
        rd in common::arb_dst_reg(),
        doff in any::<u8>(),
        rs1 in common::arb_reg(),
        s1off in any::<u8>(),
        rs2 in common::arb_reg(),
        s2off in any::<u8>(),
        cd in any::<bool>(),
    ) {
        let src = format!("OR{} {}, {}, {}",
            fmt_cd(cd), fmt_reg(rd, doff), fmt_reg(rs1, s1off), fmt_reg(rs2, s2off));
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Or { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd });
    }

    // --- Compare ---

    #[test]
    fn asm_cmp(
        rs1 in common::arb_reg(),
        s1off in any::<u8>(),
        rs2 in common::arb_reg(),
        s2off in any::<u8>(),
    ) {
        let src = format!("CMP {}, {}", fmt_reg(rs1, s1off), fmt_reg(rs2, s2off));
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Cmp { rs1, s1off, rs2, s2off, size: 128 });
    }

    // --- Branch ---

    #[test]
    fn asm_br(
        cc in common::arb_condition(),
        target in any::<u16>(),
    ) {
        let src = format!("BR.{} {}", fmt_cc(cc), target);
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Br { cc, target });
    }

    #[test]
    fn asm_brbtst(
        btcc in common::arb_btcond(),
        rs in common::arb_reg(),
        boff in any::<u8>(),
        target in any::<u16>(),
    ) {
        let src = format!("BRBTST {}, {}, {}", fmt_btcc(btcc), fmt_reg(rs, boff), target);
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::BrBtst { btcc, rs, boff, target });
    }

    // --- Header / Cursor ---

    #[test]
    fn asm_stci(incr in any::<u16>()) {
        let src = format!("STCI {}", incr);
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        prop_assert_eq!(decoded, Instruction::Stci { incr });
    }

    #[test]
    fn asm_sth(pid in any::<u8>(), oid in any::<u8>()) {
        let src = format!("STH {}, {}", pid, oid);
        let result = assemble(&src).unwrap();
        let decoded = decode(result.words[0]).unwrap();
        // STH assembler always sets halt: false
        prop_assert_eq!(decoded, Instruction::Sth { pid, oid, halt: false });
    }
}
