use std::collections::HashMap;
use std::fmt;

use crate::encode::encode;
use crate::types::*;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// An error produced during assembly, tagged with the source line number.
#[derive(Debug, Clone)]
pub struct AsmError {
    pub line: usize,
    pub message: String,
}

impl fmt::Display for AsmError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "line {}: {}", self.line, self.message)
    }
}

/// The result of a successful assembly: encoded words plus a source-line map.
#[derive(Debug, Clone)]
pub struct AsmResult {
    /// Encoded 64-bit instruction words in program order.
    pub words: Vec<u64>,
    /// `line_map[i]` is the 1-based source line number of `words[i]`.
    pub line_map: Vec<usize>,
}

// ---------------------------------------------------------------------------
// Internal intermediate representation
// ---------------------------------------------------------------------------

/// A branch target that may be numeric or still a label name after pass 1.
#[derive(Debug, Clone)]
enum BrTarget {
    Addr(u16),
    Label(String),
}

/// An instruction in the intermediate representation (after pass 1, before
/// label resolution in pass 2).
#[derive(Debug, Clone)]
enum IrInstr {
    Resolved(Instruction),
    Br { cc: Condition, target: BrTarget },
    BrBtst { btcc: BitTestCond, rs: Reg, boff: u8, target: BrTarget },
}

/// A parsed line: either a real instruction or a skipped line.
#[derive(Debug)]
struct ParsedLine {
    /// 1-based source line number.
    line_num: usize,
    instr: IrInstr,
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

/// Assemble `source` assembly text into binary words.
///
/// Returns `Ok(AsmResult)` on success, or `Err(Vec<AsmError>)` with all
/// errors accumulated during parsing.
pub fn assemble(source: &str) -> Result<AsmResult, Vec<AsmError>> {
    let mut errors: Vec<AsmError> = Vec::new();

    // -----------------------------------------------------------------------
    // Pass 1: collect labels and parse instructions
    // -----------------------------------------------------------------------
    let mut labels: HashMap<String, u16> = HashMap::new();
    let mut ir: Vec<ParsedLine> = Vec::new();
    let mut pc: u16 = 0;

    for (idx, raw_line) in source.lines().enumerate() {
        let line_num = idx + 1;

        // Strip inline comments and surrounding whitespace.
        let trimmed = strip_comment(raw_line).trim().to_string();

        if trimmed.is_empty() {
            continue;
        }

        // Label definition (ends with ':').
        if let Some(label_name) = trimmed.strip_suffix(':') {
            let label_name = label_name.trim().to_string();
            if label_name.is_empty() {
                errors.push(AsmError { line: line_num, message: "empty label name".into() });
            } else if labels.contains_key(&label_name) {
                errors.push(AsmError {
                    line: line_num,
                    message: format!("duplicate label '{}'", label_name),
                });
            } else {
                labels.insert(label_name, pc);
            }
            continue;
        }

        // Parse an instruction.
        match parse_instruction(&trimmed, line_num) {
            Ok(instr) => {
                ir.push(ParsedLine { line_num, instr });
                pc += 1;
            }
            Err(e) => errors.push(e),
        }
    }

    // -----------------------------------------------------------------------
    // Pass 2: resolve label references
    // -----------------------------------------------------------------------
    let mut resolved: Vec<ParsedLine> = Vec::with_capacity(ir.len());
    for pl in ir {
        match pl.instr {
            IrInstr::Br { cc, target: BrTarget::Label(ref name) } => {
                match labels.get(name) {
                    Some(&addr) => resolved.push(ParsedLine {
                        line_num: pl.line_num,
                        instr: IrInstr::Resolved(Instruction::Br { cc, target: addr }),
                    }),
                    None => errors.push(AsmError {
                        line: pl.line_num,
                        message: format!("undefined label '{}'", name),
                    }),
                }
            }
            IrInstr::BrBtst { btcc, rs, boff, target: BrTarget::Label(ref name) } => {
                match labels.get(name) {
                    Some(&addr) => resolved.push(ParsedLine {
                        line_num: pl.line_num,
                        instr: IrInstr::Resolved(Instruction::BrBtst { btcc, rs, boff, target: addr }),
                    }),
                    None => errors.push(AsmError {
                        line: pl.line_num,
                        message: format!("undefined label '{}'", name),
                    }),
                }
            }
            IrInstr::Br { cc, target: BrTarget::Addr(addr) } => {
                resolved.push(ParsedLine {
                    line_num: pl.line_num,
                    instr: IrInstr::Resolved(Instruction::Br { cc, target: addr }),
                });
            }
            IrInstr::BrBtst { btcc, rs, boff, target: BrTarget::Addr(addr) } => {
                resolved.push(ParsedLine {
                    line_num: pl.line_num,
                    instr: IrInstr::Resolved(Instruction::BrBtst { btcc, rs, boff, target: addr }),
                });
            }
            IrInstr::Resolved(_) => resolved.push(pl),
        }
    }

    if !errors.is_empty() {
        return Err(errors);
    }

    // -----------------------------------------------------------------------
    // Pass 3: encode to u64
    // -----------------------------------------------------------------------
    let mut words = Vec::with_capacity(resolved.len());
    let mut line_map = Vec::with_capacity(resolved.len());
    for pl in resolved {
        if let IrInstr::Resolved(ref inst) = pl.instr {
            words.push(encode(inst));
            line_map.push(pl.line_num);
        }
    }

    Ok(AsmResult { words, line_map })
}

// ---------------------------------------------------------------------------
// Line parsing
// ---------------------------------------------------------------------------

/// Remove everything from the first `;` onwards.
fn strip_comment(line: &str) -> &str {
    if let Some(pos) = line.find(';') {
        &line[..pos]
    } else {
        line
    }
}

/// Parse a single (already comment-stripped, trimmed) instruction line.
fn parse_instruction(line: &str, line_num: usize) -> Result<IrInstr, AsmError> {
    // Split mnemonic from operands.
    let (mnemonic_raw, operands_str) = match line.find(|c: char| c.is_whitespace()) {
        Some(pos) => (&line[..pos], line[pos..].trim()),
        None => (line, ""),
    };

    let mnemonic_upper = mnemonic_raw.to_uppercase();

    // Split operands on commas; filter empty tokens.
    let operands: Vec<&str> = if operands_str.is_empty() {
        Vec::new()
    } else {
        operands_str.split(',').map(|s| s.trim()).filter(|s| !s.is_empty()).collect()
    };

    // Determine if `.CD` modifier is present and isolate the base mnemonic.
    let (base_mnemonic, cd) = parse_mnemonic_cd(&mnemonic_upper);

    // Dispatch on base mnemonic.
    match base_mnemonic.as_str() {
        // ---- Control ----
        "NOP" => {
            expect_operands(&operands, 0, "NOP", line_num)?;
            Ok(IrInstr::Resolved(Instruction::Nop))
        }
        "HALT" => {
            expect_operands(&operands, 0, "HALT", line_num)?;
            Ok(IrInstr::Resolved(Instruction::Halt { drop: false }))
        }
        "HALTDROP" => {
            expect_operands(&operands, 0, "HALTDROP", line_num)?;
            Ok(IrInstr::Resolved(Instruction::Halt { drop: true }))
        }

        // ---- Data movement ----
        "MOV" => {
            expect_operands(&operands, 2, "MOV", line_num)?;
            let (rd, doff) = parse_reg_offset(operands[0], line_num)?;
            let (rs, soff) = parse_reg_offset(operands[1], line_num)?;
            Ok(IrInstr::Resolved(Instruction::Mov { rd, doff, rs, soff, size: 128, cd }))
        }
        "MOVI" => {
            expect_operands(&operands, 3, "MOVI", line_num)?;
            let (rd, doff) = parse_reg_offset(operands[0], line_num)?;
            let imm = parse_u16(operands[1], line_num)?;
            let size = parse_u8(operands[2], line_num)?;
            Ok(IrInstr::Resolved(Instruction::Movi { rd, doff, imm, size, cd }))
        }
        "EXT" => {
            expect_operands(&operands, 3, "EXT", line_num)?;
            let (rd, _doff) = parse_reg_offset(operands[0], line_num)?;
            let soff = parse_u16(operands[1], line_num)?;
            let size = parse_u8(operands[2], line_num)?;
            Ok(IrInstr::Resolved(Instruction::Ext { rd, doff: 0, soff, size, cd }))
        }

        // ---- Arithmetic ----
        "ADD" => {
            expect_operands(&operands, 3, "ADD", line_num)?;
            let (rd, doff) = parse_reg_offset(operands[0], line_num)?;
            let (rs1, s1off) = parse_reg_offset(operands[1], line_num)?;
            let (rs2, s2off) = parse_reg_offset(operands[2], line_num)?;
            Ok(IrInstr::Resolved(Instruction::Add { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd }))
        }
        "ADDI" => {
            expect_operands(&operands, 3, "ADDI", line_num)?;
            let (rd, _) = parse_reg_offset(operands[0], line_num)?;
            let (rs, _) = parse_reg_offset(operands[1], line_num)?;
            let imm = parse_imm16(operands[2], line_num)?;
            Ok(IrInstr::Resolved(Instruction::AddI { rd, rs, imm, size: 128, cd }))
        }
        "SUB" => {
            expect_operands(&operands, 3, "SUB", line_num)?;
            let (rd, doff) = parse_reg_offset(operands[0], line_num)?;
            let (rs1, s1off) = parse_reg_offset(operands[1], line_num)?;
            let (rs2, s2off) = parse_reg_offset(operands[2], line_num)?;
            Ok(IrInstr::Resolved(Instruction::Sub { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd }))
        }
        "SUBI" => {
            expect_operands(&operands, 3, "SUBI", line_num)?;
            let (rd, _) = parse_reg_offset(operands[0], line_num)?;
            let (rs, _) = parse_reg_offset(operands[1], line_num)?;
            let imm = parse_imm16(operands[2], line_num)?;
            Ok(IrInstr::Resolved(Instruction::SubI { rd, rs, imm, size: 128, cd }))
        }

        // ---- Logic ----
        "AND" => {
            expect_operands(&operands, 3, "AND", line_num)?;
            let (rd, doff) = parse_reg_offset(operands[0], line_num)?;
            let (rs1, s1off) = parse_reg_offset(operands[1], line_num)?;
            let (rs2, s2off) = parse_reg_offset(operands[2], line_num)?;
            Ok(IrInstr::Resolved(Instruction::And { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd }))
        }
        "OR" => {
            expect_operands(&operands, 3, "OR", line_num)?;
            let (rd, doff) = parse_reg_offset(operands[0], line_num)?;
            let (rs1, s1off) = parse_reg_offset(operands[1], line_num)?;
            let (rs2, s2off) = parse_reg_offset(operands[2], line_num)?;
            Ok(IrInstr::Resolved(Instruction::Or { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd }))
        }

        // ---- Compare ----
        "CMP" => {
            expect_operands(&operands, 2, "CMP", line_num)?;
            let (rs1, s1off) = parse_reg_offset(operands[0], line_num)?;
            let (rs2, s2off) = parse_reg_offset(operands[1], line_num)?;
            Ok(IrInstr::Resolved(Instruction::Cmp { rs1, s1off, rs2, s2off, size: 128 }))
        }

        // ---- Branches ----
        // BR.cc form — the condition is part of the mnemonic suffix.
        s if s.starts_with("BR.") => {
            let cond_str = &s["BR.".len()..];
            let cc = parse_condition(cond_str, line_num)?;
            expect_operands(&operands, 1, "BR.<cc>", line_num)?;
            let target = parse_br_target(operands[0], line_num)?;
            Ok(IrInstr::Br { cc, target })
        }
        "BRBTST" => {
            expect_operands(&operands, 3, "BRBTST", line_num)?;
            let btcc = parse_btcond(operands[0], line_num)?;
            let (rs, boff) = parse_reg_offset(operands[1], line_num)?;
            let target = parse_br_target(operands[2], line_num)?;
            Ok(IrInstr::BrBtst { btcc, rs, boff, target })
        }

        // ---- Header / cursor ----
        "STCI" => {
            expect_operands(&operands, 1, "STCI", line_num)?;
            let incr = parse_u16(operands[0], line_num)?;
            Ok(IrInstr::Resolved(Instruction::Stci { incr }))
        }
        "STH" => {
            expect_operands(&operands, 2, "STH", line_num)?;
            let pid = parse_u8(operands[0], line_num)?;
            let oid = parse_u8(operands[1], line_num)?;
            Ok(IrInstr::Resolved(Instruction::Sth { pid, oid, halt: false }))
        }

        other => Err(AsmError {
            line: line_num,
            message: format!("unknown instruction '{}'", other),
        }),
    }
}

// ---------------------------------------------------------------------------
// Mnemonic helpers
// ---------------------------------------------------------------------------

/// Split a mnemonic into (base, cd_flag).
/// The `.CD` suffix is stripped; a remaining condition suffix (e.g., `.Z`) is
/// left as part of the base.
fn parse_mnemonic_cd(mnemonic: &str) -> (String, bool) {
    // `.CD` can appear alone or before nothing else (e.g. `EXT.CD`).
    // We check for `.CD` at the end (case-insensitive already uppercased).
    if let Some(base) = mnemonic.strip_suffix(".CD") {
        return (base.to_string(), true);
    }
    (mnemonic.to_string(), false)
}

// ---------------------------------------------------------------------------
// Operand-parsing helpers
// ---------------------------------------------------------------------------

/// Parse "PR0" or "PR0.8" → (Reg, offset_bytes).
pub fn parse_reg_offset(s: &str, line_num: usize) -> Result<(Reg, u8), AsmError> {
    let upper = s.to_uppercase();
    let (reg_str, off_str) = match upper.find('.') {
        Some(pos) => (&upper[..pos], Some(&upper[pos + 1..])),
        None => (upper.as_str(), None),
    };
    let reg = parse_reg(reg_str, line_num)?;
    let off = match off_str {
        Some(o) => parse_u8(o, line_num)?,
        None => 0,
    };
    Ok((reg, off))
}

fn parse_reg(s: &str, line_num: usize) -> Result<Reg, AsmError> {
    match s {
        "PR0" => Ok(Reg::PR0),
        "PR1" => Ok(Reg::PR1),
        "PR2" => Ok(Reg::PR2),
        "PR3" => Ok(Reg::PR3),
        "PRN" => Ok(Reg::PRN),
        _ => Err(AsmError { line: line_num, message: format!("unknown register '{}'", s) }),
    }
}

/// Parse a non-negative integer literal (decimal, 0x hex, 0b binary) as u8.
pub fn parse_u8(s: &str, line_num: usize) -> Result<u8, AsmError> {
    let v = parse_integer(s, line_num)?;
    if v > u8::MAX as u64 {
        return Err(AsmError { line: line_num, message: format!("value {} out of range for u8", v) });
    }
    Ok(v as u8)
}

/// Parse a non-negative integer literal as u16.
pub fn parse_u16(s: &str, line_num: usize) -> Result<u16, AsmError> {
    let v = parse_integer(s, line_num)?;
    if v > u16::MAX as u64 {
        return Err(AsmError { line: line_num, message: format!("value {} out of range for u16", v) });
    }
    Ok(v as u16)
}

/// Parse a signed or unsigned 16-bit immediate (for ADDI/SUBI style).
pub fn parse_imm16(s: &str, line_num: usize) -> Result<u16, AsmError> {
    // Support negative values via two's complement.
    if let Some(neg) = s.strip_prefix('-') {
        let v = parse_integer(neg, line_num)?;
        if v > 0x8000 {
            return Err(AsmError { line: line_num, message: format!("-{} out of range for imm16", v) });
        }
        return Ok((-(v as i32)) as u16);
    }
    parse_u16(s, line_num)
}

fn parse_integer(s: &str, line_num: usize) -> Result<u64, AsmError> {
    let s = s.trim();
    if let Some(hex) = s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")) {
        u64::from_str_radix(hex, 16).map_err(|_| AsmError {
            line: line_num,
            message: format!("invalid hex literal '{}'", s),
        })
    } else if let Some(bin) = s.strip_prefix("0b").or_else(|| s.strip_prefix("0B")) {
        u64::from_str_radix(bin, 2).map_err(|_| AsmError {
            line: line_num,
            message: format!("invalid binary literal '{}'", s),
        })
    } else {
        s.parse::<u64>().map_err(|_| AsmError {
            line: line_num,
            message: format!("invalid integer literal '{}'", s),
        })
    }
}

/// Parse a bit-test condition: "CLR"/"0" → Clear, "SET"/"1" → Set.
pub fn parse_btcond(s: &str, line_num: usize) -> Result<BitTestCond, AsmError> {
    match s.to_uppercase().as_str() {
        "CLR" | "0" => Ok(BitTestCond::Clear),
        "SET" | "1" => Ok(BitTestCond::Set),
        _ => Err(AsmError { line: line_num, message: format!("unknown btcond '{}'", s) }),
    }
}

/// Parse a condition code suffix string.
fn parse_condition(s: &str, line_num: usize) -> Result<Condition, AsmError> {
    match s.to_uppercase().as_str() {
        "Z" | "EQ" => Ok(Condition::Eq),
        "NZ" | "NEQ" => Ok(Condition::Neq),
        "LT" => Ok(Condition::Lt),
        "GT" => Ok(Condition::Gt),
        "GE" => Ok(Condition::Ge),
        "LE" => Ok(Condition::Le),
        "AL" => Ok(Condition::Al),
        _ => Err(AsmError { line: line_num, message: format!("unknown condition '{}'", s) }),
    }
}

/// Parse a branch target: a numeric address or a label name.
fn parse_br_target(s: &str, line_num: usize) -> Result<BrTarget, AsmError> {
    // Try numeric first.
    if let Ok(v) = parse_integer(s, line_num) {
        if v > u16::MAX as u64 {
            return Err(AsmError { line: line_num, message: format!("branch target {} out of range", v) });
        }
        return Ok(BrTarget::Addr(v as u16));
    }
    // Otherwise treat as a label name.
    Ok(BrTarget::Label(s.to_string()))
}

/// Validate that the operand count matches `expected`.
pub fn expect_operands(
    operands: &[&str],
    expected: usize,
    mnemonic: &str,
    line_num: usize,
) -> Result<(), AsmError> {
    if operands.len() != expected {
        Err(AsmError {
            line: line_num,
            message: format!(
                "'{}' expects {} operand(s), got {}",
                mnemonic,
                expected,
                operands.len()
            ),
        })
    } else {
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decode::decode;

    #[test]
    fn test_assemble_nop_halt() {
        let result = assemble("NOP\nHALT").unwrap();
        assert_eq!(result.words.len(), 2);
        assert_eq!(result.words[0], 0); // NOP encodes to all-zero
    }

    #[test]
    fn test_assemble_with_comments() {
        let src = "; leading comment\nNOP ; inline\n; trailing\nHALT";
        let result = assemble(src).unwrap();
        assert_eq!(result.words.len(), 2);
    }

    #[test]
    fn test_assemble_movi() {
        let result = assemble("MOVI PR0, 0x1234, 16").unwrap();
        assert_eq!(result.words.len(), 1);
        let inst = decode(result.words[0]).unwrap();
        if let Instruction::Movi { rd, imm, size, cd, .. } = inst {
            assert_eq!(rd, Reg::PR0);
            assert_eq!(imm, 0x1234);
            assert_eq!(size, 16);
            assert!(!cd);
        } else {
            panic!("expected Movi, got {:?}", inst);
        }
    }

    #[test]
    fn test_assemble_cd_modifier() {
        let result = assemble("EXT.CD PR1, 8, 32").unwrap();
        assert_eq!(result.words.len(), 1);
        let inst = decode(result.words[0]).unwrap();
        if let Instruction::Ext { cd, rd, soff, size, .. } = inst {
            assert!(cd, "expected cd=true");
            assert_eq!(rd, Reg::PR1);
            assert_eq!(soff, 8);
            assert_eq!(size, 32);
        } else {
            panic!("expected Ext, got {:?}", inst);
        }
    }

    #[test]
    fn test_assemble_branch_condition() {
        let result = assemble("BR.Z 42").unwrap();
        assert_eq!(result.words.len(), 1);
        let inst = decode(result.words[0]).unwrap();
        if let Instruction::Br { cc, target } = inst {
            assert_eq!(cc, Condition::Eq);
            assert_eq!(target, 42);
        } else {
            panic!("expected Br, got {:?}", inst);
        }
    }

    #[test]
    fn test_assemble_branch_label() {
        let src = "BR.Z loop\nNOP\nloop:\n  NOP";
        let result = assemble(src).unwrap();
        // BR.Z loop → PC 0; NOP → PC 1; label "loop" → PC 2; NOP → PC 2
        assert_eq!(result.words.len(), 3);
        let inst = decode(result.words[0]).unwrap();
        if let Instruction::Br { target, .. } = inst {
            assert_eq!(target, 2);
        } else {
            panic!("expected Br");
        }
    }

    #[test]
    fn test_assemble_error_unknown_instruction() {
        let err = assemble("FOOBAR").unwrap_err();
        assert!(!err.is_empty());
        assert!(err[0].message.contains("FOOBAR"));
    }

    #[test]
    fn test_assemble_error_wrong_operand_count() {
        let err = assemble("EXT PR0").unwrap_err();
        assert!(!err.is_empty());
    }

    #[test]
    fn test_line_map() {
        let src = "; comment\nNOP\n\nHALT";
        let result = assemble(src).unwrap();
        assert_eq!(result.words.len(), 2);
        assert_eq!(result.line_map[0], 2); // NOP is on line 2
        assert_eq!(result.line_map[1], 4); // HALT is on line 4
    }

    #[test]
    fn test_hex_and_binary_immediates() {
        // 0xFF = 255, 0b1010 = 10
        let result = assemble("MOVI PR0, 0xFF, 0b1000").unwrap();
        assert_eq!(result.words.len(), 1);
        let inst = decode(result.words[0]).unwrap();
        if let Instruction::Movi { imm, size, .. } = inst {
            assert_eq!(imm, 0xFF);
            assert_eq!(size, 8); // 0b1000 = 8
        } else {
            panic!("expected Movi");
        }
    }
}
