# Tech Debt and Known Issues

## Current

- **HALT simplifications**: The HALT instruction does not model the `.RP` (reparse) modifier, the optional MAP-PC entry point, or the optional PARSER-PC jump address. These require modeling the MAP thread handoff and reparse flow.

- **EXT simplifications**: The EXT instruction does not model the `.PR` (present bit), `.SCSM` (start checksum), or `.ECSM` (end checksum) modifiers. These require the checksum accelerator and HDR.PRESENT models.

- **EXT uses 20-bit intermediate bitvectors**: The packet bit offset arithmetic in the EXT instruction uses `bits(20)` intermediates via `get_slice_int`. This is safe given the spec's parameter ranges (max offset ~2551 bits), but the constraint is not enforced by Sail's type system. If the spec's ranges change, this should be revisited.

- **Sail idiom opportunities**: `extract_bits` and `insert_bits` in `state.sail` are custom helpers using shifts and masks. Sail's standard library may have built-in equivalents (`vector_subrange`, `vector_update_subrange`) that would be more idiomatic. Investigate and refactor if so.

## Resolved

- **BR compound variants**: BRNS, BRNXTP, BRBTSTNXTP, and BRBTSTNS are now implemented. All BR variants in the spec are covered except JumpMode 100 (trap).

- **Instruction encoding**: 64-bit binary encoding implemented with `encdec` mapping in `decode.sail`. Instruction memory expanded to 65536 slots.

- **Instruction memory size**: Expanded from 256 to 65536 slots (matching bits16 PC width).

- **.CD modifier complete**: The .CD (clear destination) modifier is now supported on all applicable instructions: MOV, MOVI, EXT, EXTNXTP, ADD, ADDI, SUB, SUBI, SUBII, AND, ANDI, OR, ORI, CNCTBY, CNCTBI, MOVL, MOVLI, MOVLII, MOVR, MOVRI, MOVRII.
