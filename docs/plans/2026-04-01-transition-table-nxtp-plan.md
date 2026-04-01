# Transition Table, NXTP, BRNS, BRNXTP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the parser transition table model and NXTP/BRNS/BRNXTP instructions for protocol-graph traversal.

**Architecture:** Create `model/parser/params.sail` for implementation parameters and `model/parser/transition.sail` for the transition table (parallel arrays matching HDR pattern). Add state registers for parser state and NXTP results. NXTP performs a synchronous lookup, BRNS/BRNXTP branch based on results.

**Tech Stack:** Sail, CMake/CTest

---

### Task 1: Create params file and add type aliases

**Files:**
- Create: `model/parser/params.sail`
- Modify: `model/prelude.sail` (add bits24 alias)
- Modify: `model/main.sail` (add $include for params)

- [ ] **Step 1: Add `bits24` type alias to `model/prelude.sail`**

Insert after the `bits16` line:

```sail
type bits4   = bits(4)
type bits8   = bits(8)
type bits16  = bits(16)
type bits24  = bits(24)
type bits128 = bits(128)
```

- [ ] **Step 2: Create `model/parser/params.sail`**

```sail

// Implementation-chosen parameters for the parser model.
// The XISA spec defines interfaces but not capacities — these are
// implementation-defined. See docs/modeling-decisions.md.

// Transition table: 64 entries.
// Each rule maps (state, protocol_key) -> (next_state_pc, next_state).
// The spec does not define table capacity or state-ID bit width.
//
// Parameters:
//   Table size:      64 entries (indexed 0-63)
//   State ID:        8 bits (bits8), range 0-255
//   Protocol key:    24 bits (bits24), max size per NXTP spec
//   PC entry point:  16 bits (bits16), matching ppc width
//
// Sail requires literal sizes in vector declarations, so these
// parameters are documented here and used as literals elsewhere.
// Update both this file and the declarations if changing sizes.
```

- [ ] **Step 3: Add `$include` for params in `model/main.sail`**

```sail
$include "prelude.sail"
$include "map/state.sail"
$include "parser/params.sail"
$include "parser/types.sail"
$include "parser/state.sail"
$include "parser/decode.sail"
$include "parser/insts.sail"
$include "parser/exec.sail"
```

- [ ] **Step 4: Type-check**

Run: `./dev.sh cmake --build build --target check`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add model/prelude.sail model/parser/params.sail model/main.sail
git commit -m "Add parser params file and bits24 type alias"
```

---

### Task 2: Create transition table model and state registers

**Files:**
- Create: `model/parser/transition.sail`
- Modify: `model/parser/state.sail` (add state registers and init)
- Modify: `model/main.sail` (add $include for transition)

- [ ] **Step 1: Create `model/parser/transition.sail`**

```sail

// Parser transition table: maps (state, protocol_key) to next-state entry points.
// See XISA spec section 3.5 and docs/specs/2026-04-01-transition-table-nxtp-design.md.
//
// Uses parallel arrays (matching HDR pattern) rather than structs.
// Size: 64 entries (see model/parser/params.sail).

register tt_valid     : vector(64, bool)
register tt_state     : vector(64, bits8)
register tt_key       : vector(64, bits24)
register tt_next_pc   : vector(64, bits16)
register tt_next_state : vector(64, bits8)

val init_tt_valid : unit -> vector(64, bool)
function init_tt_valid() = [
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
]

val init_tt_bits8 : unit -> vector(64, bits8)
function init_tt_bits8() = [
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
]

val init_tt_bits24 : unit -> vector(64, bits24)
function init_tt_bits24() = [
    0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
    0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
    0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
    0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
    0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
    0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
    0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
    0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000, 0x000000,
]

val init_tt_bits16 : unit -> vector(64, bits16)
function init_tt_bits16() = [
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
]

// Reset all transition table entries.
val transition_table_init : unit -> unit
function transition_table_init() = {
    tt_valid = init_tt_valid();
    tt_state = init_tt_bits8();
    tt_key = init_tt_bits24();
    tt_next_pc = init_tt_bits16();
    tt_next_state = init_tt_bits8()
}

// Write a transition rule at a given index (for test setup and configuration).
val write_transition_rule : (int, bits8, bits24, bits16, bits8) -> unit
function write_transition_rule(idx, state, key, next_pc, next_state) = {
    assert(0 <= idx & idx < 64, "transition table index out of bounds");
    tt_valid[idx] = true;
    tt_state[idx] = state;
    tt_key[idx] = key;
    tt_next_pc[idx] = next_pc;
    tt_next_state[idx] = next_state
}

// Look up (state, key) in the transition table.
// Returns true and sets nxtp_result_pc/nxtp_result_state if found.
// Returns false if no match.
val transition_lookup : (bits8, bits24) -> bool
function transition_lookup(state, key) = {
    var found : bool = false;
    var i : int = 0;
    while i < 64 do {
        if tt_valid[i] & tt_state[i] == state & tt_key[i] == key & not_bool(found) then {
            nxtp_result_pc = tt_next_pc[i];
            nxtp_result_state = tt_next_state[i];
            found = true
        };
        i = i + 1
    };
    found
}
```

- [ ] **Step 2: Add state registers to `model/parser/state.sail`**

Insert after the `register parser_drop : bool` line:

```sail
// Parser state ID for transition table lookups.
// Tracks which protocol/state the parser is currently in.
register parser_state : bits8

// NXTP result: stored by NXTP, consumed by BRNXTP.
register nxtp_result_pc : bits16
register nxtp_result_state : bits8
register nxtp_matched : bool
```

- [ ] **Step 3: Add init to `parser_init()` in `model/parser/state.sail`**

Insert before the `// Reset MAP registers` line:

```sail
    // Reset parser state and NXTP result
    parser_state = sail_zeros(8);
    nxtp_result_pc = sail_zeros(16);
    nxtp_result_state = sail_zeros(8);
    nxtp_matched = false;

    // Reset transition table
    transition_table_init();

    // Reset MAP registers
```

- [ ] **Step 4: Add `$include` for transition in `model/main.sail`**

Insert after the params include, before types:

```sail
$include "prelude.sail"
$include "map/state.sail"
$include "parser/params.sail"
$include "parser/types.sail"
$include "parser/transition.sail"
$include "parser/state.sail"
$include "parser/decode.sail"
$include "parser/insts.sail"
$include "parser/exec.sail"
```

Note: `transition.sail` must come after `types.sail` (for type aliases) but before `state.sail` (which calls `transition_table_init` in `parser_init`). However, `transition.sail` references `nxtp_result_pc` and `nxtp_result_state` which are declared in `state.sail`. This is a circular dependency.

**Resolution:** Move the NXTP result registers into `transition.sail` (they're transition-table state, not general parser state), and only call `transition_table_init()` from `parser_init()`. The include order becomes: transition.sail (defines registers + table) → state.sail (defines parser_init which calls transition_table_init).

Revised `transition.sail` — add at the top, before the table registers:

```sail
// NXTP result: stored by NXTP, consumed by BRNXTP.
register nxtp_result_pc : bits16
register nxtp_result_state : bits8
register nxtp_matched : bool
```

And remove them from the Step 2 addition to `state.sail`. Keep only `parser_state` in `state.sail`.

- [ ] **Step 5: Type-check**

Run: `./dev.sh cmake --build build --target check`
Expected: PASS

- [ ] **Step 6: Run existing tests for regressions**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build`
Expected: all 20 tests pass

- [ ] **Step 7: Commit**

```bash
git add model/parser/transition.sail model/parser/state.sail model/main.sail
git commit -m "Add transition table model and parser state registers"
```

---

### Task 3: Add union clauses for NXTP, BRNS, BRNXTP

**Files:**
- Modify: `model/parser/types.sail` (before `end pinstr`)

- [ ] **Step 1: Add union clauses**

Insert before `end pinstr`:

```sail
// NXTP: Calculate next-protocol entry address via transition table lookup.
// Fields: (src_reg, src_offset_bits, size_bits)
union clause pinstr = PNXTP : (pregidx, bits8, bits8)

// BRNS: Branch to next state indicated by a transition rule number.
// Fields: (condition, transition_rule_number)
union clause pinstr = PBRNS : (pcond, bits8)

// BRNXTP: Branch to next-protocol (NXTP result), with JumpMode for no-match.
// Fields: (condition, jump_mode, address_or_rule)
// jump_mode: 000=nop, 001=continue, 010=jump to address, 011=use rule
// address_or_rule: used by mode 010 (as PC address) or 011 (as rule number)
union clause pinstr = PBRNXTP : (pcond, bits8, bits16)
```

- [ ] **Step 2: Commit**

```bash
git add model/parser/types.sail
git commit -m "Add union clauses for NXTP, BRNS, BRNXTP instructions"
```

---

### Task 4: Add execute clauses for NXTP, BRNS, BRNXTP

**Files:**
- Modify: `model/parser/insts.sail` (before `end execute`)

- [ ] **Step 1: Add execute clauses**

Insert before `end execute`:

```sail
// NXTP: Extract protocol key from register, look up in transition table.
// Stores result in nxtp_result_pc/nxtp_result_state/nxtp_matched.
function clause execute(PNXTP(rs, src_offset_bits, size_bits)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let sz : nat = unsigned(size_bits);
    let extracted = extract_bits(src_val, soff, sz);
    // Protocol key is up to 24 bits — truncate to bits24.
    let key : bits24 = sail_mask(24, extracted);
    nxtp_matched = transition_lookup(parser_state, key);
    RETIRE_SUCCESS
}

// BRNS: Branch to the next-state PC from a specific transition rule.
// Updates parser_state and ppc if condition is met.
function clause execute(PBRNS(cc, rule_num)) = {
    if eval_pcond(cc) then {
        let idx : int = unsigned(rule_num);
        assert(0 <= idx & idx < 64, "BRNS transition rule index out of bounds");
        ppc = tt_next_pc[idx];
        parser_state = tt_next_state[idx]
    };
    RETIRE_SUCCESS
}

// BRNXTP: Branch to next-protocol entry point (from NXTP result).
// JumpMode controls behavior when NXTP had no match.
// jump_mode encoding: 000=nop, 001=continue, 010=jump to address, 011=use rule
function clause execute(PBRNXTP(cc, jump_mode, addr_or_rule)) = {
    if eval_pcond(cc) then {
        if nxtp_matched then {
            // Match: branch to NXTP result
            ppc = nxtp_result_pc;
            parser_state = nxtp_result_state
        } else {
            // No match: follow JumpMode
            let mode : int = unsigned(jump_mode);
            if mode == 0 then {
                // 000: No jump
                ()
            } else if mode == 1 then {
                // 001: Continue to next instruction
                ()
            } else if mode == 2 then {
                // 010: Jump to explicit address
                ppc = addr_or_rule
            } else if mode == 3 then {
                // 011: Transition to state from specified rule
                let idx : int = unsigned(addr_or_rule);
                assert(0 <= idx & idx < 64, "BRNXTP rule index out of bounds");
                ppc = tt_next_pc[idx];
                parser_state = tt_next_state[idx]
            } else {
                // 100 (trap) and others: not yet supported
                ()
            }
        }
    };
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Type-check**

Run: `./dev.sh cmake --build build --target check`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add model/parser/insts.sail
git commit -m "Add execute clauses for NXTP, BRNS, BRNXTP instructions"
```

---

### Task 5: Add tests and register with CTest

**Files:**
- Create: `test/parser/test_nxtp.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create `test/parser/test_nxtp.sail`**

```sail
// Tests for NXTP, BRNS, BRNXTP (transition table) instructions.

// NXTP: match found — state=0, key=0x0800, rule at index 0.
val test_nxtp_match : unit -> unit
function test_nxtp_match() = {
    parser_init();
    // Set up transition rule: state 0, key 0x0800 -> PC 100, next state 1
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    // Put key 0x0800 in R0[15:0]
    PR[0] = 0x00000000_00000000_00000000_00000800;
    // NXTP: extract 16 bits from R0 at offset 0
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_matched == true, "NXTP should find a match");
    assert(nxtp_result_pc == 0x0064, "NXTP result PC should be 100");
    assert(nxtp_result_state == 0x01, "NXTP result state should be 1")
}

// NXTP: no match — key not in table.
val test_nxtp_no_match : unit -> unit
function test_nxtp_no_match() = {
    parser_init();
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    PR[0] = 0x00000000_00000000_00000000_00009999;
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_matched == false, "NXTP should not find a match")
}

// NXTP: state-sensitive — same key, different states, different results.
val test_nxtp_state_sensitive : unit -> unit
function test_nxtp_state_sensitive() = {
    parser_init();
    // Rule 0: state 0, key 0x0800 -> PC 100, next state 1
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    // Rule 1: state 1, key 0x0800 -> PC 200, next state 2
    write_transition_rule(1, 0x01, 0x000800, 0x00C8, 0x02);
    PR[0] = 0x00000000_00000000_00000000_00000800;

    // Lookup in state 0
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_result_pc == 0x0064, "State 0 should match rule 0 (PC=100)");

    // Change to state 1 and look up again
    parser_state = 0x01;
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_result_pc == 0x00C8, "State 1 should match rule 1 (PC=200)")
}

// BRNS: branch taken — condition met, jump to rule's PC.
val test_brns_taken : unit -> unit
function test_brns_taken() = {
    parser_init();
    write_transition_rule(5, 0x00, 0x000800, 0x0064, 0x01);
    // Set Z flag so EQ condition is met
    pflag_z = true;
    let _ = execute(PBRNS(PCC_EQ, 0x05));
    assert(ppc == 0x0064, "BRNS should branch to rule 5's PC (100)");
    assert(parser_state == 0x01, "BRNS should update parser_state to 1")
}

// BRNS: branch not taken — condition not met, PC unchanged.
val test_brns_not_taken : unit -> unit
function test_brns_not_taken() = {
    parser_init();
    write_transition_rule(5, 0x00, 0x000800, 0x0064, 0x01);
    ppc = 0x0010;
    pflag_z = false;
    let _ = execute(PBRNS(PCC_EQ, 0x05));
    assert(ppc == 0x0010, "BRNS should not branch when condition not met");
    assert(parser_state == 0x00, "parser_state should remain 0")
}

// BRNXTP: matched — branch to NXTP result.
val test_brnxtp_matched : unit -> unit
function test_brnxtp_matched() = {
    parser_init();
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    PR[0] = 0x00000000_00000000_00000000_00000800;
    // NXTP to set up result
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    // BRNXTP with always-branch condition, JumpMode 000
    let _ = execute(PBRNXTP(PCC_AL, 0x00, 0x0000));
    assert(ppc == 0x0064, "BRNXTP should branch to NXTP result PC");
    assert(parser_state == 0x01, "BRNXTP should update parser_state")
}

// BRNXTP: no match, JumpMode 000 — no jump, continue.
val test_brnxtp_nomatch_mode0 : unit -> unit
function test_brnxtp_nomatch_mode0() = {
    parser_init();
    ppc = 0x0010;
    PR[0] = 0x00000000_00000000_00000000_00009999;
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_matched == false, "should not match");
    let _ = execute(PBRNXTP(PCC_AL, 0x00, 0x0000));
    assert(ppc == 0x0010, "JumpMode 000 should not change PC")
}

// BRNXTP: no match, JumpMode 010 — jump to explicit address.
val test_brnxtp_nomatch_mode2 : unit -> unit
function test_brnxtp_nomatch_mode2() = {
    parser_init();
    ppc = 0x0010;
    PR[0] = 0x00000000_00000000_00000000_00009999;
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_matched == false, "should not match");
    // JumpMode 010, address = 0x00FF
    let _ = execute(PBRNXTP(PCC_AL, 0x02, 0x00FF));
    assert(ppc == 0x00FF, "JumpMode 010 should jump to address 0xFF")
}

// Program: Ethernet -> IPv4 parse graph traversal.
// Packet: [dst(6), src(6), EtherType(2)] = 14 bytes.
// EtherType = 0x0800 (IPv4) at bytes 12-13.
// Program: EXT EtherType into R0, NXTP with key, BRNXTP to IPv4 handler.
val test_nxtp_program : unit -> unit
function test_nxtp_program() = {
    parser_init();
    // Set up packet: EtherType 0x0800 at bytes 12-13
    packet_hdr[12] = 0x08;
    packet_hdr[13] = 0x00;
    // Transition rule: state 0, key 0x0800 -> PC 50 (IPv4 handler), state 1
    write_transition_rule(0, 0x00, 0x000800, 0x0032, 0x01);

    parser_load_program(
        [|
            // EXT 16 bits from packet offset 96 (byte 12) into R0[15:0]
            PEXT(PR0, 0x00, 0x0060, 0x10, true),
            // NXTP: look up R0[15:0] as 16-bit key
            PNXTP(PR0, 0x00, 0x10),
            // BRNXTP: always branch, JumpMode 000
            PBRNXTP(PCC_AL, 0x00, 0x0000),
            PHALT(false),
        |],
    );

    let result = parser_run();

    // Program should have branched to PC 50 (IPv4 handler).
    // But PC 50 is a NOP, so it runs NOPs until hitting... actually,
    // the program will branch to PC 50 which has NOPs, run until 255, and never halt.
    // We need a HALT at PC 50.
    // Revised: write HALT at the target PC.
    parser_init();
    packet_hdr[12] = 0x08;
    packet_hdr[13] = 0x00;
    write_transition_rule(0, 0x00, 0x000800, 0x0032, 0x01);

    parser_load_program(
        [|
            PEXT(PR0, 0x00, 0x0060, 0x10, true),
            PNXTP(PR0, 0x00, 0x10),
            PBRNXTP(PCC_AL, 0x00, 0x0000),
        |],
    );
    // Write HALT at PC 50 (the IPv4 handler entry point)
    write_pimem(50, PHALT(false));

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt at IPv4 handler");
    assert(parser_state == 0x01, "parser_state should be 1 (IPv4)");
    assert(PR[0] == 0x00000000_00000000_00000000_00000800, "R0 should have EtherType 0x0800")
}

val main : unit -> unit
function main() = {
    test_nxtp_match();
    test_nxtp_no_match();
    test_nxtp_state_sensitive();
    test_brns_taken();
    test_brns_not_taken();
    test_brnxtp_matched();
    test_brnxtp_nomatch_mode0();
    test_brnxtp_nomatch_mode2();
    test_nxtp_program()
}
```

- [ ] **Step 2: Register test in `test/CMakeLists.txt`**

Add at the end:

```cmake
add_sail_test(test_nxtp test/parser/test_nxtp.sail)
```

- [ ] **Step 3: Build and run new test**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_nxtp -V`
Expected: PASS

- [ ] **Step 4: Run full test suite**

Run: `./dev.sh ctest --test-dir build`
Expected: all 21 tests pass

- [ ] **Step 5: Commit**

```bash
git add test/parser/test_nxtp.sail test/CMakeLists.txt
git commit -m "Add tests for NXTP, BRNS, BRNXTP instructions"
```

---

### Task 6: Update coverage and modeling decisions

**Files:**
- Modify: `docs/coverage.md`
- Modify: `docs/modeling-decisions.md`

- [ ] **Step 1: Update `docs/coverage.md`**

Change line 16 from:

```markdown
| 8 | NXTP | 3.12.1 | Not started | Requires transition table model |
```

to:

```markdown
| 8 | NXTP | 3.12.1 | Done | |
```

Change line 36 (BR line) from:

```markdown
| 28 | BR/BRBTST | 3.12.18 | Done | BRNS, BRNXTP, BRBTSTNXTP deferred (need transition table) |
```

to:

```markdown
| 28 | BR/BRBTST | 3.12.18 | Done | BRNS, BRNXTP added. BRBTSTNXTP, BRBTSTNSNXTP deferred. JumpMode 100 (trap) deferred |
```

- [ ] **Step 2: Add transition table parameters to `docs/modeling-decisions.md`**

Add a new section after "Register Models":

```markdown
## Transition Table

- **Table size is 64 entries.** The spec defines the transition table interface (section 3.5) but not its capacity. 64 entries is sufficient for typical parser programs. This is an implementation-chosen parameter documented in `model/parser/params.sail`.

- **State ID is 8 bits.** The spec does not define the bit width of parser state IDs. 8 bits (256 states) covers typical protocol graphs. Documented in `model/parser/params.sail`.

- **NXTP lookup is synchronous.** See "Timing and Async Operations" above.

- **JumpMode 100 (trap) not supported.** Requires trap address configuration which is not yet modeled.
```

- [ ] **Step 3: Update todo.md**

Change the BR variants deferred line from:

```markdown
- **BR variants deferred**: BRNS (branch to next state), BRNXTP (branch to next protocol), and BRBTSTNXTP require the transition table model, which is not yet implemented. Only BR<cc> and BRBTST<cc> are modeled.
```

to:

```markdown
- **BR compound variants deferred**: BRBTSTNXTP (bit-test + next protocol) and BRBTSTNSNXTP (bit-test + next state) require compound instruction support. BRNS and BRNXTP are now implemented.
```

- [ ] **Step 4: Commit**

```bash
git add docs/coverage.md docs/modeling-decisions.md docs/todo.md
git commit -m "Update coverage and docs for transition table and NXTP"
```
