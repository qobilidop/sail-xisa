# Property-Based Testing with Proptest

## Goal

Add property-based tests using proptest to verify that the Rust encode, decode, and assembler implementations are internally consistent across all parser ISA instruction variants.

## Motivation

The parser ISA has 28+ instruction variants with complex binary encodings. Hand-written tests cover specific cases but can miss edge cases in field widths, boundary values, or rarely-used instruction variants. Property-based testing generates hundreds of random valid instructions and checks invariants automatically, with shrinking to isolate minimal failing cases.

This tests internal consistency of our Rust code (encode vs. decode, assembler vs. encode). It does **not** verify correctness against the Sail specification — that's the job of differential testing (a separate future project).

## Test Suites

### Suite A: Encode/decode roundtrip

**Property:** For any valid `Instruction`, `decode(encode(instr)) == instr`.

**Strategy:** Generate random `Instruction` values with field values constrained to their valid bit widths:
- `Reg` — uniform over `PR0..PR3` (exclude `PRN` for destination registers where it doesn't roundtrip meaningfully, include it for source registers)
- `Condition` — uniform over all 7 variants
- `BitTestCond` — uniform over `Clear`/`Set`
- Offset/size fields — constrained to their encoded bit widths (e.g., 4-bit field → 0..15)
- Immediate fields — constrained to their encoded bit widths (e.g., 16-bit → 0..65535)
- Boolean fields (`cd`, `drop`, `halt`) — uniform true/false

### Suite B: Assemble/decode round-trip

**Property:** For a representative subset of instructions, formatting them as assembly source text, assembling, then decoding the output word yields the original `Instruction`.

**Approach:** For each instruction variant, generate random valid operands, format as a single-line assembly string (e.g., `"MOVI PR0[0], 42, 16"`), run through `assembler::assemble()`, decode the resulting word with `decode()`, and compare to the expected `Instruction`.

**Scope:** Cover the instruction variants that the assembler currently supports. Not all `Instruction` variants may have assembler support yet — the test should only cover those that do. If an instruction isn't supported by the assembler, it's tested only in Suite A.

**Note on defaults:** The assembler applies default values for some fields (e.g., `MOV` always uses `size: 128`, `EXT` always uses `doff: 0`). The strategy must generate values matching these defaults for the comparison to succeed.

## File Structure

- `playground/tests/proptest_encode_decode.rs` — Suite A
- `playground/tests/proptest_assemble.rs` — Suite B
- `playground/tests/common/mod.rs` — shared `Instruction` generation strategy (used by both suites)

## Dependencies

Add to `playground/Cargo.toml`:

```toml
[dev-dependencies]
proptest = "1"
```

## What We're NOT Doing

- Execution-level property tests (e.g., "NOP doesn't change registers") — future work
- MAP ISA instructions — parser ISA only, matching current scope
- Differential testing against Sail C simulator — separate project
- `Arbitrary` trait impl — we'll write explicit strategies instead, which gives us fine-grained control over field constraints
