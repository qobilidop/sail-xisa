use serde::Serialize;

/// Parser register index. Mirrors the Sail `preg` type.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum Reg {
    /// Parser register 0
    PR0 = 0,
    /// Parser register 1
    PR1 = 1,
    /// Parser register 2
    PR2 = 2,
    /// Parser register 3
    PR3 = 3,
    /// Null / no-register sentinel
    PRN = 4,
}

/// Branch condition codes. Mirrors the Sail `cond_code` type.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum Condition {
    /// Equal
    Eq = 0,
    /// Not equal
    Neq = 1,
    /// Less than
    Lt = 2,
    /// Greater than
    Gt = 3,
    /// Greater than or equal
    Ge = 4,
    /// Less than or equal
    Le = 5,
    /// Always (unconditional)
    Al = 6,
}

/// Bit-test condition for `BrBtst` family instructions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum BitTestCond {
    /// Branch if bit is clear (0)
    Clear = 0,
    /// Branch if bit is set (1)
    Set = 1,
}

/// All Parser ISA instructions. Mirrors the Sail `pinstr` union type.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub enum Instruction {
    // -- Control --

    /// No operation.
    Nop,
    /// Halt the parser; optionally drop the packet.
    Halt { drop: bool },

    // -- Data movement --

    /// Register-to-register move (byte slice copy).
    Mov { rd: Reg, doff: u8, rs: Reg, soff: u8, size: u8, cd: bool },
    /// Move immediate value into a register slice.
    Movi { rd: Reg, doff: u8, imm: u16, size: u8, cd: bool },
    /// Extract bytes from the input packet (by-byte mode).
    Ext { rd: Reg, doff: u8, soff: u16, size: u8, cd: bool },
    /// Extract bytes using the NXTP cursor, advance cursor.
    ExtNxtp { rd: Reg, soff: u16, size: u8, cd: bool },
    /// Move-left (register source, by-byte addressing).
    MovL { rd: Reg, rs1: Reg, o1: u8, sz1: u8, rs2: Reg, o2: u8, sz2: u8, cd: bool },
    /// Move-left with one immediate operand.
    MovLI { rd: Reg, rs: Reg, off: u8, size: u8, imm: u8, cd: bool },
    /// Move-left with two immediate operands.
    MovLII { rd: Reg, rs: Reg, off: u8, size: u8, imm: u8, isz: u8, cd: bool },
    /// Move-right (register source, by-byte addressing).
    MovR { rd: Reg, rs1: Reg, o1: u8, sz1: u8, rs2: Reg, o2: u8, sz2: u8, cd: bool },
    /// Move-right with one immediate operand.
    MovRI { rd: Reg, rs: Reg, off: u8, size: u8, imm: u8, cd: bool },
    /// Move-right with two immediate operands.
    MovRII { rd: Reg, rs: Reg, off: u8, size: u8, imm: u8, isz: u8, cd: bool },

    // -- Arithmetic --

    /// Register add.
    Add { rd: Reg, doff: u8, rs1: Reg, s1off: u8, rs2: Reg, s2off: u8, size: u8, cd: bool },
    /// Add immediate.
    AddI { rd: Reg, rs: Reg, imm: u16, size: u8, cd: bool },
    /// Register subtract.
    Sub { rd: Reg, doff: u8, rs1: Reg, s1off: u8, rs2: Reg, s2off: u8, size: u8, cd: bool },
    /// Subtract immediate (reg - imm).
    SubI { rd: Reg, rs: Reg, imm: u16, size: u8, cd: bool },
    /// Subtract immediate (imm - reg).
    SubII { rd: Reg, imm: u16, rs: Reg, size: u8, cd: bool },

    // -- Logic --

    /// Bitwise AND of two registers.
    And { rd: Reg, doff: u8, rs1: Reg, s1off: u8, rs2: Reg, s2off: u8, size: u8, cd: bool },
    /// AND with immediate.
    AndI { rd: Reg, rs: Reg, imm: u16, size: u8, cd: bool },
    /// Bitwise OR of two registers.
    Or { rd: Reg, doff: u8, rs1: Reg, s1off: u8, rs2: Reg, s2off: u8, size: u8, cd: bool },
    /// OR with immediate.
    OrI { rd: Reg, rs: Reg, imm: u16, size: u8, cd: bool },

    // -- Compare --

    /// Compare two register slices; sets condition flags.
    Cmp { rs1: Reg, s1off: u8, rs2: Reg, s2off: u8, size: u8 },
    /// Compare register slice with immediate (by-byte).
    CmpIBy { rs: Reg, soff: u8, imm: u16, size: u8 },
    /// Compare register slice with immediate (by-bit).
    CmpIBi { rs: Reg, soff: u8, imm: u16, size: u8 },

    // -- Concatenation --

    /// Concatenate two register slices (by-byte result).
    CnctBy { rd: Reg, doff: u8, rs1: Reg, s1off: u8, s1sz: u8, rs2: Reg, s2off: u8, s2sz: u8, cd: bool },
    /// Concatenate two register slices (by-bit result).
    CnctBi { rd: Reg, doff: u8, rs1: Reg, s1off: u8, s1sz: u8, rs2: Reg, s2off: u8, s2sz: u8, cd: bool },

    // -- Branch --

    /// Conditional branch to absolute address.
    Br { cc: Condition, target: u16 },
    /// Branch on bit-test result to absolute address.
    BrBtst { btcc: BitTestCond, rs: Reg, boff: u8, target: u16 },
    /// Conditional branch to next-stage rule.
    BrNs { cc: Condition, rule: u8 },
    /// Conditional branch with NXTP jump mode.
    BrNxtp { cc: Condition, jm: u8, addr_or_rule: u16 },
    /// Branch on bit-test with NXTP jump mode.
    BrBtstNxtp { btcc: BitTestCond, rs: Reg, boff: u8, jm: u8, addr_or_rule: u16 },
    /// Branch on bit-test to next-stage rule.
    BrBtstNs { btcc: BitTestCond, rs: Reg, boff: u8, rule: u8 },

    // -- Header / Cursor --

    /// Set header: record protocol/object IDs and halt.
    Sth { pid: u8, oid: u8, halt: bool },
    /// Set cursor and header with increment.
    Stch { incr: u16, pid: u8, oid: u8, halt: bool },
    /// Set header with cursor increment (no halt flag).
    Sthc { incr: u16, pid: u8, oid: u8 },
    /// Set cursor from a register slice with shift and increment.
    Stc { rs: Reg, soff: u8, ssz: u8, shift: u8, incr: u8 },
    /// Set cursor to an immediate increment value.
    Stci { incr: u16 },

    // -- Store to Struct-0 --

    /// Store register slice to struct-0 output field.
    St { rs: Reg, soff: u8, doff: u8, size: u8, halt: bool },
    /// Store immediate to struct-0 output field.
    StI { imm: u16, doff: u8, size: u8 },

    // -- MAP interface --

    /// Extract bytes from a MAP table entry into a register.
    ExtMap { midx: u8, doff: u8, poff: u16, size: u8 },
    /// Move bytes from a register into a MAP table entry.
    MovMap { midx: u8, doff: u8, rs: Reg, soff: u8, size: u8 },

    // -- Transition / NXTP --

    /// Perform a next-protocol transition using a register key.
    Nxtp { rs: Reg, soff: u8, size: u8 },

    // -- PSEEK --

    /// Seek to a sub-protocol offset and return cursor value.
    Pseek { rd: Reg, doff: u8, rs: Reg, soff: u8, size: u8, cid: u8 },
    /// Seek to a sub-protocol offset using NXTP and return cursor value.
    PseekNxtp { rd: Reg, doff: u8, rs: Reg, soff: u8, size: u8, cid: u8 },
}

/// Per-step simulation result returned to the JS/WASM caller.
#[derive(Debug, Clone, Serialize)]
pub struct StepResult {
    /// Human-readable disassembly of the executed instruction.
    pub instruction: String,
    /// Whether the parser has halted after this step.
    pub halted: bool,
    /// Whether the packet was dropped.
    pub dropped: bool,
    /// Register changes as `(register_name, new_hex_value)` pairs.
    pub reg_changes: Vec<(String, String)>,
    /// Whether any condition flags changed during this step.
    pub flags_changed: bool,
}

/// High-level outcome of executing a single instruction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecResult {
    /// Instruction executed normally; simulation continues.
    Success,
    /// Parser halted (packet accepted).
    Halt,
    /// Parser halted and packet was dropped.
    Drop,
}
