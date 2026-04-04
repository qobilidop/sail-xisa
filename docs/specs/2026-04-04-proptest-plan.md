# Property-Based Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add proptest-based property tests verifying encode/decode roundtrips and assembler/decode consistency for all parser ISA instructions.

**Architecture:** Shared instruction-generation strategies in `tests/common/mod.rs`, used by two integration test files — one for encode/decode roundtrips, one for assemble/decode consistency. All proptest infrastructure is dev-dependency only.

**Tech Stack:** Rust, proptest 1.x

---

### Task 1: Add proptest dependency and shared strategy module

**Files:**
- Modify: `playground/Cargo.toml`
- Create: `playground/tests/common/mod.rs`

- [ ] **Step 1: Add proptest as a dev-dependency**

In `playground/Cargo.toml`, add:

```toml
[dev-dependencies]
proptest = "1"
```

- [ ] **Step 2: Create the shared strategy module**

Create `playground/tests/common/mod.rs` with strategies for generating random valid `Instruction` values:

```rust
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
        (arb_dst_reg(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), arb_reg(), any::<u8>(), any::<u8>(), any::<bool>())
            .prop_map(|(rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd)|
                Instruction::MovL { rd, rs1: rs1, o1: s1off, sz1: s1sz, rs2: rs2, o2: s2off, sz2: s2sz, cd }),
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
```

- [ ] **Step 3: Verify it compiles**

Run: `./dev.sh bash -c "cd playground && cargo test --no-run 2>&1 | tail -5"`
Expected: compiles without errors

- [ ] **Step 4: Commit**

```bash
git add playground/Cargo.toml playground/tests/common/mod.rs
git commit -m "Add proptest dependency and shared instruction strategy"
```

---

### Task 2: Encode/decode roundtrip tests (Suite A)

**Files:**
- Create: `playground/tests/proptest_encode_decode.rs`

- [ ] **Step 1: Create the encode/decode roundtrip test**

Create `playground/tests/proptest_encode_decode.rs`:

```rust
mod common;

use proptest::prelude::*;
use xisa::decode::decode;
use xisa::encode::encode;

proptest! {
    #[test]
    fn encode_decode_roundtrip(instr in common::arb_instruction()) {
        let word = encode(&instr);
        let decoded = decode(word).expect("decode failed for a valid encoded instruction");
        prop_assert_eq!(decoded, instr);
    }
}
```

- [ ] **Step 2: Run the tests**

Run: `./dev.sh bash -c "cd playground && cargo test --test proptest_encode_decode -- --nocapture 2>&1 | tail -20"`
Expected: all proptest cases pass (256 cases by default)

- [ ] **Step 3: Commit**

```bash
git add playground/tests/proptest_encode_decode.rs
git commit -m "Add proptest encode/decode roundtrip tests"
```

---

### Task 3: Assemble/decode consistency tests (Suite B)

**Files:**
- Create: `playground/tests/proptest_assemble.rs`

- [ ] **Step 1: Create the assemble/decode consistency tests**

Create `playground/tests/proptest_assemble.rs`. Each test generates random operands for one assembler-supported instruction, formats as assembly text, assembles, decodes, and compares.

The assembler currently supports these instructions (from `parse_instruction` in assembler.rs): NOP, HALT, HALTDROP, MOV, MOVI, EXT, ADD, ADDI, SUB, SUBI, AND, OR, CMP, BR.cc, BRBTST, STCI, STH.

Important: the assembler applies default values for several fields:
- MOV: `size: 128`
- ADD/SUB/AND/OR: `size: 128`
- ADDI/SUBI: `size: 128`
- CMP: `size: 128`
- EXT: `doff: 0`

The generated instructions must use these defaults for the comparison to succeed.

```rust
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
```

- [ ] **Step 2: Run the tests**

Run: `./dev.sh bash -c "cd playground && cargo test --test proptest_assemble -- --nocapture 2>&1 | tail -20"`
Expected: all proptest cases pass

- [ ] **Step 3: Run all tests together**

Run: `./dev.sh bash -c "cd playground && cargo test 2>&1 | grep 'test result'"`
Expected: all test suites pass (unit tests + both proptest suites)

- [ ] **Step 4: Commit**

```bash
git add playground/tests/proptest_assemble.rs
git commit -m "Add proptest assemble/decode consistency tests"
```
