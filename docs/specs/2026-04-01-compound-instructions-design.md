# Compound Instructions Design Spec (EXTNXTP, BRBTSTNXTP, BRBTSTNS)

## Overview

Three compound parser instructions that combine existing operations into single instructions. No new models needed — these reuse EXT packet extraction, NXTP transition lookup, BRBTST bit testing, and BRNS/BRNXTP branching.

Reference: [XISA white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf), sections 3.12.3 (EXTNXTP), 3.12.18 (BRBTSTNXTP, BRBTSTNS).

## Instruction Semantics

### EXTNXTP (3.12.3)

**Syntax:** `EXTNXTP[.CD] Rd, SourceOffsetBits, SizeBits`

**Operation:** Extract from packet + NXTP lookup in one instruction.
1. Extract `SizeBits` (1-24) from packet at cursor-relative `SourceOffsetBits`, store in `DestReg[SizeBits-1:0]`
2. Use extracted value as NXTP key: `transition_lookup(parser_state, extracted[23:0])`

- DestReg can be RN (null register) if the extracted value isn't needed
- .CD: clear destination register before writing (same as EXT.CD)
- Size limited to 1-24 bits (NXTP key max)

### BRBTSTNXTP (3.12.18)

**Syntax:** `BRBTSTNXTP<cc> Rs, SrcOffsetBits, JumpMode [, Address | TransitionRule]`

**Operation:** Test bit + branch to next-protocol in one instruction.
1. Test bit at `SrcOffsetBits` in `Rs`
2. Evaluate bit-test condition (`<cc>`: CLR or SET)
3. If condition met: same as BRNXTP — branch to NXTP result if matched, follow JumpMode if not

### BRBTSTNS (3.12.18)

**Syntax:** `BRBTSTNS<cc> Rs, SrcOffsetBits, TransitionRule`

**Operation:** Test bit + branch to next state in one instruction.
1. Test bit at `SrcOffsetBits` in `Rs`
2. Evaluate bit-test condition (`<cc>`: CLR or SET)
3. If condition met: same as BRNS — branch to transition rule's next_state_pc

## Union Clauses

```sail
// EXTNXTP: Extract from packet + NXTP lookup.
// Fields: (dest_reg, source_offset_bits, size_bits, clear_dest)
union clause pinstr = PEXTNXTP : (pregidx, bits16, bits8, bool)

// BRBTSTNXTP: Bit test + branch to next protocol (NXTP result).
// Fields: (condition, src_reg, bit_offset, jump_mode, address_or_rule)
union clause pinstr = PBRBTSTNXTP : (pbtcond, pregidx, bits8, bits8, bits16)

// BRBTSTNS: Bit test + branch to next state (transition rule).
// Fields: (condition, src_reg, bit_offset, transition_rule_number)
union clause pinstr = PBRBTSTNS : (pbtcond, pregidx, bits8, bits8)
```

## Deferred

- .PR modifier on EXTNXTP (present bit)
- .SCSM/.ECSM on EXTNXTP (checksum accelerator)

## Tests (test/parser/test_compound.sail)

1. **EXTNXTP match**: packet has EtherType 0x0800, EXTNXTP extracts and looks up → nxtp_matched, R0 has value
2. **EXTNXTP with RN**: same but dest=RN → nxtp_matched but RN reads as zero
3. **BRBTSTNXTP taken**: bit is set, condition SET, nxtp matched → branch to result PC
4. **BRBTSTNXTP not taken**: bit is clear, condition SET → no branch
5. **BRBTSTNS taken**: bit is set, condition SET → branch to rule's next_state_pc
6. **Program**: EXTNXTP + BRNXTP for streamlined Ethernet→IPv4 (one fewer instruction than NXTP test)
