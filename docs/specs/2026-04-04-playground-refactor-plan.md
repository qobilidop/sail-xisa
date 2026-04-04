# Playground Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate the core Rust ISA library from WASM bindings into a Cargo workspace, adding a simulator CLI binary.

**Architecture:** Two crates in a workspace — `playground/` (core library `xisa` with assembler + simulator + CLI binaries) and `web/wasm/` (thin WASM wrapper `xisa-wasm`). The core crate has zero WASM dependencies.

**Tech Stack:** Rust, Cargo workspaces, wasm-pack, serde/serde_json

---

### Task 1: Create the core crate skeleton

**Files:**
- Create: `playground/Cargo.toml`
- Create: `playground/src/lib.rs`

- [ ] **Step 1: Create `playground/Cargo.toml`**

```toml
[package]
name = "xisa"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "xisa-asm"
path = "src/bin/xisa-asm.rs"

[[bin]]
name = "xisa-sim"
path = "src/bin/xisa-sim.rs"

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

- [ ] **Step 2: Create `playground/src/lib.rs`**

```rust
pub mod types;

pub mod state;

pub mod decode;

pub mod encode;

pub mod execute;

pub mod assembler;
```

- [ ] **Step 3: Verify the skeleton compiles (will fail — modules don't exist yet)**

Run: `cd playground && cargo check 2>&1 | head -5`
Expected: errors about missing module files (this confirms the skeleton is wired up)

- [ ] **Step 4: Commit**

```bash
git add playground/Cargo.toml playground/src/lib.rs
git commit -m "Add playground/ core crate skeleton"
```

---

### Task 2: Move core modules to playground

**Files:**
- Move: `web/simulator/src/types.rs` → `playground/src/types.rs`
- Move: `web/simulator/src/state.rs` → `playground/src/state.rs`
- Move: `web/simulator/src/decode.rs` → `playground/src/decode.rs`
- Move: `web/simulator/src/encode.rs` → `playground/src/encode.rs`
- Move: `web/simulator/src/execute.rs` → `playground/src/execute.rs`
- Move: `web/simulator/src/assembler.rs` → `playground/src/assembler.rs`
- Move: `web/simulator/src/bin/xisa-asm.rs` → `playground/src/bin/xisa-asm.rs`

- [ ] **Step 1: Copy all core source files**

```bash
cp web/simulator/src/types.rs playground/src/types.rs
cp web/simulator/src/state.rs playground/src/state.rs
cp web/simulator/src/decode.rs playground/src/decode.rs
cp web/simulator/src/encode.rs playground/src/encode.rs
cp web/simulator/src/execute.rs playground/src/execute.rs
cp web/simulator/src/assembler.rs playground/src/assembler.rs
mkdir -p playground/src/bin
cp web/simulator/src/bin/xisa-asm.rs playground/src/bin/xisa-asm.rs
```

- [ ] **Step 2: Fix the crate reference in `xisa-asm.rs`**

Change `use xisa_simulator::assembler::assemble;` to `use xisa::assembler::assemble;` in `playground/src/bin/xisa-asm.rs`.

- [ ] **Step 3: Remove `use serde::Serialize` from `types.rs` if serde derive is already handled via `Cargo.toml` feature — verify it compiles**

Run: `cd playground && cargo check`
Expected: compiles successfully (the `Serialize` derive in `types.rs` should work via the `serde` dep with `derive` feature)

- [ ] **Step 4: Run tests**

Run: `cd playground && cargo test`
Expected: all tests pass (same tests as before, now running in the core crate)

- [ ] **Step 5: Commit**

```bash
git add playground/src/
git commit -m "Move core ISA modules to playground/ crate"
```

---

### Task 3: Move examples

**Files:**
- Move: `examples/parser/extract-ipv4.xisa` → `playground/examples/extract-ipv4.xisa`
- Move: `examples/parser/simple-branch.xisa` → `playground/examples/simple-branch.xisa`
- Remove: `examples/` directory

- [ ] **Step 1: Copy examples and remove old directory**

```bash
mkdir -p playground/examples
cp examples/parser/extract-ipv4.xisa playground/examples/extract-ipv4.xisa
cp examples/parser/simple-branch.xisa playground/examples/simple-branch.xisa
rm -rf examples/
```

- [ ] **Step 2: Commit**

```bash
git add playground/examples/ && git rm -r examples/
git commit -m "Move example programs to playground/examples/"
```

---

### Task 4: Add `xisa-sim` binary

**Files:**
- Create: `playground/src/bin/xisa-sim.rs`

- [ ] **Step 1: Write the simulator binary**

```rust
use std::env;
use std::fs;
use std::process;

use xisa::execute;
use xisa::state::SimState;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: xisa-sim <input.bin>");
        process::exit(1);
    }

    let input_path = &args[1];
    let bytes = match fs::read(input_path) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("Error reading {}: {}", input_path, e);
            process::exit(1);
        }
    };

    let mut state = SimState::new();

    // Load 64-bit big-endian words into instruction memory.
    for chunk in bytes.chunks_exact(8) {
        let word = u64::from_be_bytes([
            chunk[0], chunk[1], chunk[2], chunk[3],
            chunk[4], chunk[5], chunk[6], chunk[7],
        ]);
        state.instruction_mem.push(word);
    }

    // Run until halt or drop.
    loop {
        match execute::step(&mut state) {
            Ok(result) => {
                if result.halted || result.dropped {
                    break;
                }
            }
            Err(e) => {
                eprintln!("Execution error: {}", e);
                process::exit(1);
            }
        }
    }

    // Dump final state as JSON.
    println!("{}", serde_json::to_string_pretty(&state).unwrap());
}
```

- [ ] **Step 2: Add `Serialize` derive to `SimState`**

In `playground/src/state.rs`, add `use serde::Serialize;` at the top (if not already present) and add `#[derive(Debug, Clone, Serialize)]` to `SimState`.

For the fixed-size arrays larger than 32 elements (like `[bool; 64]`, `[u8; 64]`, etc.), serde doesn't auto-derive for arrays > 32 by default. Use `serde_json`'s support via serde's `#[serde(with = ...)]` or convert to `Vec` in a custom serializer. The simplest approach: add a helper module in `state.rs`:

```rust
mod array_ser {
    use serde::ser::{Serialize, Serializer, SerializeSeq};

    pub fn serialize<S, T, const N: usize>(arr: &[T; N], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
        T: Serialize,
    {
        let mut seq = serializer.serialize_seq(Some(N))?;
        for item in arr {
            seq.serialize_element(item)?;
        }
        seq.end()
    }
}
```

Then annotate each large array field:

```rust
#[serde(with = "array_ser")]
pub tt_valid: [bool; 64],
#[serde(with = "array_ser")]
pub tt_state: [u8; 64],
// ... etc for all [T; 64] and [T; 32] fields
```

- [ ] **Step 3: Verify it compiles**

Run: `cd playground && cargo check`
Expected: compiles successfully

- [ ] **Step 4: Test the binary with an example program**

```bash
cd playground
cargo run --bin xisa-asm -- examples/simple-branch.xisa /tmp/test.bin
cargo run --bin xisa-sim -- /tmp/test.bin
```

Expected: JSON output of final simulator state

- [ ] **Step 5: Commit**

```bash
git add playground/src/bin/xisa-sim.rs playground/src/state.rs
git commit -m "Add xisa-sim CLI binary for standalone simulation"
```

---

### Task 5: Rewrite WASM crate as thin wrapper

**Files:**
- Create: `web/wasm/Cargo.toml`
- Create: `web/wasm/src/lib.rs`
- Remove: `web/simulator/src/` (all `.rs` files)
- Remove: `web/simulator/Cargo.toml`, `web/simulator/Cargo.lock`

- [ ] **Step 1: Create `web/wasm/Cargo.toml`**

```toml
[package]
name = "xisa-wasm"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "rlib"]

[dependencies]
xisa = { path = "../../playground" }
wasm-bindgen = "0.2"
serde = { version = "1", features = ["derive"] }
serde-wasm-bindgen = "0.6"

[dev-dependencies]
wasm-bindgen-test = "0.3"

[profile.release]
opt-level = "s"
lto = true
```

- [ ] **Step 2: Create `web/wasm/src/lib.rs`**

```rust
use wasm_bindgen::prelude::*;
use serde::Serialize;
use xisa::state::SimState;

#[wasm_bindgen]
pub struct Simulator {
    state: SimState,
}

#[derive(Serialize)]
struct StateSnapshot {
    pc: u16,
    regs: [String; 4],
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
    #[wasm_bindgen(constructor)]
    pub fn new() -> Simulator {
        Simulator {
            state: SimState::new(),
        }
    }

    pub fn load_program(&mut self, bytes: &[u8]) {
        self.state.instruction_mem.clear();
        let chunks = bytes.chunks_exact(8);
        for chunk in chunks {
            let word = u64::from_be_bytes([
                chunk[0], chunk[1], chunk[2], chunk[3],
                chunk[4], chunk[5], chunk[6], chunk[7],
            ]);
            self.state.instruction_mem.push(word);
        }
        self.state.reset_execution();
    }

    pub fn load_packet(&mut self, packet: &[u8]) {
        let len = packet.len().min(256);
        self.state.packet_header[..len].copy_from_slice(&packet[..len]);
        for b in &mut self.state.packet_header[len..] {
            *b = 0;
        }
    }

    pub fn step(&mut self) -> Result<JsValue, JsValue> {
        xisa::execute::step(&mut self.state)
            .map_err(|e| JsValue::from_str(&e))
            .and_then(|r| {
                serde_wasm_bindgen::to_value(&r)
                    .map_err(|e| JsValue::from_str(&e.to_string()))
            })
    }

    pub fn get_state(&self) -> Result<JsValue, JsValue> {
        let regs = [
            format!("0x{:032x}", self.state.regs[0]),
            format!("0x{:032x}", self.state.regs[1]),
            format!("0x{:032x}", self.state.regs[2]),
            format!("0x{:032x}", self.state.regs[3]),
        ];
        let snapshot = StateSnapshot {
            pc: self.state.pc,
            regs,
            flag_z: self.state.flag_z,
            flag_n: self.state.flag_n,
            cursor: self.state.cursor,
            halted: self.state.halted,
            dropped: self.state.dropped,
            step_count: self.state.step_count,
            packet_header: self.state.packet_header[..256].to_vec(),
            struct0: format!("0x{:032x}", self.state.struct0),
            hdr_present: self.state.hdr_present.to_vec(),
            hdr_offset: self.state.hdr_offset.to_vec(),
        };
        serde_wasm_bindgen::to_value(&snapshot)
            .map_err(|e| JsValue::from_str(&e.to_string()))
    }

    pub fn reset(&mut self) {
        self.state.reset_execution();
    }

    pub fn assemble(&self, source: &str) -> Result<Vec<u8>, JsValue> {
        xisa::assembler::assemble(source)
            .map(|result| {
                let mut bytes = Vec::with_capacity(result.words.len() * 8);
                for word in result.words {
                    bytes.extend_from_slice(&word.to_be_bytes());
                }
                bytes
            })
            .map_err(|errors| {
                let msg = errors
                    .iter()
                    .map(|e| e.to_string())
                    .collect::<Vec<_>>()
                    .join("\n");
                JsValue::from_str(&msg)
            })
    }

    pub fn assemble_and_load(&mut self, source: &str) -> Result<JsValue, JsValue> {
        let result = xisa::assembler::assemble(source).map_err(|errors| {
            let msg = errors
                .iter()
                .map(|e| e.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            JsValue::from_str(&msg)
        })?;

        self.state.instruction_mem = result.words;
        self.state.reset_execution();

        serde_wasm_bindgen::to_value(&result.line_map)
            .map_err(|e| JsValue::from_str(&e.to_string()))
    }
}
```

- [ ] **Step 3: Remove old `web/simulator/` source files**

```bash
rm -rf web/simulator/src web/simulator/Cargo.toml web/simulator/Cargo.lock
```

Keep `web/simulator/pkg/` for now — it will be replaced by the new wasm-pack output in Task 7.

- [ ] **Step 4: Commit**

```bash
git add web/wasm/ && git rm -r web/simulator/src web/simulator/Cargo.toml web/simulator/Cargo.lock
git commit -m "Replace web/simulator/ with thin web/wasm/ wrapper crate"
```

---

### Task 6: Set up Cargo workspace

**Files:**
- Create: `Cargo.toml` (workspace root)

- [ ] **Step 1: Create workspace `Cargo.toml` at repo root**

```toml
[workspace]
members = ["playground", "web/wasm"]
resolver = "2"
```

- [ ] **Step 2: Run workspace build**

Run: `cargo test --workspace`
Expected: all tests pass (core crate tests run, WASM crate compiles)

Note: `cargo test` on the WASM crate won't run wasm-bindgen-test without wasm-pack, but it should compile. If there are compilation errors from the WASM crate in non-WASM target, that's expected since `wasm-bindgen` types are WASM-only. We can exclude the WASM crate from default workspace tests:

Run: `cargo test -p xisa`
Expected: all core tests pass

- [ ] **Step 3: Commit**

```bash
git add Cargo.toml
git commit -m "Add Cargo workspace linking playground/ and web/wasm/"
```

---

### Task 7: Update build scripts and CI

**Files:**
- Modify: `.github/workflows/web.yml`
- Modify: `web/src/lib/wasm.ts`

- [ ] **Step 1: Update CI workflow**

In `.github/workflows/web.yml`, update the paths trigger and build commands:

Add `playground/**` to the `paths` trigger lists.

Change the test job `runCmd`:

```yaml
runCmd: |
  bash scripts/generate-sail-doc.sh
  cargo test -p xisa
  cd web/wasm && wasm-pack build --target web && cd ../..
  cd web && npm ci && npx astro build
```

Change the deploy job `runCmd`:

```yaml
runCmd: |
  bash scripts/generate-sail-doc.sh
  cd web/wasm && wasm-pack build --target web && cd ../..
  cd web && npm ci && npx astro build
```

- [ ] **Step 2: Update WASM import path in `web/src/lib/wasm.ts`**

Change:
```typescript
import init, { Simulator } from '../../simulator/pkg/xisa_simulator.js';
```

To:
```typescript
import init, { Simulator } from '../../wasm/pkg/xisa_wasm.js';
```

Note: the package name changes from `xisa_simulator` to `xisa_wasm` (derived from the crate name `xisa-wasm`).

- [ ] **Step 3: Remove old `web/simulator/pkg/` and `web/simulator/target/`**

```bash
rm -rf web/simulator/
```

- [ ] **Step 4: Build WASM and verify the web site builds**

Run (inside dev container): `./dev.sh bash -c "cd web/wasm && wasm-pack build --target web && cd ../.. && cd web && npm ci && npx astro build"`

Expected: site builds successfully

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/web.yml web/src/lib/wasm.ts && git rm -rf web/simulator/
git commit -m "Update build scripts and imports for playground refactor"
```

---

### Task 8: Update Astro Vite config for new WASM path

**Files:**
- Modify: `web/astro.config.mjs` (if needed)

- [ ] **Step 1: Check if `fs.allow` needs updating**

The current config has `fs: { allow: ['..'] }` which allows access to parent directory. Since `web/wasm/pkg/` is still under `web/`, this should work without changes. Verify by running the dev server.

Run (inside dev container): `./dev.sh bash -c "cd web/wasm && wasm-pack build --target web && cd ../.. && cd web && npm ci && npx astro dev --host 0.0.0.0 &" && sleep 5 && curl -s http://localhost:4322/sail-xisa/ | head -20`

If the page loads, no changes needed. If there's a WASM import error, update `astro.config.mjs` to widen the `fs.allow` path.

- [ ] **Step 2: Commit (if changes needed)**

```bash
git add web/astro.config.mjs
git commit -m "Update Astro config for new WASM path"
```

---

### Task 9: Final verification

- [ ] **Step 1: Run all core tests**

Run: `cargo test -p xisa`
Expected: all tests pass

- [ ] **Step 2: Build WASM and web site**

Run (inside dev container): `./dev.sh bash -c "cd web/wasm && wasm-pack build --target web && cd ../.. && cd web && npm ci && npx astro build"`
Expected: builds successfully

- [ ] **Step 3: Test CLI binaries**

```bash
cargo run -p xisa --bin xisa-asm -- playground/examples/simple-branch.xisa /tmp/test.bin
cargo run -p xisa --bin xisa-sim -- /tmp/test.bin
```

Expected: assembler produces binary, simulator runs and dumps JSON state

- [ ] **Step 4: Verify workspace**

Run: `cargo test --workspace` or `cargo test -p xisa`
Expected: all tests pass

- [ ] **Step 5: Final commit (if any cleanup needed)**

```bash
git add -A
git commit -m "Playground refactor complete"
```
