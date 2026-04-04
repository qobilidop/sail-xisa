# Playground Refactor Design

## Goal

Separate the core Rust ISA library (assembler + simulator) from its WASM bindings so the core is usable as a standalone Rust library and CLI toolset, independent of the web playground.

## Motivation

Today all Rust code lives in `web/simulator/`, tightly coupled to `wasm-bindgen`. This means:

- The assembler and simulator can't be used outside the browser without pulling in WASM deps.
- Differential testing (Rust simulator vs. Sail C simulator) requires a standalone binary.
- The `xisa-asm` CLI binary needlessly depends on `wasm-bindgen`.

## Architecture

### Workspace

A Cargo workspace at the repo root ties the crates together:

```toml
[workspace]
members = ["playground", "web/wasm"]
```

This gives shared `Cargo.lock`, shared `target/`, and `cargo test --workspace`.

### Core crate: `playground/` (`xisa`)

Contains all ISA logic with no WASM dependencies:

```
playground/
  Cargo.toml            # name = "xisa", deps: serde, serde_json
  src/
    lib.rs              # pub mod declarations
    types.rs
    state.rs
    assembler.rs
    encode.rs
    decode.rs
    execute.rs
    bin/
      xisa-asm.rs       # assembler CLI (moved from web/simulator)
      xisa-sim.rs       # simulator CLI (new)
  examples/
    extract-ipv4.xisa   # moved from examples/parser/
    simple-branch.xisa  # moved from examples/parser/
```

Dependencies: `serde`, `serde_json` only. No `wasm-bindgen`.

#### `xisa-sim` binary

New CLI that loads a binary, runs to completion, and dumps final state as JSON:

```
xisa-sim <input.bin>
```

Reads the binary file, loads 64-bit big-endian words into instruction memory, runs the execute loop until halt/drop, prints `SimState` as JSON to stdout.

### WASM crate: `web/wasm/` (`xisa-wasm`)

Thin wrapper — only WASM bindings:

```
web/wasm/
  Cargo.toml            # name = "xisa-wasm", deps: xisa (path), wasm-bindgen, serde-wasm-bindgen
  src/
    lib.rs              # Simulator struct with #[wasm_bindgen] methods
```

The `Simulator` struct and `StateSnapshot` stay here. Methods delegate to the core `xisa` crate. This is the only crate that depends on `wasm-bindgen`.

## What Moves Where

| From | To |
|---|---|
| `web/simulator/src/types.rs` | `playground/src/types.rs` |
| `web/simulator/src/state.rs` | `playground/src/state.rs` |
| `web/simulator/src/assembler.rs` | `playground/src/assembler.rs` |
| `web/simulator/src/encode.rs` | `playground/src/encode.rs` |
| `web/simulator/src/decode.rs` | `playground/src/decode.rs` |
| `web/simulator/src/execute.rs` | `playground/src/execute.rs` |
| `web/simulator/src/bin/xisa-asm.rs` | `playground/src/bin/xisa-asm.rs` |
| `examples/parser/*.xisa` | `playground/examples/*.xisa` |
| `web/simulator/src/lib.rs` | `web/wasm/src/lib.rs` (rewritten as thin wrapper) |

## Build Integration Changes

- `wasm-pack build` path: `web/simulator` -> `web/wasm`
- CI scripts and dev container commands referencing `web/simulator` must update
- The Astro site's WASM import path may change depending on `wasm-pack` output dir config

## Testing

- All core logic tests move with their modules to `playground/` — run with `cargo test -p xisa`
- WASM-specific tests (`wasm-bindgen-test`) stay in `web/wasm/`
- `cargo test --workspace` runs everything
