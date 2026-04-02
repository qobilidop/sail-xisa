# Web Playground Design

A browser-based interactive playground for stepping through XISA programs
instruction by instruction, inspecting all internal state at each step.

## Goals

1. Public-facing educational tool to showcase XISA.
2. Step-by-step execution with full state visibility (registers, flags, PC,
   packet header buffer).
3. Assembly editor with example programs.
4. Static site deployment (GitHub Pages), no server required.
5. Parser ISA first; MAP ISA added later.

## Architecture

Three layers:

```
┌─────────────────────────────────────┐
│           Web UI (Svelte)           │
│  Astro + CodeMirror 6 + plain CSS   │
├─────────────────────────────────────┤
│        WASM Bridge (wasm-bindgen)    │
│  init, step, get_state, assemble    │
├─────────────────────────────────────┤
│      Simulator Core (Rust → WASM)   │
│  Instruction enum, decode, execute  │
│  Assembler (text → binary)          │
└─────────────────────────────────────┘
```

### Why these choices

- **Rust for the simulator**: Rust's `enum` + `match` mirrors Sail's union
  types. The compiler enforces exhaustive handling — adding a new instruction
  without handling it is a compile error. This is the closest thing to Sail's
  scattered functions and directly supports the goal of obviously-correct code.
- **Rust for the assembler**: The assembler shares types with the simulator
  (same `Instruction` enum, `encode` is the inverse of `decode`). Putting it in
  Rust means one implementation used everywhere — in the browser via WASM and
  locally via a CLI binary. Avoids maintaining two assemblers.
- **TypeScript was considered** for the simulator but lacks exhaustive match
  checking on discriminated unions. Missing an instruction case is a runtime
  error, not a compile error.
- **Sail C backend → WASM was considered** (the sail-riscv-wasm approach) but
  the cross-compilation complexity (Emscripten, GMP, Sail runtime) isn't
  justified for an ISA this size. The Rust simulator is a conformance
  implementation validated against the Sail model's test cases.
- **Astro**: The site includes both documentation pages and the interactive
  playground. Astro ships zero JS for doc pages and hydrates only the playground
  islands. Vite-only was considered but doesn't handle multi-page content
  (docs + playground) as cleanly.
- **Svelte islands**: The playground is three interactive panels — lightweight
  enough that Svelte (or even vanilla JS) suffices. React/Preact are heavier
  than needed.
- **CodeMirror 6**: Right-sized editor with excellent custom language support
  (Lezer grammars). Monaco is 10-20x larger and designed for full IDE
  experiences.
- **Plain CSS**: For a public project, clean HTML without utility class clutter
  is more readable for contributors.

## Simulator Core (Rust)

A library crate modeling the Parser ISA.

### Types

```rust
enum Instruction {
    Ext { dest: Reg, offset: u16, width: u8, cd: bool },
    Mov { dest: Reg, src: Reg, cd: bool },
    Add { dest: Reg, src1: Reg, src2: Reg, cd: bool },
    Br { cond: Condition, target: u16 },
    Halt,
    // ... all 20 Parser instruction groups
}

enum Reg { PR0, PR1, PR2, PR3, PRN }
enum Condition { Always, Z, NZ, N, NN, C, NC }
```

### State

```rust
struct SimState {
    pc: u16,
    regs: [u128; 5],
    flags: Flags,              // Z, N, C, V
    packet_header: [u8; 256],
    instruction_mem: Vec<u64>,
    hdr_present: [bool; 32],
    hdr_offset: [u16; 32],
    halted: bool,
    step_count: u64,
}
```

### Core functions

- `decode(bits: u64) → Result<Instruction, DecodeError>` — binary to
  instruction.
- `execute(state: &mut SimState, inst: &Instruction)` — one instruction's
  semantics. Exhaustive `match` on `Instruction`.
- `step(state: &mut SimState) → StepResult` — fetch + decode + execute.

### Validation

Sail model test cases are ported as Rust unit tests to confirm conformance
between the two implementations.

## Assembler (Rust)

Parses assembly text into binary instructions.

### Syntax

```asm
; Comments with semicolons
EXT      PR0, 0, 64         ; extract 64 bits at offset 0
EXT.CD   PR1, 8, 32         ; with clear-destination modifier
ADD      PR0, PR1, PR2
MOV.CD   PR3, PR0
CMP      PR0, PR1
BR.Z     loop               ; branch if zero flag set
HALT

loop:                        ; labels for branch targets
  NOP
```

### Components

- **Lexer** — tokenize into labels, mnemonics, modifiers, registers,
  immediates, comments.
- **Parser** — validate syntax, resolve labels to PC offsets, produce
  instruction objects.
- **Encoder** — `Instruction` → 64-bit binary, matching the Sail model's
  encoding scheme.
- **Error reporting** — line numbers and descriptive messages.

### CLI

A binary target (`xisa-asm`) for local use:

```
cargo run --bin xisa-asm examples/parser/extract-ipv4.xisa
```

## WASM Bridge

```rust
#[wasm_bindgen]
pub struct Simulator { ... }

#[wasm_bindgen]
impl Simulator {
    pub fn new() -> Simulator;
    pub fn load_program(&mut self, instructions: &[u8]);
    pub fn load_packet(&mut self, packet: &[u8]);
    pub fn step(&mut self) -> JsValue;      // StepResult as JSON
    pub fn get_state(&self) -> JsValue;     // full state snapshot
    pub fn reset(&mut self);
    pub fn assemble(&self, source: &str) -> Result<Vec<u8>, JsValue>;
}
```

- `step()` returns the decoded instruction, what changed (register writes, flag
  updates), and whether the simulator halted.
- `get_state()` returns PC, registers, flags, packet buffer, halted status,
  step count.
- Serialized via `serde` + `serde-wasm-bindgen`.

## Web UI

Astro site with Svelte interactive islands at `/playground`.

### Layout

```
┌──────────────────────────────────────────────────┐
│  Nav: Home | Docs | Playground                   │
├──────────────────────┬───────────────────────────┤
│                      │  Registers                │
│  Assembly Editor     │  ┌─────────┬───────────┐  │
│  (CodeMirror)        │  │ PR0     │ 0x000...  │  │
│                      │  │ PR1     │ 0x000...  │  │
│                      │  │ PR2     │ 0x000...  │  │
│                      │  │ PR3     │ 0x000...  │  │
│                      │  └─────────┴───────────┘  │
│                      │                           │
│  [Examples ▼]        │  Flags  Z:0 N:0 C:0 V:0  │
│                      │  PC: 0x0000  Step: 0      │
│  [Assemble] [Step]   │                           │
│  [Run] [Reset]       │  Current Instruction      │
│                      │  Packet Header Buffer     │
├──────────────────────┴───────────────────────────┤
│  Errors / assembler output                       │
└──────────────────────────────────────────────────┘
```

### Interactions

- **Examples dropdown** — loads `.xisa` example into editor.
- **Assemble** — calls Rust assembler via WASM, shows errors inline and in
  bottom panel.
- **Step** — one instruction, highlights current line in editor, highlights
  changed values in state panel.
- **Run** — steps until halt (with max-step safety limit).
- **Reset** — clears state, keeps assembled program.

### CodeMirror integration

- Custom Lezer grammar for XISA syntax highlighting.
- Inline error markers from assembler.
- Autocomplete for mnemonics and register names.

## Example Programs

```
examples/
└── parser/
    ├── extract-ipv4.xisa
    ├── protocol-walk.xisa
    └── simple-branch.xisa
```

Loaded in the playground via a dropdown. Also usable locally with the CLI
assembler.

## Repository Structure

```
sail-xisa/
├── model/                  # Sail spec (existing)
├── test/                   # Sail tests (existing)
├── examples/
│   └── parser/             # .xisa example programs
├── web/
│   ├── simulator/          # Rust crate
│   │   ├── Cargo.toml
│   │   ├── src/
│   │   │   ├── lib.rs      # WASM API
│   │   │   ├── types.rs
│   │   │   ├── decode.rs
│   │   │   ├── encode.rs
│   │   │   ├── execute.rs
│   │   │   ├── state.rs
│   │   │   ├── assembler.rs
│   │   │   └── bin/
│   │   │       └── xisa-asm.rs
│   │   └── tests/
│   ├── src/                # Astro site
│   │   ├── layouts/
│   │   ├── pages/
│   │   │   ├── index.astro
│   │   │   ├── playground.astro
│   │   │   └── docs/
│   │   ├── components/     # Svelte islands
│   │   └── content/
│   │       └── docs/       # markdown documentation
│   ├── astro.config.mjs
│   └── package.json
└── docs/                   # design specs (existing)
```

## Build Pipeline

### Local development

1. `wasm-pack build web/simulator --target web` — build WASM module.
2. `cd web && npm run dev` — Astro dev server.

### CI (GitHub Actions)

1. Existing: Sail type-check + tests.
2. New: `cargo test` in `web/simulator/` (conformance tests).
3. New: `wasm-pack build` + `astro build` → deploy to GitHub Pages.

### Dev container

Rust, wasm-pack, and Node.js added to the existing devcontainer alongside
Sail/OCaml.

## Scope

**In scope (initial):** Parser ISA simulator, assembler, playground UI, example
programs, GitHub Pages deployment.

**Later:** MAP ISA support, documentation pages, instruction explorer (decode
individual instructions interactively).
