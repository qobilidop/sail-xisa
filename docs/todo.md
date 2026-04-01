# Tech Debt and Known Issues

## Current

- **Instruction encoding not modeled**: `model/parser/decode.sail` is a placeholder. The XISA white paper does not publish full binary encoding formats, so we test by constructing instruction union values directly. If encodings become available, add `mapping clause encdec` for each instruction.

- **.CD modifier not modeled for most instructions**: The .CD (clear destination) optional modifier is not yet supported for MOV, MOVI, ADD, SUB, AND, OR, or CNCT instructions. It should clear the destination register before writing. Currently only EXT supports .CD.

- **HALT simplifications**: The HALT instruction does not model the `.RP` (reparse) modifier, the optional MAP-PC entry point, or the optional PARSER-PC jump address. These require modeling the MAP thread handoff and reparse flow.

- **EXT simplifications**: The EXT instruction does not model the `.PR` (present bit), `.SCSM` (start checksum), or `.ECSM` (end checksum) modifiers. These require the checksum accelerator and HDR.PRESENT models.

- **EXT uses 20-bit intermediate bitvectors**: The packet bit offset arithmetic in the EXT instruction uses `bits(20)` intermediates via `get_slice_int`. This is safe given the spec's parameter ranges (max offset ~2551 bits), but the constraint is not enforced by Sail's type system. If the spec's ranges change, this should be revisited.

- **BR variants deferred**: BRNS (branch to next state), BRNXTP (branch to next protocol), and BRBTSTNXTP require the transition table model, which is not yet implemented. Only BR<cc> and BRBTST<cc> are modeled.

- **Instruction memory uses pinstr array, not binary encoding**: The fetch-decode-execute loop uses a `vector(256, pinstr)` for instruction memory. Instructions are stored as union values, not binary-encoded bytes. When XISA binary encodings become available, replace with byte-level memory and add `mapping clause encdec` for each instruction. The `execute` function is unchanged — only the fetch/decode path changes.

- **Instruction memory limited to 256 slots**: Sail requires a literal default value for vector registers of union types. 256 is sufficient for parser programs but could be increased by generating a larger literal or switching to binary encoding.

- **Sail idiom opportunities**: `extract_bits` and `insert_bits` in `state.sail` are custom helpers using shifts and masks. Sail's standard library may have built-in equivalents (`vector_subrange`, `vector_update_subrange`) that would be more idiomatic. Investigate and refactor if so.

## Resolved

(None yet)
