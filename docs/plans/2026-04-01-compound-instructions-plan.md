# Compound Instructions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add EXTNXTP, BRBTSTNXTP, and BRBTSTNS compound parser instructions that combine existing operations.

**Architecture:** Each compound instruction reuses logic from existing execute clauses (EXT packet extraction, NXTP transition lookup, BRBTST bit testing, BRNS/BRNXTP branching). No new models or state needed.

**Tech Stack:** Sail, CMake/CTest

---

### Task 1: Add union clauses

**Files:**
- Modify: `model/parser/types.sail` (before `end pinstr`)

- [ ] **Step 1: Add union clauses**

Insert before `end pinstr`:

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

- [ ] **Step 2: Commit**

```bash
git add model/parser/types.sail
git commit -m "Add union clauses for EXTNXTP, BRBTSTNXTP, BRBTSTNS"
```

---

### Task 2: Add execute clauses

**Files:**
- Modify: `model/parser/insts.sail` (before `end execute`)

- [ ] **Step 1: Add execute clauses**

Insert before `end execute`:

```sail
// EXTNXTP: Extract data from packet into register, then NXTP lookup with extracted key.
// Combines EXT (at dest offset 0) + NXTP in one instruction. Size limited to 1-24 bits.
function clause execute(PEXTNXTP(rd, src_offset_bits, size_bits, clear_dest)) = {
    let soff = unsigned(src_offset_bits);
    let sz = unsigned(size_bits);
    let cursor_bit_offset = unsigned(pcursor) * 8;
    let packet_bit_offset = cursor_bit_offset + soff;

    // Packet extraction logic (same as EXT)
    let pbo_bv : bits(20) = get_slice_int(20, packet_bit_offset, 0);
    let start_byte = unsigned(sail_shiftright(pbo_bv, 3));
    let bit_in_byte = unsigned(pbo_bv & 0x00007);

    let sum_bv : bits(20) = get_slice_int(20, bit_in_byte + sz + 7, 0);
    let bytes_needed = unsigned(sail_shiftright(sum_bv, 3));

    var acc : bits128 = sail_zeros(128);
    var i : int = 0;
    while i < bytes_needed do {
        let byte_idx : int = start_byte + i;
        let byte_val : bits128 = sail_zero_extend(read_packet_byte(byte_idx), 128);
        acc = acc | sail_shiftleft(byte_val, 8 * (bytes_needed - 1 - i));
        i = i + 1
    };

    let shift_amount : int = bytes_needed * 8 - bit_in_byte - sz;
    let extracted : bits128 = sail_shiftright(acc, shift_amount) & sail_mask(128, sail_ones(sz));

    // Write to destination register at offset 0
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, 0, sz, extracted);
    write_preg(rd, result);

    // NXTP: use extracted value as transition key (up to 24 bits)
    let key : bits24 = sail_mask(24, extracted);
    nxtp_matched = transition_lookup(parser_state, key);
    RETIRE_SUCCESS
}

// BRBTSTNXTP: Test bit in register, branch to next protocol if condition met.
// Combines BRBTST condition check + BRNXTP branch logic.
function clause execute(PBRBTSTNXTP(btcc, rs, bit_offset, jump_mode, addr_or_rule)) = {
    let src_val = read_preg(rs);
    let boff : nat = unsigned(bit_offset);
    let bit_val = extract_bits(src_val, boff, 1);
    let bit_is_set = bit_val != sail_zeros(128);
    let take_branch : bool = match btcc {
        PBT_CLR => not_bool(bit_is_set),
        PBT_SET => bit_is_set,
    };
    if take_branch then {
        if nxtp_matched then {
            ppc = nxtp_result_pc;
            parser_state = nxtp_result_state
        } else {
            let mode : int = unsigned(jump_mode);
            if mode == 0 then {
                ()
            } else if mode == 1 then {
                ()
            } else if mode == 2 then {
                ppc = addr_or_rule
            } else if mode == 3 then {
                let idx : int = unsigned(addr_or_rule);
                ppc = read_tt_next_pc(idx);
                parser_state = read_tt_next_state(idx)
            } else {
                ()
            }
        }
    };
    RETIRE_SUCCESS
}

// BRBTSTNS: Test bit in register, branch to next state from transition rule if condition met.
// Combines BRBTST condition check + BRNS branch logic.
function clause execute(PBRBTSTNS(btcc, rs, bit_offset, rule_num)) = {
    let src_val = read_preg(rs);
    let boff : nat = unsigned(bit_offset);
    let bit_val = extract_bits(src_val, boff, 1);
    let bit_is_set = bit_val != sail_zeros(128);
    let take_branch : bool = match btcc {
        PBT_CLR => not_bool(bit_is_set),
        PBT_SET => bit_is_set,
    };
    if take_branch then {
        let idx : int = unsigned(rule_num);
        ppc = read_tt_next_pc(idx);
        parser_state = read_tt_next_state(idx)
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
git commit -m "Add execute clauses for EXTNXTP, BRBTSTNXTP, BRBTSTNS"
```

---

### Task 3: Add tests

**Files:**
- Create: `test/parser/test_compound.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create `test/parser/test_compound.sail`**

```sail
// Tests for compound instructions (EXTNXTP, BRBTSTNXTP, BRBTSTNS).

// EXTNXTP: extract EtherType 0x0800 from packet, lookup matches.
val test_extnxtp_match : unit -> unit
function test_extnxtp_match() = {
    parser_init();
    packet_hdr[0] = 0x08;
    packet_hdr[1] = 0x00;
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    // PEXTNXTP(dest_reg, source_offset_bits, size_bits, clear_dest)
    let _ = execute(PEXTNXTP(PR0, 0x0000, 0x10, true));
    assert(PR[0] == 0x00000000_00000000_00000000_00000800,
        "EXTNXTP should extract 0x0800 into R0[15:0]");
    assert(nxtp_matched == true, "EXTNXTP should find a match");
    assert(nxtp_result_pc == 0x0064, "EXTNXTP result PC should be 100")
}

// EXTNXTP with RN: lookup happens but dest register is null.
val test_extnxtp_rn : unit -> unit
function test_extnxtp_rn() = {
    parser_init();
    packet_hdr[0] = 0x08;
    packet_hdr[1] = 0x00;
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    let _ = execute(PEXTNXTP(PRN, 0x0000, 0x10, true));
    // RN always reads as zero
    assert(read_preg(PRN) == sail_zeros(128),
        "EXTNXTP with RN should not modify any register");
    assert(nxtp_matched == true, "EXTNXTP should still perform lookup")
}

// BRBTSTNXTP: bit set, condition SET, nxtp matched -> branch.
val test_brbtstnxtp_taken : unit -> unit
function test_brbtstnxtp_taken() = {
    parser_init();
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    PR[0] = 0x00000000_00000000_00000000_00000800;
    // Set up NXTP result
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_matched == true, "NXTP should match");
    // R1 with bit 0 set
    PR[1] = 0x00000000_00000000_00000000_00000001;
    // PBRBTSTNXTP(condition, src_reg, bit_offset, jump_mode, addr_or_rule)
    let _ = execute(PBRBTSTNXTP(PBT_SET, PR1, 0x00, 0x00, 0x0000));
    assert(ppc == 0x0064, "BRBTSTNXTP should branch to NXTP result PC");
    assert(parser_state == 0x01, "BRBTSTNXTP should update parser_state")
}

// BRBTSTNXTP: bit clear, condition SET -> no branch.
val test_brbtstnxtp_not_taken : unit -> unit
function test_brbtstnxtp_not_taken() = {
    parser_init();
    ppc = 0x0010;
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    PR[0] = 0x00000000_00000000_00000000_00000800;
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    // R1 with bit 0 clear
    PR[1] = 0x00000000_00000000_00000000_00000000;
    let _ = execute(PBRBTSTNXTP(PBT_SET, PR1, 0x00, 0x00, 0x0000));
    assert(ppc == 0x0010, "BRBTSTNXTP should not branch when bit is clear")
}

// BRBTSTNS: bit set, condition SET -> branch to rule's next state.
val test_brbtstns_taken : unit -> unit
function test_brbtstns_taken() = {
    parser_init();
    write_transition_rule(3, 0x00, 0x000800, 0x0050, 0x02);
    // R0 with bit 4 set
    PR[0] = 0x00000000_00000000_00000000_00000010;
    // PBRBTSTNS(condition, src_reg, bit_offset, rule_number)
    let _ = execute(PBRBTSTNS(PBT_SET, PR0, 0x04, 0x03));
    assert(ppc == 0x0050, "BRBTSTNS should branch to rule 3's PC");
    assert(parser_state == 0x02, "BRBTSTNS should update parser_state to 2")
}

// Program: EXTNXTP + BRNXTP for streamlined Ethernet -> IPv4.
// One fewer instruction than the NXTP program test (EXT + NXTP combined).
val test_extnxtp_program : unit -> unit
function test_extnxtp_program() = {
    parser_init();
    packet_hdr[12] = 0x08;
    packet_hdr[13] = 0x00;
    write_transition_rule(0, 0x00, 0x000800, 0x0032, 0x01);

    parser_load_program(
        [|
            // EXTNXTP: extract 16 bits from packet offset 96 (byte 12) + lookup
            PEXTNXTP(PR0, 0x0060, 0x10, true),
            // BRNXTP: branch to NXTP result
            PBRNXTP(PCC_AL, 0x00, 0x0000),
        |],
    );
    write_pimem(50, PHALT(false));

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt at IPv4 handler");
    assert(parser_state == 0x01, "parser_state should be 1 (IPv4)");
    assert(PR[0] == 0x00000000_00000000_00000000_00000800, "R0 should have EtherType")
}

val main : unit -> unit
function main() = {
    test_extnxtp_match();
    test_extnxtp_rn();
    test_brbtstnxtp_taken();
    test_brbtstnxtp_not_taken();
    test_brbtstns_taken();
    test_extnxtp_program()
}
```

- [ ] **Step 2: Register test in `test/CMakeLists.txt`**

Add at the end:

```cmake
add_sail_test(test_compound test/parser/test_compound.sail)
```

- [ ] **Step 3: Build and run**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_compound -V`
Expected: PASS

- [ ] **Step 4: Run full suite**

Run: `./dev.sh ctest --test-dir build`
Expected: all 22 tests pass

- [ ] **Step 5: Commit**

```bash
git add test/parser/test_compound.sail test/CMakeLists.txt
git commit -m "Add tests for EXTNXTP, BRBTSTNXTP, BRBTSTNS instructions"
```

---

### Task 4: Update coverage

**Files:**
- Modify: `docs/coverage.md`

- [ ] **Step 1: Update coverage**

Change line 15 from:

```markdown
| 7 | EXTNXTP | 3.12.3 | Not started | |
```

to:

```markdown
| 7 | EXTNXTP | 3.12.3 | Done | .CD supported. No .PR, .SCSM, .ECSM yet |
```

Change the BR line from:

```markdown
| 28 | BR/BRBTST/BRNS/BRNXTP | 3.12.18 | Done | BRBTSTNXTP, BRBTSTNSNXTP deferred. JumpMode 100 (trap) deferred |
```

to:

```markdown
| 28 | BR/BRBTST/BRNS/BRNXTP/BRBTSTNXTP/BRBTSTNS | 3.12.18 | Done | JumpMode 100 (trap) deferred |
```

- [ ] **Step 2: Commit**

```bash
git add docs/coverage.md
git commit -m "Update coverage for compound instructions"
```
