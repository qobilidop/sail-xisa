# Fetch-Decode-Execute Loop Design Spec

## Overview

Add an instruction memory, fetch-decode-execute loop, and program-level tests to make the Parser ISA model executable. Instructions are stored as `pinstr` values (no binary encoding yet).

## Instruction Memory

- `register pimem : vector(1024, pinstr)` — array of 1024 instruction slots.
- Fetch reads `pimem[ppc]` directly — no binary decoding.
- **Future binary encoding:** When XISA binary encodings become available, replace `pimem` with a byte-level instruction memory and add a `mapping clause encdec` decode step between fetch and execute. The `execute` function is unchanged — it always takes `pinstr`. This is a localized change.

## Loop Semantics

`parser_step() -> ExecutionResult`:
1. Fetch instruction at `ppc`
2. Advance `ppc += 1` (so branches overwrite the incremented PC)
3. Execute the fetched instruction
4. Return the result

`parser_run() -> ExecutionResult`:
- Call `parser_step()` in a loop
- Stop on `RETIRE_HALT` or `RETIRE_DROP`, returning that result
- Safety limit: 10000 steps to prevent infinite loops. Returns `RETIRE_HALT` if exceeded.

## PC Advancement

PC is advanced **before** execute. This means:
- Non-branch instructions: PC naturally points to the next instruction.
- Branch instructions (PBR, PBRBTST): overwrite `ppc` with the target address. The pre-increment is discarded.
- This matches typical pipelined ISA behavior.

## Helpers

- `parser_load_program(instrs : list(pinstr))` — loads a list of instructions into `pimem` starting at address 0. Fills the rest with `PNOP()`. Resets `ppc` to 0.

## Code Changes

| File | Change |
|------|--------|
| `model/parser/state.sail` | Add `pimem` register, `parser_load_program` helper, initialize `pimem` in `parser_init` |
| `model/parser/exec.sail` (new) | `parser_step`, `parser_run` functions |
| `model/main.sail` | Include `exec.sail` |
| `test/parser/test_program.sail` (new) | Program-level tests using `parser_run` |
| `test/CMakeLists.txt` | Register `test_program` |
| `docs/todo.md` | Update: loop exists, binary encoding still deferred |

## Test Programs

Tests in `test_program.sail` will load small programs and run them via `parser_run()`:
- Simple: MOVI + HALT (load a value then halt)
- Arithmetic: MOVI + MOVI + ADD + HALT (compute and halt)
- Branch: MOVI + CMP + BR + HALT at different addresses (conditional control flow)
- Loop: a small counting loop using SUB + CMP + BR back
