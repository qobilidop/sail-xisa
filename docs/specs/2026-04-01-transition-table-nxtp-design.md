# Transition Table, NXTP, BRNS, BRNXTP Design Spec

## Overview

The parser transition table is the core data structure driving protocol-graph traversal (XISA spec section 3.5). NXTP looks up a protocol key in the table to determine the next parser state. BRNS and BRNXTP branch to next-state entry points based on transition table results.

This is sub-project A of the transition table work. Sub-projects B (PSEEK) and C (EXTNXTP, compound BR variants) build on this foundation.

Reference: [XISA white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf), sections 3.5, 3.5.1, 3.12.1, 3.12.18.

## Implementation Parameters

The spec defines the transition table interface but not its capacity or state-ID bit width — these are implementation-defined. We choose concrete defaults and document them in `model/parser/params.sail`:

- **TRANSITION_TABLE_SIZE**: 64 entries
- **Parser state ID**: 8 bits (`bits8`)
- **Protocol key**: up to 24 bits (`bits(24)`)
- **PC entry point**: 16 bits (`bits16`, matching `ppc`)

These are noted in `docs/modeling-decisions.md` as implementation-chosen parameters.

## Transition Table Model

Located in `model/parser/transition.sail`.

### Table Structure

Each transition rule contains:
- `valid : bool` — whether this entry is active
- `state : bits8` — parser state to match
- `protocol_key : bits(24)` — protocol value to match
- `next_state_pc : bits16` — PC entry point for the next parser state
- `next_state : bits8` — the next parser state ID

The table is a fixed-size array:
- `register transition_table : vector(64, TransitionRule)`

### Lookup

`transition_lookup(state, key)` scans the table for the first valid entry matching `(state, key)`. Returns an option type: match found → `Some(rule)`, no match → `None`.

### Helper Functions

- `write_transition_rule(idx, rule)` — write a rule at a given index (for test setup)
- `transition_lookup(state, key)` — search for matching rule

## State Registers

Added to `model/parser/state.sail`:

- `register parser_state : bits8` — current parser state (initialized to 0)
- `register nxtp_result_pc : bits16` — PC from last NXTP lookup
- `register nxtp_result_state : bits8` — next state from last NXTP lookup
- `register nxtp_matched : bool` — whether last NXTP found a match

All initialized in `parser_init()`.

## Instruction Semantics

### NXTP (3.12.1)

**Syntax:** `NXTP SourceReg, SourceOffsetBits, SizeBits`

**Operation:** Extract protocol key from register, look up in transition table.

1. Extract `key = SourceReg[i-1:j]` where `j = SourceOffsetBits`, `i = SourceOffsetBits + SizeBits` (up to 24 bits)
2. Look up `(parser_state, key)` in transition table
3. If match: `nxtp_matched = true`, `nxtp_result_pc = rule.next_state_pc`, `nxtp_result_state = rule.next_state`
4. If no match: `nxtp_matched = false`

### BRNS (3.12.18)

**Syntax:** `BRNS<cc> TransitionRule`

**Operation:** Branch to the next-state PC indicated by a specific transition rule number, if condition is met.

1. Evaluate condition code `<cc>`
2. If condition met: `ppc = transition_table[rule].next_state_pc`, `parser_state = transition_table[rule].next_state`

### BRNXTP (3.12.18)

**Syntax:** `BRNXTP<cc> JumpMode [, Address | TransitionRule]`

**Operation:** Branch to the next-protocol entry point (from NXTP result), if condition is met. JumpMode controls behavior on no-match.

1. Evaluate condition code `<cc>`
2. If condition not met: do nothing
3. If condition met AND `nxtp_matched`:
   - `ppc = nxtp_result_pc`
   - `parser_state = nxtp_result_state`
4. If condition met AND NOT `nxtp_matched`: follow JumpMode:
   - `000`: No jump (continue to next instruction)
   - `001`: Continue to next instruction
   - `010`: Jump to explicit address (address operand)
   - `011`: Transition to state from specified rule number
   - `100`: Trap (jump to pre-configured trap address)

### JumpMode Support

For the initial implementation:
- **Mode 000 and 001**: Supported (no jump / continue — same effect in our model)
- **Mode 010**: Supported (jump to explicit address)
- **Mode 011**: Supported (use transition rule)
- **Mode 100**: Deferred (requires trap address configuration)

## Union Clauses

```sail
// NXTP: Calculate next-protocol entry address via transition table lookup.
// Fields: (src_reg, src_offset_bits, size_bits)
union clause pinstr = PNXTP : (pregidx, bits8, bits8)

// BRNS: Branch to next state indicated by a transition rule number.
// Fields: (condition, transition_rule_number)
union clause pinstr = PBRNS : (pcond, bits8)

// BRNXTP: Branch to next-protocol (NXTP result), with JumpMode for no-match.
// Fields: (condition, jump_mode, address_or_rule)
// address_or_rule is used by JumpMode 010 (as address) or 011 (as rule number).
union clause pinstr = PBRNXTP : (pcond, bits8, bits16)
```

## Deferred

- JumpMode 100 (trap) — requires trap address configuration
- EXTNXTP — EXT + NXTP compound (sub-project C)
- BRBTSTNXTP, BRBTSTNSNXTP — bit-test + NXTP branch compounds (sub-project C)
- PSEEK, PSEEKNXTP — protocol seek accelerator (sub-project B)

## Tests (test/parser/test_nxtp.sail)

### Setup helper
- `setup_transition_rule(idx, state, key, next_pc, next_state)` — populate a table entry

### NXTP tests
1. **NXTP match**: state=0, rule `(0, 0x0800) → PC 100, state 1`, NXTP with key=0x0800 → nxtp_matched=true, nxtp_result_pc=100
2. **NXTP no match**: NXTP with key=0x9999 → nxtp_matched=false
3. **NXTP state-sensitive**: rules for state 0 and state 1 with same key but different PCs → correct result based on current state

### BRNS tests
4. **BRNS taken**: condition met → ppc = rule's next_state_pc
5. **BRNS not taken**: condition not met → ppc unchanged

### BRNXTP tests
6. **BRNXTP matched**: NXTP matched, condition met → branch to nxtp_result_pc
7. **BRNXTP no match, JumpMode 000**: not matched → continue (no branch)
8. **BRNXTP no match, JumpMode 010**: not matched → jump to explicit address

### Program-level test
9. **Ethernet → IPv4 parse graph**: Load packet with EtherType=0x0800. EXT EtherType into R0, NXTP with key from R0, BRNXTP to IPv4 handler. Verify parser_state updated and PC jumped to the IPv4 entry point.
