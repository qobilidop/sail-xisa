use proptest::prelude::*;
use xisa::types::*;

/// Strategy for generating a valid Reg (0..=4 maps to PR0..PRN).
pub fn arb_reg() -> impl Strategy<Value = Reg> {
    prop_oneof![
        Just(Reg::PR0),
        Just(Reg::PR1),
        Just(Reg::PR2),
        Just(Reg::PR3),
        Just(Reg::PRN),
    ]
}

/// Strategy for Reg excluding PRN (for destination registers).
pub fn arb_dst_reg() -> impl Strategy<Value = Reg> {
    prop_oneof![
        Just(Reg::PR0),
        Just(Reg::PR1),
        Just(Reg::PR2),
        Just(Reg::PR3),
    ]
}

pub fn arb_condition() -> impl Strategy<Value = Condition> {
    prop_oneof![
        Just(Condition::Eq),
        Just(Condition::Neq),
        Just(Condition::Lt),
        Just(Condition::Gt),
        Just(Condition::Ge),
        Just(Condition::Le),
        Just(Condition::Al),
    ]
}

pub fn arb_btcond() -> impl Strategy<Value = BitTestCond> {
    prop_oneof![
        Just(BitTestCond::Clear),
        Just(BitTestCond::Set),
    ]
}

/// Strategy for generating any valid Instruction.
///
/// Field ranges are constrained to match their encoded bit widths:
/// - Reg fields: 3 bits (0..=4 valid values)
/// - u8 fields: 8 bits (0..=255)
/// - u16 fields: 16 bits (0..=65535)
/// - bool fields: true/false
/// - midx: 4 bits (0..=15)
/// - Condition: 3 bits (0..=6 valid values)
/// - BitTestCond: 1 bit
pub fn arb_instruction() -> impl Strategy<Value = Instruction> {
    prop_oneof![
        // Control
        Just(Instruction::Nop),
        any::<bool>().prop_map(|drop| Instruction::Halt { drop }),

        // Data movement
        (arb_dst_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, doff, rs, soff, size, cd)|
                Instruction::Mov { rd, doff, rs, soff, size, cd }),
        (arb_dst_reg(), any::<u8>(), any::<u16>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, doff, imm, size, cd)|
                Instruction::Movi { rd, doff, imm, size, cd }),
        (arb_dst_reg(), any::<u8>(), any::<u16>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, doff, soff, size, cd)|
                Instruction::Ext { rd, doff, soff, size, cd }),
        (arb_dst_reg(), any::<u16>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, soff, size, cd)|
                Instruction::ExtNxtp { rd, soff, size, cd }),
        (arb_dst_reg(), arb_reg(), any::<u8>(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, rs1, o1, sz1, rs2, o2, sz2, cd)|
                Instruction::MovL { rd, rs1, o1, sz1, rs2, o2, sz2, cd }),
        (arb_dst_reg(), arb_reg(), any::<u8>(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, rs, off, size, imm, cd)|
                Instruction::MovLI { rd, rs, off, size, imm, cd }),
        (arb_dst_reg(), arb_reg(), any::<u8>(), any::<u8>(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, rs, off, size, imm, isz, cd)|
                Instruction::MovLII { rd, rs, off, size, imm, isz, cd }),
        (arb_dst_reg(), arb_reg(), any::<u8>(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, rs1, o1, sz1, rs2, o2, sz2, cd)|
                Instruction::MovR { rd, rs1, o1, sz1, rs2, o2, sz2, cd }),
        (arb_dst_reg(), arb_reg(), any::<u8>(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, rs, off, size, imm, cd)|
                Instruction::MovRI { rd, rs, off, size, imm, cd }),
        (arb_dst_reg(), arb_reg(), any::<u8>(), any::<u8>(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, rs, off, size, imm, isz, cd)|
                Instruction::MovRII { rd, rs, off, size, imm, isz, cd }),

        // Arithmetic
        (arb_dst_reg(), any::<u8>(), arb_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, doff, rs1, s1off, rs2, s2off, size, cd)|
                Instruction::Add { rd, doff, rs1, s1off, rs2, s2off, size, cd }),
        (arb_dst_reg(), arb_reg(), any::<u16>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, rs, imm, size, cd)|
                Instruction::AddI { rd, rs, imm, size, cd }),
        (arb_dst_reg(), any::<u8>(), arb_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, doff, rs1, s1off, rs2, s2off, size, cd)|
                Instruction::Sub { rd, doff, rs1, s1off, rs2, s2off, size, cd }),
        (arb_dst_reg(), arb_reg(), any::<u16>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, rs, imm, size, cd)|
                Instruction::SubI { rd, rs, imm, size, cd }),
        (arb_dst_reg(), any::<u16>(), arb_reg(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, imm, rs, size, cd)|
                Instruction::SubII { rd, imm, rs, size, cd }),

        // Logic
        (arb_dst_reg(), any::<u8>(), arb_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, doff, rs1, s1off, rs2, s2off, size, cd)|
                Instruction::And { rd, doff, rs1, s1off, rs2, s2off, size, cd }),
        (arb_dst_reg(), arb_reg(), any::<u16>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, rs, imm, size, cd)|
                Instruction::AndI { rd, rs, imm, size, cd }),
        (arb_dst_reg(), any::<u8>(), arb_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, doff, rs1, s1off, rs2, s2off, size, cd)|
                Instruction::Or { rd, doff, rs1, s1off, rs2, s2off, size, cd }),
        (arb_dst_reg(), arb_reg(), any::<u16>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, rs, imm, size, cd)|
                Instruction::OrI { rd, rs, imm, size, cd }),

        // Compare
        (arb_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>())
            .prop_map(|(rs1, s1off, rs2, s2off, size)|
                Instruction::Cmp { rs1, s1off, rs2, s2off, size }),
        (arb_reg(), any::<u8>(), any::<u16>(), any::<u8>())
            .prop_map(|(rs, soff, imm, size)|
                Instruction::CmpIBy { rs, soff, imm, size }),
        (arb_reg(), any::<u8>(), any::<u16>(), any::<u8>())
            .prop_map(|(rs, soff, imm, size)|
                Instruction::CmpIBi { rs, soff, imm, size }),

        // Concatenation
        (arb_dst_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd)|
                Instruction::CnctBy { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd }),
        (arb_dst_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd)|
                Instruction::CnctBi { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd }),

        // Branch
        (arb_condition(), any::<u16>())
            .prop_map(|(cc, target)| Instruction::Br { cc, target }),
        (arb_btcond(), arb_reg(), any::<u8>(), any::<u16>())
            .prop_map(|(btcc, rs, boff, target)|
                Instruction::BrBtst { btcc, rs, boff, target }),
        (arb_condition(), any::<u8>())
            .prop_map(|(cc, rule)| Instruction::BrNs { cc, rule }),
        (arb_condition(), any::<u8>(), any::<u16>())
            .prop_map(|(cc, jm, addr_or_rule)|
                Instruction::BrNxtp { cc, jm, addr_or_rule }),
        (arb_btcond(), arb_reg(), any::<u8>(), any::<u8>(), any::<u16>())
            .prop_map(|(btcc, rs, boff, jm, addr_or_rule)|
                Instruction::BrBtstNxtp { btcc, rs, boff, jm, addr_or_rule }),
        (arb_btcond(), arb_reg(), any::<u8>(), any::<u8>())
            .prop_map(|(btcc, rs, boff, rule)|
                Instruction::BrBtstNs { btcc, rs, boff, rule }),

        // Header / Cursor
        (any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(pid, oid, halt)| Instruction::Sth { pid, oid, halt }),
        (any::<u16>(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(incr, pid, oid, halt)|
                Instruction::Stch { incr, pid, oid, halt }),
        (any::<u16>(), any::<u8>(), any::<u8>())
            .prop_map(|(incr, pid, oid)| Instruction::Sthc { incr, pid, oid }),
        (arb_reg(), any::<u8>(), any::<u8>(), any::<u8>(), any::<u8>())
            .prop_map(|(rs, soff, ssz, shift, incr)|
                Instruction::Stc { rs, soff, ssz, shift, incr }),
        any::<u16>().prop_map(|incr| Instruction::Stci { incr }),

        // Store to Struct-0
        (arb_reg(), any::<u8>(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rs, soff, doff, size, halt)|
                Instruction::St { rs, soff, doff, size, halt }),
        (any::<u16>(), any::<u8>(), any::<u8>())
            .prop_map(|(imm, doff, size)| Instruction::StI { imm, doff, size }),

        // MAP interface
        (0..=15u8, any::<u8>(), any::<u16>(), any::<u8>())
            .prop_map(|(midx, doff, poff, size)|
                Instruction::ExtMap { midx, doff, poff, size }),
        (0..=15u8, any::<u8>(), arb_reg(), any::<u8>(), any::<u8>())
            .prop_map(|(midx, doff, rs, soff, size)|
                Instruction::MovMap { midx, doff, rs, soff, size }),

        // Transition / NXTP
        (arb_reg(), any::<u8>(), any::<u8>())
            .prop_map(|(rs, soff, size)| Instruction::Nxtp { rs, soff, size }),

        // PSEEK
        (arb_dst_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<u8>())
            .prop_map(|(rd, doff, rs, soff, size, cid)|
                Instruction::Pseek { rd, doff, rs, soff, size, cid }),
        (arb_dst_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<u8>())
            .prop_map(|(rd, doff, rs, soff, size, cid)|
                Instruction::PseekNxtp { rd, doff, rs, soff, size, cid }),
    ]
}
