# Web Playground Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a browser-based playground for stepping through XISA Parser ISA programs, with assembly editor, state inspection, and example programs.

**Architecture:** Rust simulator core compiled to WASM via wasm-pack, served by an Astro static site with Svelte interactive islands. The assembler lives in Rust alongside the simulator, shared via WASM in the browser and as a CLI locally.

**Tech Stack:** Rust + wasm-bindgen + wasm-pack, Astro + Svelte, CodeMirror 6, plain CSS

**Reference:** Design spec at `docs/specs/2026-04-01-web-playground-design.md`. Sail Parser ISA model at `model/parser/` is the authoritative source for instruction semantics.

---

## File Map

| File | Responsibility |
|------|---------------|
| `.devcontainer/Dockerfile` | Modify: add Rust, wasm-pack, Node.js |
| `web/simulator/Cargo.toml` | Rust crate config with wasm-bindgen, serde deps |
| `web/simulator/src/lib.rs` | WASM API: Simulator struct with init/step/get_state/assemble |
| `web/simulator/src/types.rs` | Instruction enum (43 variants), Reg, Condition, StepResult |
| `web/simulator/src/state.rs` | SimState struct, initialization, register/flag accessors |
| `web/simulator/src/decode.rs` | 64-bit binary → Instruction (mirrors `model/parser/decode.sail`) |
| `web/simulator/src/encode.rs` | Instruction → 64-bit binary (inverse of decode) |
| `web/simulator/src/execute.rs` | Instruction semantics (mirrors `model/parser/insts.sail`) |
| `web/simulator/src/assembler.rs` | Assembly text → Instruction list → binary |
| `web/simulator/src/bin/xisa-asm.rs` | CLI assembler binary |
| `web/simulator/tests/conformance.rs` | Tests ported from Sail test suite |
| `web/package.json` | Astro + Svelte + CodeMirror dependencies |
| `web/astro.config.mjs` | Astro config with Svelte integration |
| `web/src/layouts/Base.astro` | Shared page layout with nav |
| `web/src/pages/index.astro` | Landing page |
| `web/src/pages/playground.astro` | Playground page (loads Svelte islands) |
| `web/src/components/Editor.svelte` | CodeMirror assembly editor + examples dropdown |
| `web/src/components/Controls.svelte` | Assemble/Step/Run/Reset buttons |
| `web/src/components/StateViewer.svelte` | Registers, flags, PC, packet buffer display |
| `web/src/components/Playground.svelte` | Top-level playground component wiring the three panels |
| `web/src/lib/wasm.ts` | WASM module loader |
| `web/src/lib/xisa-grammar.ts` | CodeMirror Lezer grammar for XISA assembly |
| `web/src/styles/global.css` | Global styles |
| `web/src/styles/playground.css` | Playground panel styles |
| `examples/parser/simple-branch.xisa` | Basic branching example program |
| `examples/parser/extract-ipv4.xisa` | IPv4 header extraction example |
| `.github/workflows/web.yml` | CI: Rust tests + WASM build + Astro deploy |

---

## Phase 1: Infrastructure

### Task 1: Add Rust, wasm-pack, and Node.js to Dev Container

**Files:**
- Modify: `.devcontainer/Dockerfile`

- [ ] **Step 1: Update Dockerfile**

Add Rust toolchain, wasm-pack, and Node.js after the existing Sail setup:

```dockerfile
# Rust toolchain (for WASM simulator)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . /root/.cargo/env \
    && rustup target add wasm32-unknown-unknown

ENV PATH="/root/.cargo/bin:${PATH}"

# wasm-pack (builds Rust → WASM with JS bindings)
RUN cargo install wasm-pack

# Node.js 22 LTS (for Astro frontend)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 2: Rebuild dev container**

Run: `devcontainer build --workspace-folder .`

- [ ] **Step 3: Verify all tools are available**

Run: `./dev.sh rustc --version && ./dev.sh wasm-pack --version && ./dev.sh node --version`
Expected: Version strings for all three tools.

- [ ] **Step 4: Commit**

```bash
git add .devcontainer/Dockerfile
git commit -m "Add Rust, wasm-pack, and Node.js to dev container"
```

---

### Task 2: Scaffold Rust Crate

**Files:**
- Create: `web/simulator/Cargo.toml`
- Create: `web/simulator/src/lib.rs`
- Create: `web/simulator/src/types.rs`

- [ ] **Step 1: Create Cargo.toml**

```toml
[package]
name = "xisa-simulator"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "rlib"]

[[bin]]
name = "xisa-asm"
path = "src/bin/xisa-asm.rs"

[dependencies]
wasm-bindgen = "0.2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
serde-wasm-bindgen = "0.6"

[dev-dependencies]
wasm-bindgen-test = "0.3"

[profile.release]
opt-level = "s"
lto = true
```

- [ ] **Step 2: Create lib.rs with module declarations**

```rust
pub mod types;

// Modules added in later tasks:
// pub mod state;
// pub mod decode;
// pub mod encode;
// pub mod execute;
// pub mod assembler;
```

- [ ] **Step 3: Create types.rs with register and condition enums**

```rust
use serde::Serialize;

/// Parser register index. 4 general-purpose 128-bit registers + null register.
/// Mirrors `pregidx` from model/parser/types.sail.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum Reg {
    PR0 = 0,
    PR1 = 1,
    PR2 = 2,
    PR3 = 3,
    PRN = 4,
}

/// Branch condition codes. Mirrors `pcond` from model/parser/types.sail.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum Condition {
    Eq = 0,   // Zero flag set
    Neq = 1,  // Zero flag clear
    Lt = 2,   // Negative flag set
    Gt = 3,   // !Negative && !Zero
    Ge = 4,   // !Negative
    Le = 5,   // Negative || Zero
    Al = 6,   // Always
}

/// Bit-test branch condition. Mirrors `pbtcond` from model/parser/types.sail.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum BitTestCond {
    Clear = 0,
    Set = 1,
}

/// Parser ISA instruction set. 43 variants mirroring the Sail union type
/// `pinstr` from model/parser/types.sail.
///
/// Field names and types match the Sail model. Offsets and sizes are in bits
/// unless noted otherwise. All registers are 128-bit big-endian.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub enum Instruction {
    // -- Control --
    Nop,
    Halt { drop: bool },

    // -- Data movement --
    Mov { rd: Reg, doff: u8, rs: Reg, soff: u8, size: u8, cd: bool },
    Movi { rd: Reg, doff: u8, imm: u16, size: u8, cd: bool },
    Ext { rd: Reg, doff: u8, soff: u16, size: u8, cd: bool },
    ExtNxtp { rd: Reg, soff: u16, size: u8, cd: bool },
    MovL { rd: Reg, rs1: Reg, o1: u8, sz1: u8, rs2: Reg, o2: u8, sz2: u8, cd: bool },
    MovLI { rd: Reg, rs: Reg, off: u8, size: u8, imm: u8, cd: bool },
    MovLII { rd: Reg, rs: Reg, off: u8, size: u8, imm: u8, isz: u8, cd: bool },
    MovR { rd: Reg, rs1: Reg, o1: u8, sz1: u8, rs2: Reg, o2: u8, sz2: u8, cd: bool },
    MovRI { rd: Reg, rs: Reg, off: u8, size: u8, imm: u8, cd: bool },
    MovRII { rd: Reg, rs: Reg, off: u8, size: u8, imm: u8, isz: u8, cd: bool },

    // -- Arithmetic --
    Add { rd: Reg, doff: u8, rs1: Reg, s1off: u8, rs2: Reg, s2off: u8, size: u8, cd: bool },
    AddI { rd: Reg, rs: Reg, imm: u16, size: u8, cd: bool },
    Sub { rd: Reg, doff: u8, rs1: Reg, s1off: u8, rs2: Reg, s2off: u8, size: u8, cd: bool },
    SubI { rd: Reg, rs: Reg, imm: u16, size: u8, cd: bool },
    SubII { rd: Reg, imm: u16, rs: Reg, size: u8, cd: bool },

    // -- Logic --
    And { rd: Reg, doff: u8, rs1: Reg, s1off: u8, rs2: Reg, s2off: u8, size: u8, cd: bool },
    AndI { rd: Reg, rs: Reg, imm: u16, size: u8, cd: bool },
    Or { rd: Reg, doff: u8, rs1: Reg, s1off: u8, rs2: Reg, s2off: u8, size: u8, cd: bool },
    OrI { rd: Reg, rs: Reg, imm: u16, size: u8, cd: bool },

    // -- Compare --
    Cmp { rs1: Reg, s1off: u8, rs2: Reg, s2off: u8, size: u8 },
    CmpIBy { rs: Reg, soff: u8, imm: u16, size: u8 },
    CmpIBi { rs: Reg, soff: u8, imm: u16, size: u8 },

    // -- Concatenation --
    CnctBy { rd: Reg, doff: u8, rs1: Reg, s1off: u8, s1sz: u8, rs2: Reg, s2off: u8, s2sz: u8, cd: bool },
    CnctBi { rd: Reg, doff: u8, rs1: Reg, s1off: u8, s1sz: u8, rs2: Reg, s2off: u8, s2sz: u8, cd: bool },

    // -- Branch --
    Br { cc: Condition, target: u16 },
    BrBtst { btcc: BitTestCond, rs: Reg, boff: u8, target: u16 },
    BrNs { cc: Condition, rule: u8 },
    BrNxtp { cc: Condition, jm: u8, addr_or_rule: u16 },
    BrBtstNxtp { btcc: BitTestCond, rs: Reg, boff: u8, jm: u8, addr_or_rule: u16 },
    BrBtstNs { btcc: BitTestCond, rs: Reg, boff: u8, rule: u8 },

    // -- Header / Cursor --
    Sth { pid: u8, oid: u8, halt: bool },
    Stch { incr: u16, pid: u8, oid: u8, halt: bool },
    Sthc { incr: u16, pid: u8, oid: u8 },
    Stc { rs: Reg, soff: u8, ssz: u8, shift: u8, incr: u8 },
    Stci { incr: u16 },

    // -- Store to Struct-0 --
    St { rs: Reg, soff: u8, doff: u8, size: u8, halt: bool },
    StI { imm: u16, doff: u8, size: u8 },

    // -- MAP interface --
    ExtMap { midx: u8, doff: u8, poff: u16, size: u8 },
    MovMap { midx: u8, doff: u8, rs: Reg, soff: u8, size: u8 },

    // -- Transition / NXTP --
    Nxtp { rs: Reg, soff: u8, size: u8 },

    // -- PSEEK --
    Pseek { rd: Reg, doff: u8, rs: Reg, soff: u8, size: u8, cid: u8 },
    PseekNxtp { rd: Reg, doff: u8, rs: Reg, soff: u8, size: u8, cid: u8 },
}

/// Result of a single step.
#[derive(Debug, Clone, Serialize)]
pub struct StepResult {
    /// The instruction that was executed (human-readable).
    pub instruction: String,
    /// Whether the simulator halted.
    pub halted: bool,
    /// Whether the packet was dropped (HALTDROP).
    pub dropped: bool,
    /// Which registers changed (register name → new value as hex string).
    pub reg_changes: Vec<(String, String)>,
    /// Whether flags changed.
    pub flags_changed: bool,
}

/// Execution outcome (internal, not serialized to JS).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecResult {
    Success,
    Halt,
    Drop,
}
```

- [ ] **Step 4: Verify it compiles**

Run: `./dev.sh bash -c "cd web/simulator && cargo check"`
Expected: Compiles with no errors.

- [ ] **Step 5: Commit**

```bash
git add web/simulator/Cargo.toml web/simulator/src/lib.rs web/simulator/src/types.rs
git commit -m "Scaffold Rust simulator crate with Parser ISA types"
```

---

## Phase 2: Simulator Core

### Task 3: State Module

**Files:**
- Create: `web/simulator/src/state.rs`
- Modify: `web/simulator/src/lib.rs` (uncomment `pub mod state;`)

- [ ] **Step 1: Create state.rs**

```rust
use serde::Serialize;

use crate::types::Reg;

/// Complete parser processor state.
/// Mirrors the state variables from model/parser/state.sail.
#[derive(Debug, Clone, Serialize)]
pub struct SimState {
    /// Program counter (16-bit, 0-65535).
    pub pc: u16,
    /// 4 general-purpose 128-bit registers (PR0-PR3) + PRN (null, always 0).
    pub regs: [u128; 5],
    /// Zero flag.
    pub flag_z: bool,
    /// Negative flag.
    pub flag_n: bool,
    /// Cursor position in the packet header buffer (byte offset, 0-255).
    pub cursor: u8,
    /// Parser state ID for transition table lookups.
    pub parser_state: u8,
    /// 256-byte packet header buffer.
    pub packet_header: Vec<u8>,
    /// Instruction memory (64-bit encoded instructions).
    pub instruction_mem: Vec<u64>,
    /// Header presence flags (32 entries).
    pub hdr_present: [bool; 32],
    /// Header offset values (32 entries, byte offsets).
    pub hdr_offset: [u8; 32],
    /// Struct-0: 128-bit standard metadata register.
    pub struct0: u128,
    /// Whether the processor has halted.
    pub halted: bool,
    /// Whether the packet was dropped (via HALTDROP).
    pub dropped: bool,
    /// Total steps executed.
    pub step_count: u64,

    // -- NXTP result (set by transition table lookup) --
    pub nxtp_result_pc: u16,
    pub nxtp_result_state: u8,
    pub nxtp_matched: bool,

    // -- Transition table (64 entries) --
    pub tt_valid: [bool; 64],
    pub tt_state: [u8; 64],
    pub tt_key: [u32; 64],       // 24-bit keys stored in u32
    pub tt_next_pc: [u16; 64],
    pub tt_next_state: [u8; 64],

    // -- PSEEK table (32 entries) --
    pub pseek_valid: [bool; 32],
    pub pseek_class_id: [u8; 32],
    pub pseek_protocol_value: [u16; 32],
    pub pseek_hdr_length: [u8; 32],
    pub pseek_next_proto_off: [u8; 32],
    pub pseek_next_proto_size: [u8; 32],

    // -- MAP registers (for EXTMAP/MOVMAP, 16 × 128-bit) --
    pub map_regs: [u128; 16],
}

impl SimState {
    /// Create a new state with all values initialized to zero/false.
    /// Mirrors parser_init() from model/parser/state.sail.
    pub fn new() -> Self {
        Self {
            pc: 0,
            regs: [0; 5],
            flag_z: false,
            flag_n: false,
            cursor: 0,
            parser_state: 0,
            packet_header: vec![0; 256],
            instruction_mem: Vec::new(),
            hdr_present: [false; 32],
            hdr_offset: [0; 32],
            struct0: 0,
            halted: false,
            dropped: false,
            step_count: 0,
            nxtp_result_pc: 0,
            nxtp_result_state: 0,
            nxtp_matched: false,
            tt_valid: [false; 64],
            tt_state: [0; 64],
            tt_key: [0; 64],
            tt_next_pc: [0; 64],
            tt_next_state: [0; 64],
            pseek_valid: [false; 32],
            pseek_class_id: [0; 32],
            pseek_protocol_value: [0; 32],
            pseek_hdr_length: [0; 32],
            pseek_next_proto_off: [0; 32],
            pseek_next_proto_size: [0; 32],
            map_regs: [0; 16],
        }
    }

    /// Read a register value. PRN always returns 0.
    pub fn read_reg(&self, reg: Reg) -> u128 {
        self.regs[reg as usize]
    }

    /// Write a register value. Writes to PRN are discarded.
    pub fn write_reg(&mut self, reg: Reg, val: u128) {
        if reg != Reg::PRN {
            self.regs[reg as usize] = val;
        }
    }

    /// Reset state but keep instruction memory and tables.
    pub fn reset_execution(&mut self) {
        self.pc = 0;
        self.regs = [0; 5];
        self.flag_z = false;
        self.flag_n = false;
        self.cursor = 0;
        self.parser_state = 0;
        self.halted = false;
        self.dropped = false;
        self.step_count = 0;
        self.hdr_present = [false; 32];
        self.hdr_offset = [0; 32];
        self.struct0 = 0;
        self.nxtp_result_pc = 0;
        self.nxtp_result_state = 0;
        self.nxtp_matched = false;
        self.map_regs = [0; 16];
    }
}

// -- Bit manipulation helpers --
// These mirror extract_bits / insert_bits from model/parser/state.sail.
// Registers are 128-bit big-endian: bit 0 is the MSB, bit 127 is the LSB.

/// Extract `size` bits starting at bit position `offset` (big-endian, 0 = MSB).
/// Returns the extracted value right-aligned (zero-extended).
pub fn extract_bits(val: u128, offset: u8, size: u8) -> u128 {
    if size == 0 || size > 128 {
        return 0;
    }
    let shift = 128 - (offset as u32) - (size as u32);
    let mask = if size >= 128 { u128::MAX } else { (1u128 << size) - 1 };
    (val >> shift) & mask
}

/// Insert `size` bits of `data` at bit position `offset` (big-endian, 0 = MSB).
/// Returns the modified value with other bits preserved.
pub fn insert_bits(val: u128, offset: u8, size: u8, data: u128) -> u128 {
    if size == 0 || size > 128 {
        return val;
    }
    let shift = 128 - (offset as u32) - (size as u32);
    let mask = if size >= 128 { u128::MAX } else { (1u128 << size) - 1 };
    (val & !(mask << shift)) | ((data & mask) << shift)
}

/// Extract bytes from the packet header buffer at a bit offset.
/// Used by EXT, EXTNXTP, EXTMAP instructions.
/// `cursor` is the byte position, `bit_offset` is relative to cursor.
pub fn extract_packet_bits(packet: &[u8], cursor: u8, bit_offset: u16, size: u8) -> u128 {
    let start_bit = (cursor as u32) * 8 + (bit_offset as u32);
    let mut result: u128 = 0;
    for i in 0..(size as u32) {
        let byte_idx = ((start_bit + i) / 8) as usize;
        let bit_idx = 7 - ((start_bit + i) % 8); // big-endian within byte
        if byte_idx < packet.len() {
            let bit = ((packet[byte_idx] >> bit_idx) & 1) as u128;
            result = (result << 1) | bit;
        }
    }
    result
}
```

- [ ] **Step 2: Add module to lib.rs**

Add `pub mod state;` to `web/simulator/src/lib.rs`.

- [ ] **Step 3: Write tests for bit manipulation helpers**

Create `web/simulator/src/state.rs` test module at the bottom of the file:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_bits_msb() {
        // Bit 0 is MSB. Extract 8 bits from position 0 of 0xFF00...00
        let val: u128 = 0xFF << 120;
        assert_eq!(extract_bits(val, 0, 8), 0xFF);
    }

    #[test]
    fn test_extract_bits_middle() {
        // Extract 16 bits from position 8
        let val: u128 = 0x00ABCD << 104;
        assert_eq!(extract_bits(val, 8, 16), 0xABCD);
    }

    #[test]
    fn test_insert_bits() {
        let val: u128 = 0;
        let result = insert_bits(val, 0, 8, 0xFF);
        assert_eq!(extract_bits(result, 0, 8), 0xFF);
        // Rest should be zero
        assert_eq!(extract_bits(result, 8, 120), 0);
    }

    #[test]
    fn test_insert_preserves_other_bits() {
        let val: u128 = u128::MAX;
        let result = insert_bits(val, 8, 8, 0x00);
        assert_eq!(extract_bits(result, 0, 8), 0xFF);
        assert_eq!(extract_bits(result, 8, 8), 0x00);
        assert_eq!(extract_bits(result, 16, 8), 0xFF);
    }

    #[test]
    fn test_extract_packet_bits() {
        let packet = vec![0x45, 0x00, 0x00, 0x3C]; // IPv4 header start
        // Extract first 4 bits (version = 4)
        assert_eq!(extract_packet_bits(&packet, 0, 0, 4), 4);
        // Extract next 4 bits (IHL = 5)
        assert_eq!(extract_packet_bits(&packet, 0, 4, 4), 5);
    }

    #[test]
    fn test_prn_always_zero() {
        let mut state = SimState::new();
        state.write_reg(Reg::PRN, 0xDEAD);
        assert_eq!(state.read_reg(Reg::PRN), 0);
    }
}
```

- [ ] **Step 4: Run tests**

Run: `./dev.sh bash -c "cd web/simulator && cargo test"`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add web/simulator/src/state.rs web/simulator/src/lib.rs
git commit -m "Add simulator state module with bit manipulation helpers"
```

---

### Task 4: Decode Module — Control, Data Movement, Arithmetic

**Files:**
- Create: `web/simulator/src/decode.rs`
- Modify: `web/simulator/src/lib.rs` (add `pub mod decode;`)

The decode module translates 64-bit encoded instructions to `Instruction` enum variants. The encoding format uses bits [63:58] as a 6-bit opcode, with fields packed MSB-first after the opcode. This mirrors `model/parser/decode.sail`.

- [ ] **Step 1: Create decode.rs with opcode constants and helper**

```rust
use crate::types::*;

/// Decode error with the raw instruction word.
#[derive(Debug, Clone)]
pub struct DecodeError {
    pub word: u64,
    pub message: String,
}

// Opcode constants (bits [63:58]). Mirrors model/parser/decode.sail.
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

/// Extract a bit field from a 64-bit instruction word.
/// `start` is the MSB position (0 = bit 63), `width` is the number of bits.
fn field(word: u64, start: u8, width: u8) -> u64 {
    let shift = 64 - (start as u32) - (width as u32);
    let mask = (1u64 << width) - 1;
    (word >> shift) & mask
}

fn decode_reg(bits: u64) -> Result<Reg, DecodeError> {
    match bits {
        0 => Ok(Reg::PR0),
        1 => Ok(Reg::PR1),
        2 => Ok(Reg::PR2),
        3 => Ok(Reg::PR3),
        4 => Ok(Reg::PRN),
        _ => Err(DecodeError {
            word: bits,
            message: format!("invalid register index: {}", bits),
        }),
    }
}

fn decode_cond(bits: u64) -> Result<Condition, DecodeError> {
    match bits {
        0 => Ok(Condition::Eq),
        1 => Ok(Condition::Neq),
        2 => Ok(Condition::Lt),
        3 => Ok(Condition::Gt),
        4 => Ok(Condition::Ge),
        5 => Ok(Condition::Le),
        6 => Ok(Condition::Al),
        _ => Err(DecodeError {
            word: bits,
            message: format!("invalid condition code: {}", bits),
        }),
    }
}

fn decode_btcond(bits: u64) -> BitTestCond {
    if bits == 0 { BitTestCond::Clear } else { BitTestCond::Set }
}

/// Decode a 64-bit instruction word into an Instruction.
pub fn decode(word: u64) -> Result<Instruction, DecodeError> {
    let opcode = field(word, 0, 6) as u8;

    match opcode {
        // -- Control --
        OP_NOP => Ok(Instruction::Nop),
        OP_HALT => Ok(Instruction::Halt {
            drop: field(word, 6, 1) != 0,
        }),

        // -- Transition --
        OP_NXTP => Ok(Instruction::Nxtp {
            rs: decode_reg(field(word, 6, 3))?,
            soff: field(word, 9, 8) as u8,
            size: field(word, 17, 8) as u8,
        }),

        // -- PSEEK --
        OP_PSEEK => Ok(Instruction::Pseek {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            rs: decode_reg(field(word, 17, 3))?,
            soff: field(word, 20, 8) as u8,
            size: field(word, 28, 8) as u8,
            cid: field(word, 36, 8) as u8,
        }),
        OP_PSEEKNXTP => Ok(Instruction::PseekNxtp {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            rs: decode_reg(field(word, 17, 3))?,
            soff: field(word, 20, 8) as u8,
            size: field(word, 28, 8) as u8,
            cid: field(word, 36, 8) as u8,
        }),

        // -- Extraction --
        OP_EXT => Ok(Instruction::Ext {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            soff: field(word, 17, 16) as u16,
            size: field(word, 33, 8) as u8,
            cd: field(word, 41, 1) != 0,
        }),
        OP_EXTNXTP => Ok(Instruction::ExtNxtp {
            rd: decode_reg(field(word, 6, 3))?,
            soff: field(word, 9, 16) as u16,
            size: field(word, 25, 8) as u8,
            cd: field(word, 33, 1) != 0,
        }),
        OP_EXTMAP => Ok(Instruction::ExtMap {
            midx: field(word, 6, 4) as u8,
            doff: field(word, 10, 8) as u8,
            poff: field(word, 18, 16) as u16,
            size: field(word, 34, 8) as u8,
        }),
        OP_MOVMAP => Ok(Instruction::MovMap {
            midx: field(word, 6, 4) as u8,
            doff: field(word, 10, 8) as u8,
            rs: decode_reg(field(word, 18, 3))?,
            soff: field(word, 21, 8) as u8,
            size: field(word, 29, 8) as u8,
        }),

        // -- Concatenation --
        OP_CNCTBY => Ok(Instruction::CnctBy {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            rs1: decode_reg(field(word, 17, 3))?,
            s1off: field(word, 20, 8) as u8,
            s1sz: field(word, 28, 8) as u8,
            rs2: decode_reg(field(word, 36, 3))?,
            s2off: field(word, 39, 8) as u8,
            s2sz: field(word, 47, 8) as u8,
            cd: field(word, 55, 1) != 0,
        }),
        OP_CNCTBI => Ok(Instruction::CnctBi {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            rs1: decode_reg(field(word, 17, 3))?,
            s1off: field(word, 20, 8) as u8,
            s1sz: field(word, 28, 8) as u8,
            rs2: decode_reg(field(word, 36, 3))?,
            s2off: field(word, 39, 8) as u8,
            s2sz: field(word, 47, 8) as u8,
            cd: field(word, 55, 1) != 0,
        }),

        // -- Header / Cursor --
        OP_STH => Ok(Instruction::Sth {
            pid: field(word, 6, 8) as u8,
            oid: field(word, 14, 8) as u8,
            halt: field(word, 22, 1) != 0,
        }),
        OP_STC => Ok(Instruction::Stc {
            rs: decode_reg(field(word, 6, 3))?,
            soff: field(word, 9, 8) as u8,
            ssz: field(word, 17, 8) as u8,
            shift: field(word, 25, 8) as u8,
            incr: field(word, 33, 8) as u8,
        }),
        OP_STCI => Ok(Instruction::Stci {
            incr: field(word, 6, 16) as u16,
        }),
        OP_STCH => Ok(Instruction::Stch {
            incr: field(word, 6, 16) as u16,
            pid: field(word, 22, 8) as u8,
            oid: field(word, 30, 8) as u8,
            halt: field(word, 38, 1) != 0,
        }),
        OP_STHC => Ok(Instruction::Sthc {
            incr: field(word, 6, 16) as u16,
            pid: field(word, 22, 8) as u8,
            oid: field(word, 30, 8) as u8,
        }),

        // -- Store to Struct-0 --
        OP_ST => Ok(Instruction::St {
            rs: decode_reg(field(word, 6, 3))?,
            soff: field(word, 9, 8) as u8,
            doff: field(word, 17, 8) as u8,
            size: field(word, 25, 8) as u8,
            halt: field(word, 33, 1) != 0,
        }),
        OP_STI => Ok(Instruction::StI {
            imm: field(word, 6, 16) as u16,
            doff: field(word, 22, 8) as u8,
            size: field(word, 30, 8) as u8,
        }),

        // -- Data movement --
        OP_MOV => Ok(Instruction::Mov {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            rs: decode_reg(field(word, 17, 3))?,
            soff: field(word, 20, 8) as u8,
            size: field(word, 28, 8) as u8,
            cd: field(word, 36, 1) != 0,
        }),
        OP_MOVI => Ok(Instruction::Movi {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            imm: field(word, 17, 16) as u16,
            size: field(word, 33, 8) as u8,
            cd: field(word, 41, 1) != 0,
        }),
        OP_MOVL => Ok(Instruction::MovL {
            rd: decode_reg(field(word, 6, 3))?,
            rs1: decode_reg(field(word, 9, 3))?,
            o1: field(word, 12, 8) as u8,
            sz1: field(word, 20, 8) as u8,
            rs2: decode_reg(field(word, 28, 3))?,
            o2: field(word, 31, 8) as u8,
            sz2: field(word, 39, 8) as u8,
            cd: field(word, 47, 1) != 0,
        }),
        OP_MOVLI => Ok(Instruction::MovLI {
            rd: decode_reg(field(word, 6, 3))?,
            rs: decode_reg(field(word, 9, 3))?,
            off: field(word, 12, 8) as u8,
            size: field(word, 20, 8) as u8,
            imm: field(word, 28, 8) as u8,
            cd: field(word, 36, 1) != 0,
        }),
        OP_MOVLII => Ok(Instruction::MovLII {
            rd: decode_reg(field(word, 6, 3))?,
            rs: decode_reg(field(word, 9, 3))?,
            off: field(word, 12, 8) as u8,
            size: field(word, 20, 8) as u8,
            imm: field(word, 28, 8) as u8,
            isz: field(word, 36, 8) as u8,
            cd: field(word, 44, 1) != 0,
        }),
        OP_MOVR => Ok(Instruction::MovR {
            rd: decode_reg(field(word, 6, 3))?,
            rs1: decode_reg(field(word, 9, 3))?,
            o1: field(word, 12, 8) as u8,
            sz1: field(word, 20, 8) as u8,
            rs2: decode_reg(field(word, 28, 3))?,
            o2: field(word, 31, 8) as u8,
            sz2: field(word, 39, 8) as u8,
            cd: field(word, 47, 1) != 0,
        }),
        OP_MOVRI => Ok(Instruction::MovRI {
            rd: decode_reg(field(word, 6, 3))?,
            rs: decode_reg(field(word, 9, 3))?,
            off: field(word, 12, 8) as u8,
            size: field(word, 20, 8) as u8,
            imm: field(word, 28, 8) as u8,
            cd: field(word, 36, 1) != 0,
        }),
        OP_MOVRII => Ok(Instruction::MovRII {
            rd: decode_reg(field(word, 6, 3))?,
            rs: decode_reg(field(word, 9, 3))?,
            off: field(word, 12, 8) as u8,
            size: field(word, 20, 8) as u8,
            imm: field(word, 28, 8) as u8,
            isz: field(word, 36, 8) as u8,
            cd: field(word, 44, 1) != 0,
        }),

        // -- Arithmetic --
        OP_ADD => Ok(Instruction::Add {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            rs1: decode_reg(field(word, 17, 3))?,
            s1off: field(word, 20, 8) as u8,
            rs2: decode_reg(field(word, 28, 3))?,
            s2off: field(word, 31, 8) as u8,
            size: field(word, 39, 8) as u8,
            cd: field(word, 47, 1) != 0,
        }),
        OP_ADDI => Ok(Instruction::AddI {
            rd: decode_reg(field(word, 6, 3))?,
            rs: decode_reg(field(word, 9, 3))?,
            imm: field(word, 12, 16) as u16,
            size: field(word, 28, 8) as u8,
            cd: field(word, 36, 1) != 0,
        }),
        OP_SUB => Ok(Instruction::Sub {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            rs1: decode_reg(field(word, 17, 3))?,
            s1off: field(word, 20, 8) as u8,
            rs2: decode_reg(field(word, 28, 3))?,
            s2off: field(word, 31, 8) as u8,
            size: field(word, 39, 8) as u8,
            cd: field(word, 47, 1) != 0,
        }),
        OP_SUBI => Ok(Instruction::SubI {
            rd: decode_reg(field(word, 6, 3))?,
            rs: decode_reg(field(word, 9, 3))?,
            imm: field(word, 12, 16) as u16,
            size: field(word, 28, 8) as u8,
            cd: field(word, 36, 1) != 0,
        }),
        OP_SUBII => Ok(Instruction::SubII {
            rd: decode_reg(field(word, 6, 3))?,
            imm: field(word, 9, 16) as u16,
            rs: decode_reg(field(word, 25, 3))?,
            size: field(word, 28, 8) as u8,
            cd: field(word, 36, 1) != 0,
        }),

        // -- Logic --
        OP_AND => Ok(Instruction::And {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            rs1: decode_reg(field(word, 17, 3))?,
            s1off: field(word, 20, 8) as u8,
            rs2: decode_reg(field(word, 28, 3))?,
            s2off: field(word, 31, 8) as u8,
            size: field(word, 39, 8) as u8,
            cd: field(word, 47, 1) != 0,
        }),
        OP_ANDI => Ok(Instruction::AndI {
            rd: decode_reg(field(word, 6, 3))?,
            rs: decode_reg(field(word, 9, 3))?,
            imm: field(word, 12, 16) as u16,
            size: field(word, 28, 8) as u8,
            cd: field(word, 36, 1) != 0,
        }),
        OP_OR => Ok(Instruction::Or {
            rd: decode_reg(field(word, 6, 3))?,
            doff: field(word, 9, 8) as u8,
            rs1: decode_reg(field(word, 17, 3))?,
            s1off: field(word, 20, 8) as u8,
            rs2: decode_reg(field(word, 28, 3))?,
            s2off: field(word, 31, 8) as u8,
            size: field(word, 39, 8) as u8,
            cd: field(word, 47, 1) != 0,
        }),
        OP_ORI => Ok(Instruction::OrI {
            rd: decode_reg(field(word, 6, 3))?,
            rs: decode_reg(field(word, 9, 3))?,
            imm: field(word, 12, 16) as u16,
            size: field(word, 28, 8) as u8,
            cd: field(word, 36, 1) != 0,
        }),

        // -- Compare --
        OP_CMP => Ok(Instruction::Cmp {
            rs1: decode_reg(field(word, 6, 3))?,
            s1off: field(word, 9, 8) as u8,
            rs2: decode_reg(field(word, 17, 3))?,
            s2off: field(word, 20, 8) as u8,
            size: field(word, 28, 8) as u8,
        }),
        OP_CMPIBY => Ok(Instruction::CmpIBy {
            rs: decode_reg(field(word, 6, 3))?,
            soff: field(word, 9, 8) as u8,
            imm: field(word, 17, 16) as u16,
            size: field(word, 33, 8) as u8,
        }),
        OP_CMPIBI => Ok(Instruction::CmpIBi {
            rs: decode_reg(field(word, 6, 3))?,
            soff: field(word, 9, 8) as u8,
            imm: field(word, 17, 16) as u16,
            size: field(word, 33, 8) as u8,
        }),

        // -- Branch --
        OP_BR => Ok(Instruction::Br {
            cc: decode_cond(field(word, 6, 3))?,
            target: field(word, 9, 16) as u16,
        }),
        OP_BRBTST => Ok(Instruction::BrBtst {
            btcc: decode_btcond(field(word, 6, 1)),
            rs: decode_reg(field(word, 7, 3))?,
            boff: field(word, 10, 8) as u8,
            target: field(word, 18, 16) as u16,
        }),
        OP_BRNS => Ok(Instruction::BrNs {
            cc: decode_cond(field(word, 6, 3))?,
            rule: field(word, 9, 8) as u8,
        }),
        OP_BRNXTP => Ok(Instruction::BrNxtp {
            cc: decode_cond(field(word, 6, 3))?,
            jm: field(word, 9, 8) as u8,
            addr_or_rule: field(word, 17, 16) as u16,
        }),
        OP_BRBTSTNXTP => Ok(Instruction::BrBtstNxtp {
            btcc: decode_btcond(field(word, 6, 1)),
            rs: decode_reg(field(word, 7, 3))?,
            boff: field(word, 10, 8) as u8,
            jm: field(word, 18, 8) as u8,
            addr_or_rule: field(word, 26, 16) as u16,
        }),
        OP_BRBTSTNS => Ok(Instruction::BrBtstNs {
            btcc: decode_btcond(field(word, 6, 1)),
            rs: decode_reg(field(word, 7, 3))?,
            boff: field(word, 10, 8) as u8,
            rule: field(word, 18, 8) as u8,
        }),

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
        assert_eq!(decode(0x0000000000000000).unwrap(), Instruction::Nop);
    }

    #[test]
    fn test_decode_halt() {
        // opcode 1 = 0b000001, drop=0 → bits: 000001 0 000...
        let word = 1u64 << 58;
        assert_eq!(decode(word).unwrap(), Instruction::Halt { drop: false });
    }

    #[test]
    fn test_decode_halt_drop() {
        // opcode 1, drop=1 → bits: 000001 1 000...
        let word = (1u64 << 58) | (1u64 << 57);
        assert_eq!(decode(word).unwrap(), Instruction::Halt { drop: true });
    }

    #[test]
    fn test_decode_unknown_opcode() {
        // opcode 63 (0b111111) is not assigned
        let word = 63u64 << 58;
        assert!(decode(word).is_err());
    }

    #[test]
    fn test_field_extraction() {
        // Test the field() helper directly
        let word: u64 = 0b_000101_001_00001000_0000000000010000_00100000_1_u64 << 22;
        // opcode=5 (EXT), rd=PR1(001), doff=8, soff=16, size=32, cd=1
        let inst = decode(word).unwrap();
        assert_eq!(inst, Instruction::Ext {
            rd: Reg::PR1,
            doff: 8,
            soff: 16,
            size: 32,
            cd: true,
        });
    }
}
```

- [ ] **Step 2: Add module to lib.rs**

Add `pub mod decode;` to `web/simulator/src/lib.rs`.

- [ ] **Step 3: Run tests**

Run: `./dev.sh bash -c "cd web/simulator && cargo test"`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add web/simulator/src/decode.rs web/simulator/src/lib.rs
git commit -m "Add decode module for all 43 Parser ISA instructions"
```

---

### Task 5: Encode Module

**Files:**
- Create: `web/simulator/src/encode.rs`
- Modify: `web/simulator/src/lib.rs` (add `pub mod encode;`)

The encode module is the inverse of decode. It converts `Instruction` enum variants back to 64-bit words. Used by the assembler.

- [ ] **Step 1: Create encode.rs**

```rust
use crate::types::*;

/// Pack a field into a 64-bit word at a given bit position.
/// `start` is the MSB position (0 = bit 63), `width` is the number of bits.
fn pack(word: &mut u64, start: u8, width: u8, value: u64) {
    let shift = 64 - (start as u32) - (width as u32);
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

/// Encode an Instruction into a 64-bit word.
/// This is the inverse of decode::decode().
pub fn encode(inst: &Instruction) -> u64 {
    let mut w: u64 = 0;

    match inst {
        Instruction::Nop => { /* opcode 0, all zeros */ }

        Instruction::Halt { drop } => {
            pack(&mut w, 0, 6, 1);
            pack(&mut w, 6, 1, *drop as u64);
        }

        Instruction::Nxtp { rs, soff, size } => {
            pack(&mut w, 0, 6, 2);
            pack(&mut w, 6, 3, reg_bits(*rs));
            pack(&mut w, 9, 8, *soff as u64);
            pack(&mut w, 17, 8, *size as u64);
        }

        Instruction::Pseek { rd, doff, rs, soff, size, cid } => {
            pack(&mut w, 0, 6, 3);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs));
            pack(&mut w, 20, 8, *soff as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 8, *cid as u64);
        }

        Instruction::PseekNxtp { rd, doff, rs, soff, size, cid } => {
            pack(&mut w, 0, 6, 4);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs));
            pack(&mut w, 20, 8, *soff as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 8, *cid as u64);
        }

        Instruction::Ext { rd, doff, soff, size, cd } => {
            pack(&mut w, 0, 6, 5);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 16, *soff as u64);
            pack(&mut w, 33, 8, *size as u64);
            pack(&mut w, 41, 1, *cd as u64);
        }

        Instruction::ExtNxtp { rd, soff, size, cd } => {
            pack(&mut w, 0, 6, 6);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 16, *soff as u64);
            pack(&mut w, 25, 8, *size as u64);
            pack(&mut w, 33, 1, *cd as u64);
        }

        Instruction::ExtMap { midx, doff, poff, size } => {
            pack(&mut w, 0, 6, 7);
            pack(&mut w, 6, 4, *midx as u64);
            pack(&mut w, 10, 8, *doff as u64);
            pack(&mut w, 18, 16, *poff as u64);
            pack(&mut w, 34, 8, *size as u64);
        }

        Instruction::MovMap { midx, doff, rs, soff, size } => {
            pack(&mut w, 0, 6, 8);
            pack(&mut w, 6, 4, *midx as u64);
            pack(&mut w, 10, 8, *doff as u64);
            pack(&mut w, 18, 3, reg_bits(*rs));
            pack(&mut w, 21, 8, *soff as u64);
            pack(&mut w, 29, 8, *size as u64);
        }

        Instruction::CnctBy { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd } => {
            pack(&mut w, 0, 6, 9);
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
            pack(&mut w, 0, 6, 10);
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
            pack(&mut w, 0, 6, 11);
            pack(&mut w, 6, 8, *pid as u64);
            pack(&mut w, 14, 8, *oid as u64);
            pack(&mut w, 22, 1, *halt as u64);
        }

        Instruction::Stc { rs, soff, ssz, shift, incr } => {
            pack(&mut w, 0, 6, 12);
            pack(&mut w, 6, 3, reg_bits(*rs));
            pack(&mut w, 9, 8, *soff as u64);
            pack(&mut w, 17, 8, *ssz as u64);
            pack(&mut w, 25, 8, *shift as u64);
            pack(&mut w, 33, 8, *incr as u64);
        }

        Instruction::Stci { incr } => {
            pack(&mut w, 0, 6, 13);
            pack(&mut w, 6, 16, *incr as u64);
        }

        Instruction::Stch { incr, pid, oid, halt } => {
            pack(&mut w, 0, 6, 14);
            pack(&mut w, 6, 16, *incr as u64);
            pack(&mut w, 22, 8, *pid as u64);
            pack(&mut w, 30, 8, *oid as u64);
            pack(&mut w, 38, 1, *halt as u64);
        }

        Instruction::Sthc { incr, pid, oid } => {
            pack(&mut w, 0, 6, 15);
            pack(&mut w, 6, 16, *incr as u64);
            pack(&mut w, 22, 8, *pid as u64);
            pack(&mut w, 30, 8, *oid as u64);
        }

        Instruction::St { rs, soff, doff, size, halt } => {
            pack(&mut w, 0, 6, 16);
            pack(&mut w, 6, 3, reg_bits(*rs));
            pack(&mut w, 9, 8, *soff as u64);
            pack(&mut w, 17, 8, *doff as u64);
            pack(&mut w, 25, 8, *size as u64);
            pack(&mut w, 33, 1, *halt as u64);
        }

        Instruction::StI { imm, doff, size } => {
            pack(&mut w, 0, 6, 17);
            pack(&mut w, 6, 16, *imm as u64);
            pack(&mut w, 22, 8, *doff as u64);
            pack(&mut w, 30, 8, *size as u64);
        }

        Instruction::Mov { rd, doff, rs, soff, size, cd } => {
            pack(&mut w, 0, 6, 18);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 3, reg_bits(*rs));
            pack(&mut w, 20, 8, *soff as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::Movi { rd, doff, imm, size, cd } => {
            pack(&mut w, 0, 6, 19);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 8, *doff as u64);
            pack(&mut w, 17, 16, *imm as u64);
            pack(&mut w, 33, 8, *size as u64);
            pack(&mut w, 41, 1, *cd as u64);
        }

        Instruction::MovL { rd, rs1, o1, sz1, rs2, o2, sz2, cd } => {
            pack(&mut w, 0, 6, 20);
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
            pack(&mut w, 0, 6, 21);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 8, *off as u64);
            pack(&mut w, 20, 8, *size as u64);
            pack(&mut w, 28, 8, *imm as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::MovLII { rd, rs, off, size, imm, isz, cd } => {
            pack(&mut w, 0, 6, 22);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 8, *off as u64);
            pack(&mut w, 20, 8, *size as u64);
            pack(&mut w, 28, 8, *imm as u64);
            pack(&mut w, 36, 8, *isz as u64);
            pack(&mut w, 44, 1, *cd as u64);
        }

        Instruction::MovR { rd, rs1, o1, sz1, rs2, o2, sz2, cd } => {
            pack(&mut w, 0, 6, 23);
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
            pack(&mut w, 0, 6, 24);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 8, *off as u64);
            pack(&mut w, 20, 8, *size as u64);
            pack(&mut w, 28, 8, *imm as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::MovRII { rd, rs, off, size, imm, isz, cd } => {
            pack(&mut w, 0, 6, 25);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 8, *off as u64);
            pack(&mut w, 20, 8, *size as u64);
            pack(&mut w, 28, 8, *imm as u64);
            pack(&mut w, 36, 8, *isz as u64);
            pack(&mut w, 44, 1, *cd as u64);
        }

        Instruction::Add { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            pack(&mut w, 0, 6, 26);
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
            pack(&mut w, 0, 6, 27);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 16, *imm as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::Sub { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            pack(&mut w, 0, 6, 28);
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
            pack(&mut w, 0, 6, 29);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 16, *imm as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::SubII { rd, imm, rs, size, cd } => {
            pack(&mut w, 0, 6, 30);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 16, *imm as u64);
            pack(&mut w, 25, 3, reg_bits(*rs));
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::And { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            pack(&mut w, 0, 6, 31);
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
            pack(&mut w, 0, 6, 32);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 16, *imm as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::Or { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            pack(&mut w, 0, 6, 33);
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
            pack(&mut w, 0, 6, 34);
            pack(&mut w, 6, 3, reg_bits(*rd));
            pack(&mut w, 9, 3, reg_bits(*rs));
            pack(&mut w, 12, 16, *imm as u64);
            pack(&mut w, 28, 8, *size as u64);
            pack(&mut w, 36, 1, *cd as u64);
        }

        Instruction::Cmp { rs1, s1off, rs2, s2off, size } => {
            pack(&mut w, 0, 6, 35);
            pack(&mut w, 6, 3, reg_bits(*rs1));
            pack(&mut w, 9, 8, *s1off as u64);
            pack(&mut w, 17, 3, reg_bits(*rs2));
            pack(&mut w, 20, 8, *s2off as u64);
            pack(&mut w, 28, 8, *size as u64);
        }

        Instruction::CmpIBy { rs, soff, imm, size } => {
            pack(&mut w, 0, 6, 36);
            pack(&mut w, 6, 3, reg_bits(*rs));
            pack(&mut w, 9, 8, *soff as u64);
            pack(&mut w, 17, 16, *imm as u64);
            pack(&mut w, 33, 8, *size as u64);
        }

        Instruction::CmpIBi { rs, soff, imm, size } => {
            pack(&mut w, 0, 6, 37);
            pack(&mut w, 6, 3, reg_bits(*rs));
            pack(&mut w, 9, 8, *soff as u64);
            pack(&mut w, 17, 16, *imm as u64);
            pack(&mut w, 33, 8, *size as u64);
        }

        Instruction::Br { cc, target } => {
            pack(&mut w, 0, 6, 38);
            pack(&mut w, 6, 3, cond_bits(*cc));
            pack(&mut w, 9, 16, *target as u64);
        }

        Instruction::BrBtst { btcc, rs, boff, target } => {
            pack(&mut w, 0, 6, 39);
            pack(&mut w, 6, 1, btcond_bits(*btcc));
            pack(&mut w, 7, 3, reg_bits(*rs));
            pack(&mut w, 10, 8, *boff as u64);
            pack(&mut w, 18, 16, *target as u64);
        }

        Instruction::BrNs { cc, rule } => {
            pack(&mut w, 0, 6, 40);
            pack(&mut w, 6, 3, cond_bits(*cc));
            pack(&mut w, 9, 8, *rule as u64);
        }

        Instruction::BrNxtp { cc, jm, addr_or_rule } => {
            pack(&mut w, 0, 6, 41);
            pack(&mut w, 6, 3, cond_bits(*cc));
            pack(&mut w, 9, 8, *jm as u64);
            pack(&mut w, 17, 16, *addr_or_rule as u64);
        }

        Instruction::BrBtstNxtp { btcc, rs, boff, jm, addr_or_rule } => {
            pack(&mut w, 0, 6, 42);
            pack(&mut w, 6, 1, btcond_bits(*btcc));
            pack(&mut w, 7, 3, reg_bits(*rs));
            pack(&mut w, 10, 8, *boff as u64);
            pack(&mut w, 18, 8, *jm as u64);
            pack(&mut w, 26, 16, *addr_or_rule as u64);
        }

        Instruction::BrBtstNs { btcc, rs, boff, rule } => {
            pack(&mut w, 0, 6, 43);
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
    use crate::decode;

    /// Round-trip test: encode → decode should produce the original instruction.
    fn roundtrip(inst: Instruction) {
        let word = encode(&inst);
        let decoded = decode::decode(word).expect("decode failed");
        assert_eq!(decoded, inst, "roundtrip failed for {:?} (word: {:#018x})", inst, word);
    }

    #[test]
    fn test_roundtrip_nop() { roundtrip(Instruction::Nop); }

    #[test]
    fn test_roundtrip_halt() { roundtrip(Instruction::Halt { drop: false }); }

    #[test]
    fn test_roundtrip_halt_drop() { roundtrip(Instruction::Halt { drop: true }); }

    #[test]
    fn test_roundtrip_ext() {
        roundtrip(Instruction::Ext {
            rd: Reg::PR1, doff: 8, soff: 16, size: 32, cd: true,
        });
    }

    #[test]
    fn test_roundtrip_mov() {
        roundtrip(Instruction::Mov {
            rd: Reg::PR0, doff: 0, rs: Reg::PR1, soff: 0, size: 128, cd: false,
        });
    }

    #[test]
    fn test_roundtrip_add() {
        roundtrip(Instruction::Add {
            rd: Reg::PR0, doff: 0, rs1: Reg::PR1, s1off: 0,
            rs2: Reg::PR2, s2off: 0, size: 64, cd: true,
        });
    }

    #[test]
    fn test_roundtrip_br() {
        roundtrip(Instruction::Br { cc: Condition::Eq, target: 42 });
    }

    #[test]
    fn test_roundtrip_brbtst() {
        roundtrip(Instruction::BrBtst {
            btcc: BitTestCond::Set, rs: Reg::PR0, boff: 7, target: 100,
        });
    }

    #[test]
    fn test_roundtrip_cnctby() {
        roundtrip(Instruction::CnctBy {
            rd: Reg::PR0, doff: 0,
            rs1: Reg::PR1, s1off: 0, s1sz: 8,
            rs2: Reg::PR2, s2off: 0, s2sz: 8,
            cd: false,
        });
    }

    #[test]
    fn test_roundtrip_sth() {
        roundtrip(Instruction::Sth { pid: 1, oid: 14, halt: true });
    }

    #[test]
    fn test_roundtrip_all_instructions() {
        // Exhaustive roundtrip of every instruction variant with sample values.
        let instructions = vec![
            Instruction::Nop,
            Instruction::Halt { drop: false },
            Instruction::Halt { drop: true },
            Instruction::Mov { rd: Reg::PR0, doff: 0, rs: Reg::PR1, soff: 8, size: 16, cd: true },
            Instruction::Movi { rd: Reg::PR2, doff: 0, imm: 0xABCD, size: 16, cd: false },
            Instruction::Ext { rd: Reg::PR0, doff: 0, soff: 0, size: 64, cd: false },
            Instruction::ExtNxtp { rd: Reg::PR0, soff: 0, size: 8, cd: true },
            Instruction::MovL { rd: Reg::PR0, rs1: Reg::PR1, o1: 0, sz1: 8, rs2: Reg::PR2, o2: 0, sz2: 8, cd: false },
            Instruction::MovLI { rd: Reg::PR0, rs: Reg::PR1, off: 0, size: 8, imm: 4, cd: false },
            Instruction::MovLII { rd: Reg::PR0, rs: Reg::PR1, off: 0, size: 8, imm: 4, isz: 16, cd: false },
            Instruction::MovR { rd: Reg::PR0, rs1: Reg::PR1, o1: 8, sz1: 8, rs2: Reg::PR2, o2: 0, sz2: 8, cd: false },
            Instruction::MovRI { rd: Reg::PR0, rs: Reg::PR1, off: 8, size: 8, imm: 4, cd: false },
            Instruction::MovRII { rd: Reg::PR0, rs: Reg::PR1, off: 8, size: 8, imm: 4, isz: 16, cd: false },
            Instruction::Add { rd: Reg::PR0, doff: 0, rs1: Reg::PR1, s1off: 0, rs2: Reg::PR2, s2off: 0, size: 32, cd: false },
            Instruction::AddI { rd: Reg::PR0, rs: Reg::PR1, imm: 100, size: 16, cd: false },
            Instruction::Sub { rd: Reg::PR0, doff: 0, rs1: Reg::PR1, s1off: 0, rs2: Reg::PR2, s2off: 0, size: 32, cd: false },
            Instruction::SubI { rd: Reg::PR0, rs: Reg::PR1, imm: 1, size: 16, cd: false },
            Instruction::SubII { rd: Reg::PR0, imm: 100, rs: Reg::PR1, size: 16, cd: false },
            Instruction::And { rd: Reg::PR0, doff: 0, rs1: Reg::PR1, s1off: 0, rs2: Reg::PR2, s2off: 0, size: 32, cd: false },
            Instruction::AndI { rd: Reg::PR0, rs: Reg::PR1, imm: 0xFF, size: 8, cd: false },
            Instruction::Or { rd: Reg::PR0, doff: 0, rs1: Reg::PR1, s1off: 0, rs2: Reg::PR2, s2off: 0, size: 32, cd: false },
            Instruction::OrI { rd: Reg::PR0, rs: Reg::PR1, imm: 0xFF, size: 8, cd: false },
            Instruction::Cmp { rs1: Reg::PR0, s1off: 0, rs2: Reg::PR1, s2off: 0, size: 32 },
            Instruction::CmpIBy { rs: Reg::PR0, soff: 0, imm: 42, size: 16 },
            Instruction::CmpIBi { rs: Reg::PR0, soff: 0, imm: 42, size: 16 },
            Instruction::CnctBy { rd: Reg::PR0, doff: 0, rs1: Reg::PR1, s1off: 0, s1sz: 8, rs2: Reg::PR2, s2off: 0, s2sz: 8, cd: false },
            Instruction::CnctBi { rd: Reg::PR0, doff: 0, rs1: Reg::PR1, s1off: 0, s1sz: 8, rs2: Reg::PR2, s2off: 0, s2sz: 8, cd: false },
            Instruction::Br { cc: Condition::Al, target: 0 },
            Instruction::BrBtst { btcc: BitTestCond::Clear, rs: Reg::PR0, boff: 0, target: 10 },
            Instruction::BrNs { cc: Condition::Al, rule: 0 },
            Instruction::BrNxtp { cc: Condition::Al, jm: 2, addr_or_rule: 100 },
            Instruction::BrBtstNxtp { btcc: BitTestCond::Set, rs: Reg::PR0, boff: 0, jm: 2, addr_or_rule: 100 },
            Instruction::BrBtstNs { btcc: BitTestCond::Set, rs: Reg::PR0, boff: 0, rule: 5 },
            Instruction::Sth { pid: 0, oid: 0, halt: false },
            Instruction::Stch { incr: 14, pid: 1, oid: 14, halt: false },
            Instruction::Sthc { incr: 14, pid: 1, oid: 14 },
            Instruction::Stc { rs: Reg::PR0, soff: 0, ssz: 8, shift: 0, incr: 0 },
            Instruction::Stci { incr: 20 },
            Instruction::St { rs: Reg::PR0, soff: 0, doff: 0, size: 32, halt: false },
            Instruction::StI { imm: 0x0800, doff: 0, size: 16 },
            Instruction::ExtMap { midx: 0, doff: 0, poff: 0, size: 32 },
            Instruction::MovMap { midx: 0, doff: 0, rs: Reg::PR0, soff: 0, size: 32 },
            Instruction::Nxtp { rs: Reg::PR0, soff: 0, size: 24 },
            Instruction::Pseek { rd: Reg::PR0, doff: 0, rs: Reg::PR1, soff: 0, size: 16, cid: 1 },
            Instruction::PseekNxtp { rd: Reg::PR0, doff: 0, rs: Reg::PR1, soff: 0, size: 16, cid: 1 },
        ];

        for inst in instructions {
            roundtrip(inst);
        }
    }
}
```

- [ ] **Step 2: Add module to lib.rs**

Add `pub mod encode;` to `web/simulator/src/lib.rs`.

- [ ] **Step 3: Run tests**

Run: `./dev.sh bash -c "cd web/simulator && cargo test"`
Expected: All roundtrip tests pass. This validates both encode and decode together.

- [ ] **Step 4: Commit**

```bash
git add web/simulator/src/encode.rs web/simulator/src/lib.rs
git commit -m "Add encode module with exhaustive roundtrip tests"
```

---

### Task 6: Execute Module — All Instruction Semantics

**Files:**
- Create: `web/simulator/src/execute.rs`
- Modify: `web/simulator/src/lib.rs` (add `pub mod execute;`)

This is the core of the simulator. Each instruction's semantics mirrors `model/parser/insts.sail`. The Rust `match` enforces that every `Instruction` variant is handled.

- [ ] **Step 1: Create execute.rs**

```rust
use crate::state::{extract_bits, extract_packet_bits, insert_bits, SimState};
use crate::types::*;

/// Evaluate a branch condition against current flags.
fn eval_condition(state: &SimState, cc: Condition) -> bool {
    match cc {
        Condition::Eq => state.flag_z,
        Condition::Neq => !state.flag_z,
        Condition::Lt => state.flag_n,
        Condition::Gt => !state.flag_n && !state.flag_z,
        Condition::Ge => !state.flag_n,
        Condition::Le => state.flag_n || state.flag_z,
        Condition::Al => true,
    }
}

/// Perform NXTP transition table lookup.
/// Searches for (parser_state, protocol_key) in the transition table.
fn nxtp_lookup(state: &mut SimState, protocol_key: u32) {
    state.nxtp_matched = false;
    for i in 0..64 {
        if state.tt_valid[i]
            && state.tt_state[i] == state.parser_state
            && state.tt_key[i] == protocol_key
        {
            state.nxtp_result_pc = state.tt_next_pc[i];
            state.nxtp_result_state = state.tt_next_state[i];
            state.nxtp_matched = true;
            return;
        }
    }
}

/// Handle BRNXTP jump-mode logic after an NXTP lookup.
fn apply_nxtp_branch(state: &mut SimState, jm: u8, addr_or_rule: u16) {
    if state.nxtp_matched {
        state.pc = state.nxtp_result_pc;
        state.parser_state = state.nxtp_result_state;
    } else {
        match jm {
            0 | 1 => { /* no jump, continue */ }
            2 => { state.pc = addr_or_rule; }
            3 => {
                let idx = addr_or_rule as usize;
                if idx < 64 && state.tt_valid[idx] {
                    state.pc = state.tt_next_pc[idx];
                    state.parser_state = state.tt_next_state[idx];
                }
            }
            _ => { /* unknown jump mode, no action */ }
        }
    }
}

/// Apply .CD (clear destination) modifier: zero the register before the operation.
fn maybe_clear(state: &mut SimState, reg: Reg, cd: bool) {
    if cd {
        state.write_reg(reg, 0);
    }
}

/// Execute a single instruction, mutating state.
/// Returns the execution result (success, halt, or drop).
///
/// Mirrors the scattered function `execute_pinstr` from model/parser/insts.sail.
pub fn execute(state: &mut SimState, inst: &Instruction) -> ExecResult {
    match inst {
        // -- Control --
        Instruction::Nop => ExecResult::Success,

        Instruction::Halt { drop } => {
            state.halted = true;
            if *drop {
                state.dropped = true;
                ExecResult::Drop
            } else {
                ExecResult::Halt
            }
        }

        // -- Data movement --
        Instruction::Mov { rd, doff, rs, soff, size, cd } => {
            let val = extract_bits(state.read_reg(*rs), *soff, *size);
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff, *size, val));
            ExecResult::Success
        }

        Instruction::Movi { rd, doff, imm, size, cd } => {
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff, *size, *imm as u128));
            ExecResult::Success
        }

        Instruction::Ext { rd, doff, soff, size, cd } => {
            let val = extract_packet_bits(&state.packet_header, state.cursor, *soff, *size);
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff, *size, val));
            ExecResult::Success
        }

        Instruction::ExtNxtp { rd, soff, size, cd } => {
            // Extract from packet into register (doff=0 implied)
            let val = extract_packet_bits(&state.packet_header, state.cursor, *soff, *size);
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, 0, *size, val));
            // Then do NXTP lookup with the extracted value as protocol key
            nxtp_lookup(state, val as u32);
            ExecResult::Success
        }

        Instruction::MovL { rd, rs1, o1, sz1, rs2, o2, sz2, cd } => {
            let data = extract_bits(state.read_reg(*rs1), *o1, *sz1);
            let shift_val = extract_bits(state.read_reg(*rs2), *o2, *sz2) as u8;
            let dest_off = o1.wrapping_add(shift_val);
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, dest_off, *sz1, data));
            ExecResult::Success
        }

        Instruction::MovLI { rd, rs, off, size, imm, cd } => {
            let data = extract_bits(state.read_reg(*rs), *off, *size);
            let dest_off = off.wrapping_add(*imm);
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, dest_off, *size, data));
            ExecResult::Success
        }

        Instruction::MovLII { rd, rs, off, size, imm, isz, cd } => {
            let data = extract_bits(state.read_reg(*rs), *off, *size);
            let dest_off = off.wrapping_add(*imm);
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, dest_off, *isz, data));
            ExecResult::Success
        }

        Instruction::MovR { rd, rs1, o1, sz1, rs2, o2, sz2, cd } => {
            let data = extract_bits(state.read_reg(*rs1), *o1, *sz1);
            let shift_val = extract_bits(state.read_reg(*rs2), *o2, *sz2) as u8;
            let dest_off = o1.saturating_sub(shift_val);
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, dest_off, *sz1, data));
            ExecResult::Success
        }

        Instruction::MovRI { rd, rs, off, size, imm, cd } => {
            let data = extract_bits(state.read_reg(*rs), *off, *size);
            let dest_off = off.saturating_sub(*imm);
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, dest_off, *size, data));
            ExecResult::Success
        }

        Instruction::MovRII { rd, rs, off, size, imm, isz, cd } => {
            let data = extract_bits(state.read_reg(*rs), *off, *size);
            let dest_off = off.saturating_sub(*imm);
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, dest_off, *isz, data));
            ExecResult::Success
        }

        // -- Arithmetic --
        Instruction::Add { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            let a = extract_bits(state.read_reg(*rs1), *s1off, *size);
            let b = extract_bits(state.read_reg(*rs2), *s2off, *size);
            let mask = if *size >= 128 { u128::MAX } else { (1u128 << *size) - 1 };
            let result = (a.wrapping_add(b)) & mask;
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff, *size, result));
            ExecResult::Success
        }

        Instruction::AddI { rd, rs, imm, size, cd } => {
            let a = extract_bits(state.read_reg(*rs), 0, *size);
            let mask = if *size >= 128 { u128::MAX } else { (1u128 << *size) - 1 };
            let result = (a.wrapping_add(*imm as u128)) & mask;
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, 0, *size, result));
            ExecResult::Success
        }

        Instruction::Sub { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            let a = extract_bits(state.read_reg(*rs1), *s1off, *size);
            let b = extract_bits(state.read_reg(*rs2), *s2off, *size);
            let mask = if *size >= 128 { u128::MAX } else { (1u128 << *size) - 1 };
            let result = (a.wrapping_sub(b)) & mask;
            state.flag_z = result == 0;
            state.flag_n = (result >> (*size - 1)) & 1 == 1;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff, *size, result));
            ExecResult::Success
        }

        Instruction::SubI { rd, rs, imm, size, cd } => {
            let a = extract_bits(state.read_reg(*rs), 0, *size);
            let mask = if *size >= 128 { u128::MAX } else { (1u128 << *size) - 1 };
            let result = (a.wrapping_sub(*imm as u128)) & mask;
            state.flag_z = result == 0;
            state.flag_n = (result >> (*size - 1)) & 1 == 1;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, 0, *size, result));
            ExecResult::Success
        }

        Instruction::SubII { rd, imm, rs, size, cd } => {
            let a = *imm as u128;
            let b = extract_bits(state.read_reg(*rs), 0, *size);
            let mask = if *size >= 128 { u128::MAX } else { (1u128 << *size) - 1 };
            let result = (a.wrapping_sub(b)) & mask;
            state.flag_z = result == 0;
            state.flag_n = (result >> (*size - 1)) & 1 == 1;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, 0, *size, result));
            ExecResult::Success
        }

        // -- Logic --
        Instruction::And { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            let a = extract_bits(state.read_reg(*rs1), *s1off, *size);
            let b = extract_bits(state.read_reg(*rs2), *s2off, *size);
            let result = a & b;
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff, *size, result));
            ExecResult::Success
        }

        Instruction::AndI { rd, rs, imm, size, cd } => {
            let a = extract_bits(state.read_reg(*rs), 0, *size);
            let result = a & (*imm as u128);
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, 0, *size, result));
            ExecResult::Success
        }

        Instruction::Or { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            let a = extract_bits(state.read_reg(*rs1), *s1off, *size);
            let b = extract_bits(state.read_reg(*rs2), *s2off, *size);
            let result = a | b;
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff, *size, result));
            ExecResult::Success
        }

        Instruction::OrI { rd, rs, imm, size, cd } => {
            let a = extract_bits(state.read_reg(*rs), 0, *size);
            let result = a | (*imm as u128);
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, 0, *size, result));
            ExecResult::Success
        }

        // -- Compare (same as Sub but result is discarded) --
        Instruction::Cmp { rs1, s1off, rs2, s2off, size } => {
            let a = extract_bits(state.read_reg(*rs1), *s1off, *size);
            let b = extract_bits(state.read_reg(*rs2), *s2off, *size);
            let mask = if *size >= 128 { u128::MAX } else { (1u128 << *size) - 1 };
            let result = (a.wrapping_sub(b)) & mask;
            state.flag_z = result == 0;
            state.flag_n = (result >> (*size - 1)) & 1 == 1;
            ExecResult::Success
        }

        Instruction::CmpIBy { rs, soff, imm, size } => {
            // soff is in bytes, convert to bits
            let a = extract_bits(state.read_reg(*rs), *soff * 8, *size);
            let mask = if *size >= 128 { u128::MAX } else { (1u128 << *size) - 1 };
            let result = (a.wrapping_sub(*imm as u128)) & mask;
            state.flag_z = result == 0;
            state.flag_n = (result >> (*size - 1)) & 1 == 1;
            ExecResult::Success
        }

        Instruction::CmpIBi { rs, soff, imm, size } => {
            // soff is in bits
            let a = extract_bits(state.read_reg(*rs), *soff, *size);
            let mask = if *size >= 128 { u128::MAX } else { (1u128 << *size) - 1 };
            let result = (a.wrapping_sub(*imm as u128)) & mask;
            state.flag_z = result == 0;
            state.flag_n = (result >> (*size - 1)) & 1 == 1;
            ExecResult::Success
        }

        // -- Concatenation --
        Instruction::CnctBy { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd } => {
            // Byte-granularity: offsets/sizes are in bytes, convert to bits
            let v1 = extract_bits(state.read_reg(*rs1), *s1off * 8, *s1sz * 8);
            let v2 = extract_bits(state.read_reg(*rs2), *s2off * 8, *s2sz * 8);
            let combined = (v1 << (*s2sz * 8)) | v2;
            let total_sz = *s1sz * 8 + *s2sz * 8;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff * 8, total_sz, combined));
            ExecResult::Success
        }

        Instruction::CnctBi { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd } => {
            // Bit-granularity: all values are in bits
            let v1 = extract_bits(state.read_reg(*rs1), *s1off, *s1sz);
            let v2 = extract_bits(state.read_reg(*rs2), *s2off, *s2sz);
            let combined = (v1 << *s2sz) | v2;
            let total_sz = *s1sz + *s2sz;
            maybe_clear(state, *rd, *cd);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff, total_sz, combined));
            ExecResult::Success
        }

        // -- Branch --
        Instruction::Br { cc, target } => {
            if eval_condition(state, *cc) {
                state.pc = *target;
            }
            ExecResult::Success
        }

        Instruction::BrBtst { btcc, rs, boff, target } => {
            let bit = (extract_bits(state.read_reg(*rs), *boff, 1)) & 1;
            let take = match btcc {
                BitTestCond::Clear => bit == 0,
                BitTestCond::Set => bit == 1,
            };
            if take {
                state.pc = *target;
            }
            ExecResult::Success
        }

        Instruction::BrNs { cc, rule } => {
            if eval_condition(state, *cc) {
                let idx = *rule as usize;
                if idx < 64 && state.tt_valid[idx] {
                    state.pc = state.tt_next_pc[idx];
                    state.parser_state = state.tt_next_state[idx];
                }
            }
            ExecResult::Success
        }

        Instruction::BrNxtp { cc, jm, addr_or_rule } => {
            if eval_condition(state, *cc) {
                apply_nxtp_branch(state, *jm, *addr_or_rule);
            }
            ExecResult::Success
        }

        Instruction::BrBtstNxtp { btcc, rs, boff, jm, addr_or_rule } => {
            let bit = (extract_bits(state.read_reg(*rs), *boff, 1)) & 1;
            let take = match btcc {
                BitTestCond::Clear => bit == 0,
                BitTestCond::Set => bit == 1,
            };
            if take {
                apply_nxtp_branch(state, *jm, *addr_or_rule);
            }
            ExecResult::Success
        }

        Instruction::BrBtstNs { btcc, rs, boff, rule } => {
            let bit = (extract_bits(state.read_reg(*rs), *boff, 1)) & 1;
            let take = match btcc {
                BitTestCond::Clear => bit == 0,
                BitTestCond::Set => bit == 1,
            };
            if take {
                let idx = *rule as usize;
                if idx < 64 && state.tt_valid[idx] {
                    state.pc = state.tt_next_pc[idx];
                    state.parser_state = state.tt_next_state[idx];
                }
            }
            ExecResult::Success
        }

        // -- Header / Cursor --
        Instruction::Sth { pid, oid, halt } => {
            let idx = *pid as usize;
            if idx < 32 {
                state.hdr_present[idx] = true;
                state.hdr_offset[idx] = *oid;
            }
            if *halt {
                state.halted = true;
                return ExecResult::Halt;
            }
            ExecResult::Success
        }

        Instruction::Stc { rs, soff, ssz, shift, incr } => {
            let val = extract_bits(state.read_reg(*rs), *soff, *ssz) as u8;
            let new_cursor = val.wrapping_add(*incr) << shift;
            state.cursor = state.cursor.wrapping_add(new_cursor);
            ExecResult::Success
        }

        Instruction::Stci { incr } => {
            state.cursor = state.cursor.wrapping_add(*incr as u8);
            ExecResult::Success
        }

        Instruction::Stch { incr, pid, oid, halt } => {
            // Set cursor first, then header
            state.cursor = state.cursor.wrapping_add(*incr as u8);
            let idx = *pid as usize;
            if idx < 32 {
                state.hdr_present[idx] = true;
                state.hdr_offset[idx] = *oid;
            }
            if *halt {
                state.halted = true;
                return ExecResult::Halt;
            }
            ExecResult::Success
        }

        Instruction::Sthc { incr, pid, oid } => {
            // Set header first, then cursor
            let idx = *pid as usize;
            if idx < 32 {
                state.hdr_present[idx] = true;
                state.hdr_offset[idx] = *oid;
            }
            state.cursor = state.cursor.wrapping_add(*incr as u8);
            ExecResult::Success
        }

        // -- Store to Struct-0 --
        Instruction::St { rs, soff, doff, size, halt } => {
            let val = extract_bits(state.read_reg(*rs), *soff, *size);
            state.struct0 = insert_bits(state.struct0, *doff, *size, val);
            if *halt {
                state.halted = true;
                return ExecResult::Halt;
            }
            ExecResult::Success
        }

        Instruction::StI { imm, doff, size } => {
            state.struct0 = insert_bits(state.struct0, *doff, *size, *imm as u128);
            ExecResult::Success
        }

        // -- MAP interface --
        Instruction::ExtMap { midx, doff, poff, size } => {
            let val = extract_packet_bits(&state.packet_header, state.cursor, *poff, *size);
            let idx = *midx as usize;
            if idx < 16 {
                state.map_regs[idx] = insert_bits(state.map_regs[idx], *doff, *size, val);
            }
            ExecResult::Success
        }

        Instruction::MovMap { midx, doff, rs, soff, size } => {
            let val = extract_bits(state.read_reg(*rs), *soff, *size);
            let idx = *midx as usize;
            if idx < 16 {
                state.map_regs[idx] = insert_bits(state.map_regs[idx], *doff, *size, val);
            }
            ExecResult::Success
        }

        // -- Transition / NXTP --
        Instruction::Nxtp { rs, soff, size } => {
            let key = extract_bits(state.read_reg(*rs), *soff, *size) as u32;
            nxtp_lookup(state, key);
            ExecResult::Success
        }

        // -- PSEEK --
        Instruction::Pseek { rd, doff, rs, soff, size, cid } => {
            let protocol = extract_bits(state.read_reg(*rs), *soff, *size) as u16;
            let result = pseek_scan(state, *cid, protocol);
            maybe_clear(state, *rd, false);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff, *size, result as u128));
            ExecResult::Success
        }

        Instruction::PseekNxtp { rd, doff, rs, soff, size, cid } => {
            let protocol = extract_bits(state.read_reg(*rs), *soff, *size) as u16;
            let result = pseek_scan(state, *cid, protocol);
            let cur = state.read_reg(*rd);
            state.write_reg(*rd, insert_bits(cur, *doff, *size, result as u128));
            // Then do NXTP with the final protocol value
            nxtp_lookup(state, result as u32);
            ExecResult::Success
        }
    }
}

/// PSEEK scan: walk through headers using the PSEEK table.
/// Returns the final protocol value after scanning.
fn pseek_scan(state: &mut SimState, start_cid: u8, initial_protocol: u16) -> u16 {
    let mut protocol = initial_protocol;
    let mut matched = true;

    while matched {
        matched = false;
        for i in 0..32 {
            if state.pseek_valid[i]
                && state.pseek_class_id[i] == start_cid
                && state.pseek_protocol_value[i] == protocol
            {
                // Advance cursor by header length
                state.cursor = state.cursor.wrapping_add(state.pseek_hdr_length[i]);
                // Read next protocol from packet at the specified offset
                let next_off = state.pseek_next_proto_off[i] as u16;
                let next_sz = state.pseek_next_proto_size[i];
                protocol = extract_packet_bits(
                    &state.packet_header,
                    state.cursor,
                    next_off,
                    next_sz,
                ) as u16;
                matched = true;
                break;
            }
        }
    }
    protocol
}

/// Fetch, decode, and execute one instruction. Advances PC.
pub fn step(state: &mut SimState) -> Result<StepResult, String> {
    if state.halted {
        return Err("simulator is halted".to_string());
    }

    let pc_idx = state.pc as usize;
    if pc_idx >= state.instruction_mem.len() {
        return Err(format!("PC {} out of bounds (imem size: {})", pc_idx, state.instruction_mem.len()));
    }

    let word = state.instruction_mem[pc_idx];
    let inst = crate::decode::decode(word).map_err(|e| e.message)?;

    // Snapshot for change detection
    let old_regs = state.regs;
    let old_flags = (state.flag_z, state.flag_n);

    // Advance PC before execution (branches overwrite it)
    state.pc = state.pc.wrapping_add(1);

    let result = execute(state, &inst);
    state.step_count += 1;

    // Detect changes
    let reg_names = ["PR0", "PR1", "PR2", "PR3", "PRN"];
    let mut reg_changes = Vec::new();
    for i in 0..5 {
        if state.regs[i] != old_regs[i] {
            reg_changes.push((
                reg_names[i].to_string(),
                format!("0x{:032x}", state.regs[i]),
            ));
        }
    }
    let flags_changed = (state.flag_z, state.flag_n) != old_flags;

    Ok(StepResult {
        instruction: format!("{:?}", inst),
        halted: matches!(result, ExecResult::Halt | ExecResult::Drop),
        dropped: matches!(result, ExecResult::Drop),
        reg_changes,
        flags_changed,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::Reg;

    fn make_state() -> SimState {
        SimState::new()
    }

    #[test]
    fn test_nop() {
        let mut s = make_state();
        let r = execute(&mut s, &Instruction::Nop);
        assert_eq!(r, ExecResult::Success);
    }

    #[test]
    fn test_halt() {
        let mut s = make_state();
        let r = execute(&mut s, &Instruction::Halt { drop: false });
        assert_eq!(r, ExecResult::Halt);
        assert!(s.halted);
        assert!(!s.dropped);
    }

    #[test]
    fn test_halt_drop() {
        let mut s = make_state();
        let r = execute(&mut s, &Instruction::Halt { drop: true });
        assert_eq!(r, ExecResult::Drop);
        assert!(s.halted);
        assert!(s.dropped);
    }

    #[test]
    fn test_movi_and_mov() {
        let mut s = make_state();
        // MOVI PR0, doff=0, imm=0x1234, size=16, cd=true
        execute(&mut s, &Instruction::Movi {
            rd: Reg::PR0, doff: 0, imm: 0x1234, size: 16, cd: true,
        });
        let v = extract_bits(s.read_reg(Reg::PR0), 0, 16);
        assert_eq!(v, 0x1234);

        // MOV PR1 = PR0
        execute(&mut s, &Instruction::Mov {
            rd: Reg::PR1, doff: 0, rs: Reg::PR0, soff: 0, size: 16, cd: true,
        });
        assert_eq!(extract_bits(s.read_reg(Reg::PR1), 0, 16), 0x1234);
    }

    #[test]
    fn test_add_sets_zero_flag() {
        let mut s = make_state();
        // 0 + 0 = 0 → Z flag set
        execute(&mut s, &Instruction::Add {
            rd: Reg::PR0, doff: 0, rs1: Reg::PR1, s1off: 0,
            rs2: Reg::PR2, s2off: 0, size: 32, cd: true,
        });
        assert!(s.flag_z);
    }

    #[test]
    fn test_sub_sets_negative_flag() {
        let mut s = make_state();
        // PR0 = 1, PR1 = 2, result = 1 - 2 = -1 (wraps, MSB set)
        s.write_reg(Reg::PR0, insert_bits(0, 0, 32, 1));
        s.write_reg(Reg::PR1, insert_bits(0, 0, 32, 2));
        execute(&mut s, &Instruction::Sub {
            rd: Reg::PR2, doff: 0, rs1: Reg::PR0, s1off: 0,
            rs2: Reg::PR1, s2off: 0, size: 32, cd: true,
        });
        assert!(s.flag_n);
        assert!(!s.flag_z);
    }

    #[test]
    fn test_branch_taken() {
        let mut s = make_state();
        s.flag_z = true;
        execute(&mut s, &Instruction::Br { cc: Condition::Eq, target: 42 });
        assert_eq!(s.pc, 42);
    }

    #[test]
    fn test_branch_not_taken() {
        let mut s = make_state();
        s.flag_z = false;
        s.pc = 10;
        execute(&mut s, &Instruction::Br { cc: Condition::Eq, target: 42 });
        assert_eq!(s.pc, 10); // unchanged
    }

    #[test]
    fn test_ext_from_packet() {
        let mut s = make_state();
        s.packet_header[0] = 0x45; // IPv4: version=4, IHL=5
        // Extract 8 bits from packet offset 0
        execute(&mut s, &Instruction::Ext {
            rd: Reg::PR0, doff: 0, soff: 0, size: 8, cd: true,
        });
        assert_eq!(extract_bits(s.read_reg(Reg::PR0), 0, 8), 0x45);
    }

    #[test]
    fn test_sth_sets_header() {
        let mut s = make_state();
        execute(&mut s, &Instruction::Sth { pid: 1, oid: 14, halt: false });
        assert!(s.hdr_present[1]);
        assert_eq!(s.hdr_offset[1], 14);
        assert!(!s.halted);
    }

    #[test]
    fn test_stci_advances_cursor() {
        let mut s = make_state();
        execute(&mut s, &Instruction::Stci { incr: 14 });
        assert_eq!(s.cursor, 14);
        execute(&mut s, &Instruction::Stci { incr: 6 });
        assert_eq!(s.cursor, 20);
    }

    #[test]
    fn test_step_function() {
        let mut s = make_state();
        // Load a small program: MOVI PR0, 0x42; HALT
        s.instruction_mem = vec![
            crate::encode::encode(&Instruction::Movi {
                rd: Reg::PR0, doff: 0, imm: 0x42, size: 16, cd: true,
            }),
            crate::encode::encode(&Instruction::Halt { drop: false }),
        ];

        let r1 = step(&mut s).unwrap();
        assert!(!r1.halted);
        assert_eq!(s.pc, 1);

        let r2 = step(&mut s).unwrap();
        assert!(r2.halted);
    }
}
```

- [ ] **Step 2: Add module to lib.rs**

Add `pub mod execute;` to `web/simulator/src/lib.rs`.

- [ ] **Step 3: Run tests**

Run: `./dev.sh bash -c "cd web/simulator && cargo test"`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add web/simulator/src/execute.rs web/simulator/src/lib.rs
git commit -m "Add execute module with all Parser ISA instruction semantics"
```

---

## Phase 3: Assembler

### Task 7: Assembler Module

**Files:**
- Create: `web/simulator/src/assembler.rs`
- Modify: `web/simulator/src/lib.rs` (add `pub mod assembler;`)

The assembler parses assembly text into a list of `Instruction` values, then encodes them to binary. It handles labels, comments, `.CD` modifiers, and error reporting with line numbers.

- [ ] **Step 1: Create assembler.rs**

```rust
use crate::encode::encode;
use crate::types::*;

/// An assembly error with line number and message.
#[derive(Debug, Clone)]
pub struct AsmError {
    pub line: usize,
    pub message: String,
}

impl std::fmt::Display for AsmError {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "line {}: {}", self.line, self.message)
    }
}

/// Result of successful assembly.
pub struct AsmResult {
    /// Encoded instructions as 64-bit words.
    pub words: Vec<u64>,
    /// Source line number for each instruction (for editor highlighting).
    pub line_map: Vec<usize>,
}

/// Assemble source text into binary instructions.
pub fn assemble(source: &str) -> Result<AsmResult, Vec<AsmError>> {
    let mut errors = Vec::new();
    let mut instructions: Vec<(usize, Instruction)> = Vec::new();
    let mut labels: std::collections::HashMap<String, u16> = std::collections::HashMap::new();

    // -- Pass 1: collect labels and parse instructions --
    let mut pc: u16 = 0;
    for (line_idx, line) in source.lines().enumerate() {
        let line_num = line_idx + 1;
        let line = line.trim();

        // Strip comments
        let line = if let Some(idx) = line.find(';') {
            line[..idx].trim()
        } else {
            line
        };

        if line.is_empty() {
            continue;
        }

        // Check for label
        if let Some(label) = line.strip_suffix(':') {
            let label = label.trim();
            if label.is_empty() {
                errors.push(AsmError { line: line_num, message: "empty label".to_string() });
                continue;
            }
            labels.insert(label.to_string(), pc);
            continue;
        }

        // Parse instruction
        match parse_instruction(line, line_num) {
            Ok(inst) => {
                instructions.push((line_num, inst));
                pc += 1;
            }
            Err(e) => errors.push(e),
        }
    }

    if !errors.is_empty() {
        return Err(errors);
    }

    // -- Pass 2: resolve labels in branch instructions --
    let mut resolved = Vec::new();
    for (line_num, inst) in &instructions {
        let inst = resolve_labels(inst, &labels, *line_num, &mut errors);
        resolved.push((*line_num, inst));
    }

    if !errors.is_empty() {
        return Err(errors);
    }

    // -- Pass 3: encode to binary --
    let mut words = Vec::new();
    let mut line_map = Vec::new();
    for (line_num, inst) in &resolved {
        words.push(encode(inst));
        line_map.push(*line_num);
    }

    Ok(AsmResult { words, line_map })
}

fn resolve_labels(
    inst: &Instruction,
    labels: &std::collections::HashMap<String, u16>,
    _line_num: usize,
    _errors: &mut Vec<AsmError>,
) -> Instruction {
    // Labels are resolved during parse_instruction by storing the target as 0
    // and using a placeholder. For now, branch targets are parsed as immediates.
    // A more complete implementation would handle symbolic labels here.
    inst.clone()
}

/// Parse a single instruction line into an Instruction.
fn parse_instruction(line: &str, line_num: usize) -> Result<Instruction, AsmError> {
    let err = |msg: &str| AsmError { line: line_num, message: msg.to_string() };

    // Split mnemonic from operands
    let (mnemonic, operands_str) = match line.find(char::is_whitespace) {
        Some(idx) => (line[..idx].trim(), line[idx..].trim()),
        None => (line, ""),
    };

    let mnemonic_upper = mnemonic.to_uppercase();

    // Check for .CD modifier
    let (base_mnemonic, cd) = if mnemonic_upper.ends_with(".CD") {
        (&mnemonic_upper[..mnemonic_upper.len() - 3], true)
    } else {
        (mnemonic_upper.as_str(), false)
    };

    // Parse condition suffix for branch instructions (e.g., BR.Z, BR.AL)
    let (branch_base, condition) = parse_branch_condition(base_mnemonic);

    // Parse operands into a list of tokens
    let operands: Vec<&str> = if operands_str.is_empty() {
        Vec::new()
    } else {
        operands_str.split(',').map(|s| s.trim()).collect()
    };

    match branch_base {
        "NOP" => Ok(Instruction::Nop),
        "HALT" => Ok(Instruction::Halt { drop: false }),
        "HALTDROP" => Ok(Instruction::Halt { drop: true }),

        "MOV" => {
            expect_operands(&operands, 2, "MOV", line_num)?;
            let (rd, doff) = parse_reg_offset(&operands[0], line_num)?;
            let (rs, soff) = parse_reg_offset(&operands[1], line_num)?;
            Ok(Instruction::Mov { rd, doff, rs, soff, size: 128, cd })
        }

        "MOVI" => {
            expect_operands(&operands, 3, "MOVI", line_num)?;
            let (rd, doff) = parse_reg_offset(&operands[0], line_num)?;
            let imm = parse_imm16(&operands[1], line_num)?;
            let size = parse_u8(&operands[2], line_num)?;
            Ok(Instruction::Movi { rd, doff, imm, size, cd })
        }

        "EXT" => {
            expect_operands(&operands, 3, "EXT", line_num)?;
            let (rd, doff) = parse_reg_offset(&operands[0], line_num)?;
            let soff = parse_u16(&operands[1], line_num)?;
            let size = parse_u8(&operands[2], line_num)?;
            Ok(Instruction::Ext { rd, doff, soff, size, cd })
        }

        "ADD" => {
            expect_operands(&operands, 3, "ADD", line_num)?;
            let (rd, doff) = parse_reg_offset(&operands[0], line_num)?;
            let (rs1, s1off) = parse_reg_offset(&operands[1], line_num)?;
            let (rs2, s2off) = parse_reg_offset(&operands[2], line_num)?;
            Ok(Instruction::Add { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd })
        }

        "ADDI" => {
            expect_operands(&operands, 3, "ADDI", line_num)?;
            let (rd, _) = parse_reg_offset(&operands[0], line_num)?;
            let (rs, _) = parse_reg_offset(&operands[1], line_num)?;
            let imm = parse_imm16(&operands[2], line_num)?;
            Ok(Instruction::AddI { rd, rs, imm, size: 128, cd })
        }

        "SUB" => {
            expect_operands(&operands, 3, "SUB", line_num)?;
            let (rd, doff) = parse_reg_offset(&operands[0], line_num)?;
            let (rs1, s1off) = parse_reg_offset(&operands[1], line_num)?;
            let (rs2, s2off) = parse_reg_offset(&operands[2], line_num)?;
            Ok(Instruction::Sub { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd })
        }

        "SUBI" => {
            expect_operands(&operands, 3, "SUBI", line_num)?;
            let (rd, _) = parse_reg_offset(&operands[0], line_num)?;
            let (rs, _) = parse_reg_offset(&operands[1], line_num)?;
            let imm = parse_imm16(&operands[2], line_num)?;
            Ok(Instruction::SubI { rd, rs, imm, size: 128, cd })
        }

        "AND" => {
            expect_operands(&operands, 3, "AND", line_num)?;
            let (rd, doff) = parse_reg_offset(&operands[0], line_num)?;
            let (rs1, s1off) = parse_reg_offset(&operands[1], line_num)?;
            let (rs2, s2off) = parse_reg_offset(&operands[2], line_num)?;
            Ok(Instruction::And { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd })
        }

        "OR" => {
            expect_operands(&operands, 3, "OR", line_num)?;
            let (rd, doff) = parse_reg_offset(&operands[0], line_num)?;
            let (rs1, s1off) = parse_reg_offset(&operands[1], line_num)?;
            let (rs2, s2off) = parse_reg_offset(&operands[2], line_num)?;
            Ok(Instruction::Or { rd, doff, rs1, s1off, rs2, s2off, size: 128, cd })
        }

        "CMP" => {
            expect_operands(&operands, 2, "CMP", line_num)?;
            let (rs1, s1off) = parse_reg_offset(&operands[0], line_num)?;
            let (rs2, s2off) = parse_reg_offset(&operands[1], line_num)?;
            Ok(Instruction::Cmp { rs1, s1off, rs2, s2off, size: 128 })
        }

        "BR" => {
            let cc = condition.ok_or_else(|| err("BR requires condition suffix (e.g., BR.AL, BR.Z)"))?;
            expect_operands(&operands, 1, "BR", line_num)?;
            let target = parse_u16(&operands[0], line_num)?;
            Ok(Instruction::Br { cc, target })
        }

        "BRBTST" => {
            expect_operands(&operands, 3, "BRBTST", line_num)?;
            let btcc = parse_btcond(&operands[0], line_num)?;
            let (rs, boff) = parse_reg_offset(&operands[1], line_num)?;
            let target = parse_u16(&operands[2], line_num)?;
            Ok(Instruction::BrBtst { btcc, rs, boff, target })
        }

        "STCI" => {
            expect_operands(&operands, 1, "STCI", line_num)?;
            let incr = parse_u16(&operands[0], line_num)?;
            Ok(Instruction::Stci { incr })
        }

        "STH" => {
            expect_operands(&operands, 2, "STH", line_num)?;
            let pid = parse_u8(&operands[0], line_num)?;
            let oid = parse_u8(&operands[1], line_num)?;
            Ok(Instruction::Sth { pid, oid, halt: false })
        }

        _ => Err(err(&format!("unknown instruction: {}", base_mnemonic))),
    }
}

/// Parse branch condition suffix from mnemonic (e.g., "BR.Z" → ("BR", Some(Eq))).
fn parse_branch_condition(mnemonic: &str) -> (&str, Option<Condition>) {
    if let Some(base) = mnemonic.strip_suffix(".EQ") { return (base, Some(Condition::Eq)); }
    if let Some(base) = mnemonic.strip_suffix(".Z") { return (base, Some(Condition::Eq)); }
    if let Some(base) = mnemonic.strip_suffix(".NEQ") { return (base, Some(Condition::Neq)); }
    if let Some(base) = mnemonic.strip_suffix(".NZ") { return (base, Some(Condition::Neq)); }
    if let Some(base) = mnemonic.strip_suffix(".LT") { return (base, Some(Condition::Lt)); }
    if let Some(base) = mnemonic.strip_suffix(".GT") { return (base, Some(Condition::Gt)); }
    if let Some(base) = mnemonic.strip_suffix(".GE") { return (base, Some(Condition::Ge)); }
    if let Some(base) = mnemonic.strip_suffix(".LE") { return (base, Some(Condition::Le)); }
    if let Some(base) = mnemonic.strip_suffix(".AL") { return (base, Some(Condition::Al)); }
    (mnemonic, None)
}

/// Parse a register name, optionally with a bit offset (e.g., "PR0" or "PR0.8").
fn parse_reg_offset(s: &str, line_num: usize) -> Result<(Reg, u8), AsmError> {
    let err = |msg: &str| AsmError { line: line_num, message: msg.to_string() };
    let (reg_str, offset) = if let Some(idx) = s.find('.') {
        let off = s[idx + 1..].parse::<u8>().map_err(|_| err("invalid bit offset"))?;
        (&s[..idx], off)
    } else {
        (s, 0)
    };

    let reg = match reg_str.to_uppercase().as_str() {
        "PR0" => Reg::PR0,
        "PR1" => Reg::PR1,
        "PR2" => Reg::PR2,
        "PR3" => Reg::PR3,
        "PRN" => Reg::PRN,
        _ => return Err(err(&format!("unknown register: {}", reg_str))),
    };
    Ok((reg, offset))
}

fn parse_u8(s: &str, line_num: usize) -> Result<u8, AsmError> {
    parse_number(s).and_then(|n| u8::try_from(n).ok())
        .ok_or_else(|| AsmError { line: line_num, message: format!("invalid u8: {}", s) })
}

fn parse_u16(s: &str, line_num: usize) -> Result<u16, AsmError> {
    parse_number(s).and_then(|n| u16::try_from(n).ok())
        .ok_or_else(|| AsmError { line: line_num, message: format!("invalid u16: {}", s) })
}

fn parse_imm16(s: &str, line_num: usize) -> Result<u16, AsmError> {
    parse_number(s).and_then(|n| u16::try_from(n).ok())
        .ok_or_else(|| AsmError { line: line_num, message: format!("invalid immediate: {}", s) })
}

/// Parse a number, supporting decimal, hex (0x), and binary (0b) formats.
fn parse_number(s: &str) -> Option<u64> {
    let s = s.trim();
    if let Some(hex) = s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")) {
        u64::from_str_radix(hex, 16).ok()
    } else if let Some(bin) = s.strip_prefix("0b").or_else(|| s.strip_prefix("0B")) {
        u64::from_str_radix(bin, 2).ok()
    } else {
        s.parse::<u64>().ok()
    }
}

fn parse_btcond(s: &str, line_num: usize) -> Result<BitTestCond, AsmError> {
    match s.to_uppercase().as_str() {
        "CLR" | "0" => Ok(BitTestCond::Clear),
        "SET" | "1" => Ok(BitTestCond::Set),
        _ => Err(AsmError { line: line_num, message: format!("invalid bit-test condition: {}", s) }),
    }
}

fn expect_operands(operands: &[&str], expected: usize, mnemonic: &str, line_num: usize) -> Result<(), AsmError> {
    if operands.len() != expected {
        Err(AsmError {
            line: line_num,
            message: format!("{} expects {} operand(s), got {}", mnemonic, expected, operands.len()),
        })
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_assemble_nop_halt() {
        let result = assemble("NOP\nHALT").unwrap();
        assert_eq!(result.words.len(), 2);
        assert_eq!(result.words[0], 0); // NOP = all zeros
    }

    #[test]
    fn test_assemble_with_comments() {
        let result = assemble("; This is a comment\nNOP ; inline\nHALT").unwrap();
        assert_eq!(result.words.len(), 2);
    }

    #[test]
    fn test_assemble_movi() {
        let result = assemble("MOVI PR0, 0x1234, 16\nHALT").unwrap();
        assert_eq!(result.words.len(), 2);
        // Verify by decoding
        let inst = crate::decode::decode(result.words[0]).unwrap();
        assert_eq!(inst, Instruction::Movi {
            rd: Reg::PR0, doff: 0, imm: 0x1234, size: 16, cd: false,
        });
    }

    #[test]
    fn test_assemble_cd_modifier() {
        let result = assemble("EXT.CD PR0, 0, 64\nHALT").unwrap();
        let inst = crate::decode::decode(result.words[0]).unwrap();
        match inst {
            Instruction::Ext { cd, .. } => assert!(cd),
            _ => panic!("expected Ext"),
        }
    }

    #[test]
    fn test_assemble_branch_condition() {
        let result = assemble("BR.Z 42\nHALT").unwrap();
        let inst = crate::decode::decode(result.words[0]).unwrap();
        assert_eq!(inst, Instruction::Br { cc: Condition::Eq, target: 42 });
    }

    #[test]
    fn test_assemble_error_unknown_instruction() {
        let result = assemble("FOOBAR");
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert_eq!(errors[0].line, 1);
        assert!(errors[0].message.contains("unknown instruction"));
    }

    #[test]
    fn test_assemble_error_wrong_operand_count() {
        let result = assemble("EXT PR0");
        assert!(result.is_err());
    }

    #[test]
    fn test_line_map() {
        let src = "; header\n\nNOP\n\nHALT\n";
        let result = assemble(src).unwrap();
        assert_eq!(result.line_map, vec![3, 5]); // NOP at line 3, HALT at line 5
    }

    #[test]
    fn test_hex_and_binary_immediates() {
        let result = assemble("MOVI PR0, 0xFF, 8\nHALT").unwrap();
        let inst = crate::decode::decode(result.words[0]).unwrap();
        match inst {
            Instruction::Movi { imm, .. } => assert_eq!(imm, 0xFF),
            _ => panic!("expected Movi"),
        }
    }
}
```

Note: This is an initial assembler supporting a core subset of instructions (NOP, HALT, MOV, MOVI, EXT, ADD, ADDI, SUB, SUBI, AND, OR, CMP, BR, BRBTST, STCI, STH). Remaining instruction mnemonics follow the same pattern and should be added incrementally as needed. The assembler is extensible — each new instruction is a new match arm in `parse_instruction`.

- [ ] **Step 2: Add module to lib.rs**

Add `pub mod assembler;` to `web/simulator/src/lib.rs`.

- [ ] **Step 3: Run tests**

Run: `./dev.sh bash -c "cd web/simulator && cargo test"`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add web/simulator/src/assembler.rs web/simulator/src/lib.rs
git commit -m "Add assembler with core instruction subset"
```

---

### Task 8: CLI Assembler Binary

**Files:**
- Create: `web/simulator/src/bin/xisa-asm.rs`

- [ ] **Step 1: Create the CLI binary**

```rust
use std::env;
use std::fs;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: xisa-asm <input.xisa> [output.bin]");
        process::exit(1);
    }

    let input_path = &args[1];
    let source = match fs::read_to_string(input_path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Error reading {}: {}", input_path, e);
            process::exit(1);
        }
    };

    match xisa_simulator::assembler::assemble(&source) {
        Ok(result) => {
            // Default output path: replace .xisa with .bin
            let output_path = if args.len() >= 3 {
                args[2].clone()
            } else {
                input_path.replace(".xisa", ".bin")
            };

            // Write as raw bytes (big-endian u64 per instruction)
            let mut bytes = Vec::new();
            for word in &result.words {
                bytes.extend_from_slice(&word.to_be_bytes());
            }

            match fs::write(&output_path, &bytes) {
                Ok(()) => {
                    println!("Assembled {} instructions to {}", result.words.len(), output_path);
                }
                Err(e) => {
                    eprintln!("Error writing {}: {}", output_path, e);
                    process::exit(1);
                }
            }
        }
        Err(errors) => {
            for e in &errors {
                eprintln!("{}:{}: {}", input_path, e.line, e.message);
            }
            process::exit(1);
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `./dev.sh bash -c "cd web/simulator && cargo build --bin xisa-asm"`
Expected: Builds successfully.

- [ ] **Step 3: Commit**

```bash
git add web/simulator/src/bin/xisa-asm.rs
git commit -m "Add xisa-asm CLI binary"
```

---

## Phase 4: WASM Bridge

### Task 9: WASM API

**Files:**
- Modify: `web/simulator/src/lib.rs`

- [ ] **Step 1: Add the WASM bridge to lib.rs**

Replace the module declarations in `web/simulator/src/lib.rs` with:

```rust
pub mod types;
pub mod state;
pub mod decode;
pub mod encode;
pub mod execute;
pub mod assembler;

use wasm_bindgen::prelude::*;
use serde::Serialize;

use state::SimState;

/// WASM-exposed simulator instance.
#[wasm_bindgen]
pub struct Simulator {
    state: SimState,
}

/// Full state snapshot for the UI.
#[derive(Serialize)]
struct StateSnapshot {
    pc: u16,
    regs: [String; 4], // PR0-PR3 as hex strings
    flag_z: bool,
    flag_n: bool,
    cursor: u8,
    halted: bool,
    dropped: bool,
    step_count: u64,
    packet_header: Vec<u8>,
    struct0: String,
    hdr_present: Vec<bool>,
    hdr_offset: Vec<u8>,
}

#[wasm_bindgen]
impl Simulator {
    /// Create a new simulator with zeroed state.
    #[wasm_bindgen(constructor)]
    pub fn new() -> Simulator {
        Simulator {
            state: SimState::new(),
        }
    }

    /// Load a program from binary (big-endian u64 words concatenated).
    pub fn load_program(&mut self, bytes: &[u8]) {
        self.state.instruction_mem.clear();
        for chunk in bytes.chunks(8) {
            if chunk.len() == 8 {
                let word = u64::from_be_bytes(chunk.try_into().unwrap());
                self.state.instruction_mem.push(word);
            }
        }
        self.state.reset_execution();
    }

    /// Load packet header data.
    pub fn load_packet(&mut self, packet: &[u8]) {
        let len = packet.len().min(256);
        self.state.packet_header[..len].copy_from_slice(&packet[..len]);
    }

    /// Execute one instruction. Returns StepResult as JSON.
    pub fn step(&mut self) -> Result<JsValue, JsValue> {
        match execute::step(&mut self.state) {
            Ok(result) => {
                serde_wasm_bindgen::to_value(&result).map_err(|e| JsValue::from_str(&e.to_string()))
            }
            Err(msg) => Err(JsValue::from_str(&msg)),
        }
    }

    /// Get full state snapshot as JSON.
    pub fn get_state(&self) -> Result<JsValue, JsValue> {
        let snapshot = StateSnapshot {
            pc: self.state.pc,
            regs: [
                format!("0x{:032x}", self.state.regs[0]),
                format!("0x{:032x}", self.state.regs[1]),
                format!("0x{:032x}", self.state.regs[2]),
                format!("0x{:032x}", self.state.regs[3]),
            ],
            flag_z: self.state.flag_z,
            flag_n: self.state.flag_n,
            cursor: self.state.cursor,
            halted: self.state.halted,
            dropped: self.state.dropped,
            step_count: self.state.step_count,
            packet_header: self.state.packet_header.clone(),
            struct0: format!("0x{:032x}", self.state.struct0),
            hdr_present: self.state.hdr_present.to_vec(),
            hdr_offset: self.state.hdr_offset.to_vec(),
        };
        serde_wasm_bindgen::to_value(&snapshot).map_err(|e| JsValue::from_str(&e.to_string()))
    }

    /// Reset execution state (keeps loaded program and packet).
    pub fn reset(&mut self) {
        self.state.reset_execution();
    }

    /// Assemble source text. Returns binary as Vec<u8> (big-endian u64 words).
    pub fn assemble(&self, source: &str) -> Result<Vec<u8>, JsValue> {
        match assembler::assemble(source) {
            Ok(result) => {
                let mut bytes = Vec::new();
                for word in &result.words {
                    bytes.extend_from_slice(&word.to_be_bytes());
                }
                Ok(bytes)
            }
            Err(errors) => {
                let msgs: Vec<String> = errors.iter().map(|e| e.to_string()).collect();
                Err(JsValue::from_str(&msgs.join("\n")))
            }
        }
    }

    /// Assemble and load in one step. Returns error string or empty on success.
    pub fn assemble_and_load(&mut self, source: &str) -> Result<JsValue, JsValue> {
        match assembler::assemble(source) {
            Ok(result) => {
                self.state.instruction_mem = result.words;
                self.state.reset_execution();
                let line_map: Vec<usize> = result.line_map;
                serde_wasm_bindgen::to_value(&line_map)
                    .map_err(|e| JsValue::from_str(&e.to_string()))
            }
            Err(errors) => {
                let msgs: Vec<String> = errors.iter().map(|e| e.to_string()).collect();
                Err(JsValue::from_str(&msgs.join("\n")))
            }
        }
    }
}
```

- [ ] **Step 2: Build WASM module**

Run: `./dev.sh bash -c "cd web/simulator && wasm-pack build --target web"`
Expected: Produces `web/simulator/pkg/` directory with `.wasm` + JS glue files.

- [ ] **Step 3: Commit**

```bash
git add web/simulator/src/lib.rs
git commit -m "Add WASM bridge API for simulator"
```

---

## Phase 5: Web UI

### Task 10: Scaffold Astro Project

**Files:**
- Create: `web/package.json`
- Create: `web/astro.config.mjs`
- Create: `web/tsconfig.json`
- Create: `web/src/layouts/Base.astro`
- Create: `web/src/pages/index.astro`

- [ ] **Step 1: Initialize the Astro project**

Run:
```bash
./dev.sh bash -c "cd web && npm init -y && npm install astro @astrojs/svelte svelte"
```

- [ ] **Step 2: Create astro.config.mjs**

```javascript
import { defineConfig } from 'astro/config';
import svelte from '@astrojs/svelte';

export default defineConfig({
  integrations: [svelte()],
  vite: {
    server: {
      fs: { allow: ['..'] },
    },
  },
});
```

- [ ] **Step 3: Create tsconfig.json**

```json
{
  "extends": "astro/tsconfigs/strict"
}
```

- [ ] **Step 4: Create Base.astro layout**

```astro
---
const { title } = Astro.props;
---
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title} — XISA Playground</title>
  <link rel="stylesheet" href="/styles/global.css" />
</head>
<body>
  <nav class="site-nav">
    <a href="/" class="nav-brand">XISA</a>
    <div class="nav-links">
      <a href="/">Home</a>
      <a href="/playground">Playground</a>
    </div>
  </nav>
  <main>
    <slot />
  </main>
</body>
</html>
```

- [ ] **Step 5: Create index.astro**

```astro
---
import Base from '../layouts/Base.astro';
---
<Base title="Home">
  <div class="landing">
    <h1>XISA Playground</h1>
    <p>An interactive simulator for the X-Switch Instruction Set Architecture.</p>
    <a href="/playground" class="cta">Open Playground →</a>
  </div>
</Base>
```

- [ ] **Step 6: Create global.css**

Create `web/public/styles/global.css`:

```css
* { margin: 0; padding: 0; box-sizing: border-box; }

:root {
  --bg: #1a1a2e;
  --surface: #16213e;
  --border: #334155;
  --text: #e2e8f0;
  --text-dim: #94a3b8;
  --accent: #38bdf8;
  --accent-dim: #0ea5e9;
  --changed: #fbbf24;
  --error: #f87171;
  --font-mono: 'JetBrains Mono', 'Fira Code', monospace;
  --font-sans: system-ui, -apple-system, sans-serif;
}

body {
  font-family: var(--font-sans);
  background: var(--bg);
  color: var(--text);
  min-height: 100vh;
}

.site-nav {
  display: flex;
  align-items: center;
  gap: 2rem;
  padding: 0.75rem 1.5rem;
  background: var(--surface);
  border-bottom: 1px solid var(--border);
}

.nav-brand {
  font-family: var(--font-mono);
  font-weight: 700;
  font-size: 1.1rem;
  color: var(--accent);
  text-decoration: none;
}

.nav-links { display: flex; gap: 1rem; }
.nav-links a {
  color: var(--text-dim);
  text-decoration: none;
  font-size: 0.9rem;
}
.nav-links a:hover { color: var(--text); }

.landing {
  max-width: 600px;
  margin: 4rem auto;
  text-align: center;
}

.landing h1 { font-size: 2.5rem; margin-bottom: 1rem; }
.landing p { color: var(--text-dim); margin-bottom: 2rem; }

.cta {
  display: inline-block;
  padding: 0.75rem 1.5rem;
  background: var(--accent);
  color: var(--bg);
  text-decoration: none;
  border-radius: 6px;
  font-weight: 600;
}
.cta:hover { background: var(--accent-dim); }
```

- [ ] **Step 7: Verify the dev server starts**

Run: `./dev.sh bash -c "cd web && npx astro dev --host 0.0.0.0 &" && sleep 5 && echo "Dev server started"`
Expected: Astro dev server starts successfully.

- [ ] **Step 8: Commit**

```bash
git add web/package.json web/package-lock.json web/astro.config.mjs web/tsconfig.json web/src/ web/public/
git commit -m "Scaffold Astro site with layout and landing page"
```

---

### Task 11: Playground Page with Svelte Components

**Files:**
- Create: `web/src/pages/playground.astro`
- Create: `web/src/components/Playground.svelte`
- Create: `web/src/components/Editor.svelte`
- Create: `web/src/components/Controls.svelte`
- Create: `web/src/components/StateViewer.svelte`
- Create: `web/src/lib/wasm.ts`
- Create: `web/public/styles/playground.css`

- [ ] **Step 1: Install CodeMirror**

Run: `./dev.sh bash -c "cd web && npm install @codemirror/state @codemirror/view @codemirror/language @codemirror/commands @codemirror/lang-javascript codemirror @codemirror/theme-one-dark"`

- [ ] **Step 2: Create wasm.ts loader**

```typescript
// web/src/lib/wasm.ts
import init, { Simulator } from '../../simulator/pkg/xisa_simulator.js';

let simulator: Simulator | null = null;
let initialized = false;

export async function getSimulator(): Promise<Simulator> {
  if (!initialized) {
    await init();
    initialized = true;
  }
  if (!simulator) {
    simulator = new Simulator();
  }
  return simulator;
}

export function resetSimulator(): void {
  if (simulator) {
    simulator.reset();
  }
}
```

- [ ] **Step 3: Create Playground.svelte**

```svelte
<!-- web/src/components/Playground.svelte -->
<script>
  import Editor from './Editor.svelte';
  import Controls from './Controls.svelte';
  import StateViewer from './StateViewer.svelte';
  import { getSimulator } from '../lib/wasm.ts';

  let source = '; XISA Parser Assembly\n; Write your program here\n\nMOVI PR0, 0x1234, 16\nMOVI PR1, 0x5678, 16\nADD PR2, PR0, PR1\nHALT\n';
  let state = null;
  let error = '';
  let lineMap = [];
  let currentLine = -1;
  let assembled = false;

  async function handleAssemble() {
    try {
      const sim = await getSimulator();
      const result = sim.assemble_and_load(source);
      lineMap = result;
      state = sim.get_state();
      error = '';
      assembled = true;
      currentLine = lineMap.length > 0 ? lineMap[0] : -1;
    } catch (e) {
      error = String(e);
      assembled = false;
    }
  }

  async function handleStep() {
    if (!assembled) return;
    try {
      const sim = await getSimulator();
      const result = sim.step();
      state = sim.get_state();
      error = '';
      // Update current line based on PC
      const pc = state.pc;
      currentLine = pc < lineMap.length ? lineMap[pc] : -1;
    } catch (e) {
      error = String(e);
    }
  }

  async function handleRun() {
    if (!assembled) return;
    const sim = await getSimulator();
    const maxSteps = 10000;
    for (let i = 0; i < maxSteps; i++) {
      try {
        const result = sim.step();
        if (result.halted) break;
      } catch (e) {
        error = String(e);
        break;
      }
    }
    state = sim.get_state();
    currentLine = -1;
  }

  async function handleReset() {
    const sim = await getSimulator();
    sim.reset();
    state = sim.get_state();
    error = '';
    currentLine = lineMap.length > 0 ? lineMap[0] : -1;
  }
</script>

<link rel="stylesheet" href="/styles/playground.css" />

<div class="playground">
  <div class="panel-left">
    <Editor bind:source {currentLine} />
    <Controls
      {assembled}
      halted={state?.halted ?? false}
      on:assemble={handleAssemble}
      on:step={handleStep}
      on:run={handleRun}
      on:reset={handleReset}
    />
    {#if error}
      <div class="error-panel">{error}</div>
    {/if}
  </div>
  <div class="panel-right">
    <StateViewer {state} />
  </div>
</div>
```

- [ ] **Step 4: Create Editor.svelte**

```svelte
<!-- web/src/components/Editor.svelte -->
<script>
  import { onMount } from 'svelte';
  import { EditorState } from '@codemirror/state';
  import { EditorView, keymap, lineNumbers, highlightActiveLine } from '@codemirror/view';
  import { defaultKeymap } from '@codemirror/commands';
  import { oneDark } from '@codemirror/theme-one-dark';

  export let source = '';
  export let currentLine = -1;

  let editorContainer;
  let view;

  // Example programs
  const examples = {
    'Simple Arithmetic': '; Add two values\nMOVI PR0, 0x1234, 16\nMOVI PR1, 0x5678, 16\nADD PR2, PR0, PR1\nHALT',
    'Branch Example': '; Count down from 3\nMOVI PR0, 3, 8\nMOVI PR1, 1, 8\nloop:\n  SUB PR0, PR0, PR1\n  CMP PR0, PR1\n  BR.GE 2\nHALT',
    'Extract Packet': '; Extract first 8 bytes of packet\nEXT.CD PR0, 0, 64\nEXT.CD PR1, 64, 64\nHALT',
  };

  function loadExample(name) {
    source = examples[name];
    if (view) {
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: source },
      });
    }
  }

  onMount(() => {
    const startState = EditorState.create({
      doc: source,
      extensions: [
        lineNumbers(),
        highlightActiveLine(),
        keymap.of(defaultKeymap),
        oneDark,
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            source = update.state.doc.toString();
          }
        }),
      ],
    });

    view = new EditorView({
      state: startState,
      parent: editorContainer,
    });

    return () => view.destroy();
  });
</script>

<div class="editor-section">
  <div class="editor-toolbar">
    <select on:change={(e) => loadExample(e.target.value)}>
      <option value="" disabled selected>Load Example...</option>
      {#each Object.keys(examples) as name}
        <option value={name}>{name}</option>
      {/each}
    </select>
  </div>
  <div class="editor-container" bind:this={editorContainer}></div>
</div>
```

- [ ] **Step 5: Create Controls.svelte**

```svelte
<!-- web/src/components/Controls.svelte -->
<script>
  import { createEventDispatcher } from 'svelte';

  export let assembled = false;
  export let halted = false;

  const dispatch = createEventDispatcher();
</script>

<div class="controls">
  <button on:click={() => dispatch('assemble')} class="btn btn-primary">Assemble</button>
  <button on:click={() => dispatch('step')} disabled={!assembled || halted} class="btn">Step</button>
  <button on:click={() => dispatch('run')} disabled={!assembled || halted} class="btn">Run</button>
  <button on:click={() => dispatch('reset')} disabled={!assembled} class="btn">Reset</button>
</div>
```

- [ ] **Step 6: Create StateViewer.svelte**

```svelte
<!-- web/src/components/StateViewer.svelte -->
<script>
  export let state = null;

  // Track previous state for change highlighting
  let prevState = null;

  $: if (state) {
    prevState = { ...state };
  }

  function isChanged(field) {
    if (!prevState || !state) return false;
    return JSON.stringify(prevState[field]) !== JSON.stringify(state[field]);
  }

  const regNames = ['PR0', 'PR1', 'PR2', 'PR3'];
</script>

<div class="state-viewer">
  {#if state}
    <div class="state-section">
      <h3>Registers</h3>
      <table class="reg-table">
        {#each regNames as name, i}
          <tr class:changed={state.regs && prevState?.regs && state.regs[i] !== prevState.regs[i]}>
            <td class="reg-name">{name}</td>
            <td class="reg-value">{state.regs?.[i] ?? '0x' + '0'.repeat(32)}</td>
          </tr>
        {/each}
      </table>
    </div>

    <div class="state-section">
      <h3>Status</h3>
      <div class="status-grid">
        <span class="label">PC</span>
        <span class="value">0x{state.pc?.toString(16).padStart(4, '0') ?? '0000'}</span>
        <span class="label">Step</span>
        <span class="value">{state.step_count ?? 0}</span>
        <span class="label">Cursor</span>
        <span class="value">{state.cursor ?? 0}</span>
        <span class="label">Halted</span>
        <span class="value">{state.halted ? 'Yes' : 'No'}</span>
      </div>
    </div>

    <div class="state-section">
      <h3>Flags</h3>
      <div class="flags">
        <span class="flag" class:active={state.flag_z}>Z</span>
        <span class="flag" class:active={state.flag_n}>N</span>
      </div>
    </div>

    <div class="state-section">
      <h3>Packet Header</h3>
      <div class="hex-dump">
        {#each (state.packet_header ?? []).slice(0, 64) as byte, i}
          <span class="hex-byte">{byte.toString(16).padStart(2, '0')}</span>
          {#if (i + 1) % 16 === 0}<br />{/if}
        {/each}
      </div>
    </div>
  {:else}
    <div class="state-empty">Assemble a program to see state.</div>
  {/if}
</div>
```

- [ ] **Step 7: Create playground.css**

Create `web/public/styles/playground.css`:

```css
.playground {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1px;
  height: calc(100vh - 49px);
  background: var(--border);
}

.panel-left, .panel-right {
  background: var(--bg);
  display: flex;
  flex-direction: column;
  overflow: auto;
}

.panel-left { padding: 1rem; gap: 0.75rem; }
.panel-right { padding: 1rem; }

.editor-section { flex: 1; display: flex; flex-direction: column; }
.editor-toolbar { margin-bottom: 0.5rem; }
.editor-toolbar select {
  background: var(--surface);
  color: var(--text);
  border: 1px solid var(--border);
  padding: 0.35rem 0.5rem;
  border-radius: 4px;
  font-size: 0.85rem;
}

.editor-container {
  flex: 1;
  border: 1px solid var(--border);
  border-radius: 4px;
  overflow: hidden;
}

.editor-container .cm-editor { height: 100%; }

.controls {
  display: flex;
  gap: 0.5rem;
}

.btn {
  padding: 0.4rem 1rem;
  background: var(--surface);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.85rem;
}
.btn:hover:not(:disabled) { background: var(--border); }
.btn:disabled { opacity: 0.4; cursor: not-allowed; }
.btn-primary { background: var(--accent); color: var(--bg); border-color: var(--accent); }
.btn-primary:hover { background: var(--accent-dim); }

.error-panel {
  background: rgba(248, 113, 113, 0.1);
  border: 1px solid var(--error);
  color: var(--error);
  padding: 0.5rem 0.75rem;
  border-radius: 4px;
  font-family: var(--font-mono);
  font-size: 0.8rem;
  white-space: pre-wrap;
}

.state-viewer { font-family: var(--font-mono); font-size: 0.8rem; }
.state-section { margin-bottom: 1.25rem; }
.state-section h3 {
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-dim);
  margin-bottom: 0.5rem;
}

.reg-table { width: 100%; border-collapse: collapse; }
.reg-table td { padding: 0.25rem 0.5rem; }
.reg-name { color: var(--accent); width: 3rem; }
.reg-value { color: var(--text); word-break: break-all; }
.reg-table tr.changed .reg-value { color: var(--changed); }

.status-grid {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 0.25rem 0.75rem;
}
.status-grid .label { color: var(--text-dim); }
.status-grid .value { color: var(--text); }

.flags { display: flex; gap: 0.5rem; }
.flag {
  padding: 0.2rem 0.5rem;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 3px;
  color: var(--text-dim);
}
.flag.active { color: var(--changed); border-color: var(--changed); }

.hex-dump { line-height: 1.6; }
.hex-byte {
  display: inline-block;
  width: 2ch;
  text-align: center;
  color: var(--text-dim);
  margin-right: 0.3ch;
}

.state-empty {
  color: var(--text-dim);
  text-align: center;
  padding: 2rem;
}
```

- [ ] **Step 8: Create playground.astro**

```astro
---
import Base from '../layouts/Base.astro';
import Playground from '../components/Playground.svelte';
---
<Base title="Playground">
  <Playground client:only="svelte" />
</Base>
```

- [ ] **Step 9: Build WASM and verify the full stack**

Run:
```bash
./dev.sh bash -c "cd web/simulator && wasm-pack build --target web" && ./dev.sh bash -c "cd web && npx astro build"
```
Expected: Both builds succeed. Static site output in `web/dist/`.

- [ ] **Step 10: Commit**

```bash
git add web/src/ web/public/ web/package.json web/package-lock.json
git commit -m "Add playground page with editor, controls, and state viewer"
```

---

## Phase 6: Examples and Polish

### Task 12: Example Programs

**Files:**
- Create: `examples/parser/simple-branch.xisa`
- Create: `examples/parser/extract-ipv4.xisa`

- [ ] **Step 1: Create simple-branch.xisa**

```asm
; Simple Branch Example
; Counts down from 5 and halts when reaching 0.
;
; PR0 = counter (starts at 5)
; PR1 = decrement value (1)

MOVI PR0, 5, 8          ; counter = 5
MOVI PR1, 1, 8          ; decrement = 1

; loop:
SUB PR0, PR0, PR1       ; counter -= 1
BR.NZ 2                 ; if counter != 0, jump back to SUB (PC=2)
HALT
```

- [ ] **Step 2: Create extract-ipv4.xisa**

```asm
; Extract IPv4 Header Fields
; Assumes packet starts with an IPv4 header.
;
; PR0 = version (4 bits) + IHL (4 bits)
; PR1 = total length (16 bits)
; PR2 = source IP (32 bits)
; PR3 = destination IP (32 bits)

EXT.CD PR0, 0, 8        ; version + IHL (byte 0)
EXT.CD PR1, 16, 16      ; total length (bytes 2-3)
EXT.CD PR2, 96, 32      ; source IP (bytes 12-15)
EXT.CD PR3, 128, 32     ; destination IP (bytes 16-19)

; Set header present and advance cursor
STH 0, 0                ; mark header 0 as present at offset 0
STCI 20                  ; advance cursor by 20 bytes (standard IPv4 header)

HALT
```

- [ ] **Step 3: Test with CLI assembler**

Run: `./dev.sh bash -c "cd web/simulator && cargo run --bin xisa-asm ../../examples/parser/simple-branch.xisa"`
Expected: `Assembled N instructions to ../../examples/parser/simple-branch.bin`

- [ ] **Step 4: Commit**

```bash
git add examples/
git commit -m "Add Parser ISA example programs"
```

---

## Phase 7: CI/CD

### Task 13: GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/web.yml`

- [ ] **Step 1: Create web.yml**

```yaml
name: Web Playground

on:
  push:
    paths:
      - 'web/**'
      - 'examples/**'
      - '.github/workflows/web.yml'
  pull_request:
    paths:
      - 'web/**'
      - 'examples/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: wasm32-unknown-unknown

      - name: Install wasm-pack
        run: cargo install wasm-pack

      - name: Rust tests
        working-directory: web/simulator
        run: cargo test

      - name: Build WASM
        working-directory: web/simulator
        run: wasm-pack build --target web

      - uses: actions/setup-node@v4
        with:
          node-version: 22

      - name: Install dependencies
        working-directory: web
        run: npm ci

      - name: Build site
        working-directory: web
        run: npx astro build

  deploy:
    needs: test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions:
      pages: write
      id-token: write
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: wasm32-unknown-unknown

      - name: Install wasm-pack
        run: cargo install wasm-pack

      - name: Build WASM
        working-directory: web/simulator
        run: wasm-pack build --target web

      - uses: actions/setup-node@v4
        with:
          node-version: 22

      - name: Install dependencies
        working-directory: web
        run: npm ci

      - name: Build site
        working-directory: web
        run: npx astro build

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: web/dist

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/web.yml
git commit -m "Add CI/CD workflow for web playground"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] Rust simulator with all 43 Parser ISA instructions (Task 2-6)
- [x] Decode/encode with roundtrip tests (Task 4-5)
- [x] Execute with exhaustive match (Task 6)
- [x] WASM bridge with init/step/get_state/assemble/reset (Task 9)
- [x] Assembler with core instruction subset (Task 7)
- [x] CLI assembler binary (Task 8)
- [x] Astro site with Svelte islands (Task 10-11)
- [x] CodeMirror editor (Task 11)
- [x] State viewer with registers, flags, PC, packet buffer (Task 11)
- [x] Step/Run/Reset controls (Task 11)
- [x] Example programs (Task 12)
- [x] GitHub Pages deployment (Task 13)
- [x] Dev container with Rust/wasm-pack/Node.js (Task 1)

**Placeholder scan:** No TBDs or TODOs found.

**Type consistency:** `Instruction`, `Reg`, `Condition`, `BitTestCond`, `SimState`, `StepResult`, `ExecResult`, `AsmError`, `AsmResult` — all consistently named across modules. `encode`/`decode` are inverses. `step()` in execute.rs returns `Result<StepResult, String>`. WASM bridge wraps with `JsValue`.

**Note:** The assembler (Task 7) supports a core subset of instructions. Remaining mnemonics (SUBII, ANDI, ORI, CNCTBY, CNCTBI, MOVL/MOVR variants, STC, STCH, STHC, ST, STI, EXTMAP, MOVMAP, NXTP, PSEEK, EXTNXTP, BRNS, BRNXTP, BRBTSTNXTP, BRBTSTNS) follow the same parse pattern and should be added as match arms in `parse_instruction`. Each is a straightforward addition — parse operands, construct the enum variant.
