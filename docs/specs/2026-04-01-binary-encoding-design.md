# Binary Instruction Encoding Design Spec

## Overview

Add binary encoding for all parser ISA instructions, following the sail-riscv pattern. Switch instruction memory from `pinstr` union values to 64-bit binary words decoded on every fetch via Sail's bidirectional `encdec` mapping.

This is an implementation-defined encoding (the XISA spec does not publish binary formats). If the vendor publishes encodings later, only the `encdec` mapping clauses need updating — the `execute` function is unchanged.

## Instruction Word Format

64-bit fixed-width instruction word:

```
[63:58] opcode (6 bits, 43 instructions → 0-42)
[57:0]  fields (up to 58 bits, zero-padded at LSB)
```

NOP encodes as all zeros: `0x0000000000000000`.

## Field Encoding Conventions

| Type | Bits | Encoding |
|------|------|----------|
| `pregidx` | 3 | 000=PR0, 001=PR1, 010=PR2, 011=PR3, 100=PRN |
| `pcond` | 3 | 000=EQ, 001=NEQ, 010=LT, 011=GT, 100=GE, 101=LE, 110=AL |
| `pbtcond` | 1 | 0=CLR, 1=SET |
| `bool` | 1 | 0=false, 1=true |
| `bits4` | 4 | direct |
| `bits8` | 8 | direct |
| `bits16` | 16 | direct |

Fields are packed MSB-first (left-to-right) after the opcode, matching the order they appear in the union clause. Unused LSB bits are zero.

## Opcode Table

Grouped by spec section. Opcode 0 = NOP so that zeroed memory is valid (NOP sled).

| Opcode | Instruction | Spec Section |
|--------|-------------|-------------|
| 0 | PNOP | 3.12.20 |
| 1 | PHALT | 3.12.19 |
| 2 | PNXTP | 3.12.1 |
| 3 | PPSEEK | 3.12.2 |
| 4 | PPSEEKNXTP | 3.12.2 |
| 5 | PEXT | 3.12.3 |
| 6 | PEXTNXTP | 3.12.3 |
| 7 | PEXTMAP | 3.12.4 |
| 8 | PMOVMAP | 3.12.5 |
| 9 | PCNCTBY | 3.12.6 |
| 10 | PCNCTBI | 3.12.6 |
| 11 | PSTH | 3.12.7 |
| 12 | PSTC | 3.12.8 |
| 13 | PSTCI | 3.12.8 |
| 14 | PSTCH | 3.12.9 |
| 15 | PSTHC | 3.12.9 |
| 16 | PST | 3.12.10 |
| 17 | PSTI | 3.12.10 |
| 18 | PMOV | 3.12.11 |
| 19 | PMOVI | 3.12.11 |
| 20 | PMOVL | 3.12.12 |
| 21 | PMOVLI | 3.12.12 |
| 22 | PMOVLII | 3.12.12 |
| 23 | PMOVR | 3.12.12 |
| 24 | PMOVRI | 3.12.12 |
| 25 | PMOVRII | 3.12.12 |
| 26 | PADD | 3.12.13 |
| 27 | PADDI | 3.12.13 |
| 28 | PSUB | 3.12.14 |
| 29 | PSUBI | 3.12.14 |
| 30 | PSUBII | 3.12.14 |
| 31 | PAND | 3.12.15 |
| 32 | PANDI | 3.12.15 |
| 33 | POR | 3.12.16 |
| 34 | PORI | 3.12.16 |
| 35 | PCMP | 3.12.17 |
| 36 | PCMPIBY | 3.12.17 |
| 37 | PCMPIBI | 3.12.17 |
| 38 | PBR | 3.12.18 |
| 39 | PBRBTST | 3.12.18 |
| 40 | PBRNS | 3.12.18 |
| 41 | PBRNXTP | 3.12.18 |
| 42 | PBRBTSTNXTP | 3.12.18 |
| 43 | PBRBTSTNS | 3.12.18 |

## Encoding Examples

**PNOP** (opcode 0, no fields):
```
000000 00000000000000000000000000000000000000000000000000000000000
```
= `0x0000000000000000`

**PEXT(PR0, 0x00, 0x0060, 0x10, true)** (opcode 5):
```
000101 000 00000000 0000000001100000 00010000 1 000000000000000000
opcode rd  dest_off src_off          size     cd padding
```

**PBR(PCC_AL, 0x0032)** (opcode 38):
```
100110 110 0000000000110010 000000000000000000000000000000000000000
opcode cc  target            padding
```

## Implementation Changes

### New: `model/parser/decode.sail`

Replace the placeholder with:
- Sub-mappings: `encdec_pregidx : pregidx <-> bits(3)`, `encdec_pcond : pcond <-> bits(3)`, `encdec_pbtcond : pbtcond <-> bits(1)`
- Scattered `mapping encdec : pinstr <-> bits(64)` with one clause per instruction
- Catch-all clause mapping unknown bit patterns to PNOP (or an ILLEGAL value)

### Modified: `model/parser/state.sail`

- Change `pimem` from `vector(256, pinstr)` to `vector(65536, bits(64))` — matches `ppc` width (bits16)
- Remove `init_pimem()` (256-line NOP list) — replace with zero-initialized vector
- Update `write_pimem` to accept `pinstr` (encode before storing)
- Update `parser_load_program` to encode each `pinstr` before storing
- Update bounds checks from 256 to 65536

### Modified: `model/parser/exec.sail`

- Fetch `bits(64)` from `pimem`, decode via `encdec` mapping to `pinstr`, then execute

### Tests

- Existing tests continue to work — `parser_load_program` accepts `pinstr` lists and encodes internally
- Add round-trip tests: for each instruction variant, verify `encdec(encdec(bits)) == bits`
- Add a program-level test using raw binary instructions

## Assumptions

- This is an implementation-defined encoding, documented in `docs/modeling-decisions.md`
- Opcode 0 = NOP ensures zeroed memory is safe
- Field packing order matches union clause field order (left-to-right → MSB-first)
- Unknown opcodes decode to NOP (safe default, no trap)
