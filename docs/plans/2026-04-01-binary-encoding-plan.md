# Binary Instruction Encoding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 64-bit binary encoding for all parser instructions, switch instruction memory from pinstr to bits(64), and decode on fetch (sail-riscv pattern).

**Architecture:** Add bidirectional `encdec` mapping in `decode.sail` with sub-mappings for register/condition enums. Switch `pimem` from `vector(256, pinstr)` to `vector(65536, bits(64))`. `parser_load_program` encodes `pinstr` values before storing, so existing tests keep working. The fetch loop decodes `bits(64)` back to `pinstr` before executing.

**Tech Stack:** Sail (scattered mapping), CMake/CTest

---

### Task 1: Add sub-mappings for enums

**Files:**
- Modify: `model/parser/decode.sail`

- [ ] **Step 1: Replace placeholder with sub-mappings**

Replace the entire contents of `model/parser/decode.sail` with:

```sail

// Parser instruction encoding/decoding.
// 64-bit fixed-width instruction word. See docs/specs/2026-04-01-binary-encoding-design.md.

// Type alias for instruction words.
type bits64 = bits(64)
type bits6  = bits(6)
type bits3  = bits(3)
type bits1  = bits(1)
type bits58 = bits(58)

// Sub-mapping: parser register index <-> 3 bits.
mapping encdec_pregidx : pregidx <-> bits3 = {
    PR0 <-> 0b000,
    PR1 <-> 0b001,
    PR2 <-> 0b010,
    PR3 <-> 0b011,
    PRN <-> 0b100,
}

// Sub-mapping: branch condition code <-> 3 bits.
mapping encdec_pcond : pcond <-> bits3 = {
    PCC_EQ  <-> 0b000,
    PCC_NEQ <-> 0b001,
    PCC_LT  <-> 0b010,
    PCC_GT  <-> 0b011,
    PCC_GE  <-> 0b100,
    PCC_LE  <-> 0b101,
    PCC_AL  <-> 0b110,
}

// Sub-mapping: bit-test condition <-> 1 bit.
mapping encdec_pbtcond : pbtcond <-> bits1 = {
    PBT_CLR <-> 0b0,
    PBT_SET <-> 0b1,
}

// Sub-mapping: bool <-> 1 bit.
mapping encdec_bool : bool <-> bits1 = {
    false <-> 0b0,
    true  <-> 0b1,
}

// Main instruction encoding: pinstr <-> bits(64).
// 6-bit opcode at [63:58], fields packed MSB-first, zero-padded at LSB.
val encdec : pinstr <-> bits64
scattered mapping encdec
```

- [ ] **Step 2: Type-check**

Run: `./dev.sh cmake --build build --target check`
Expected: PASS (scattered mapping declared but no clauses yet — should be ok, or may need at least one clause. If it fails, add the PNOP clause from Task 2 here.)

- [ ] **Step 3: Commit**

```bash
git add model/parser/decode.sail
git commit -m "Add sub-mappings for register, condition, and bool encoding"
```

---

### Task 2: Add encdec mapping clauses for all 43 instructions

**Files:**
- Modify: `model/parser/decode.sail` (append after scattered mapping declaration)

This is the largest task. Each instruction gets one `mapping clause encdec`. Fields are packed after the 6-bit opcode, zero-padded to 64 bits.

- [ ] **Step 1: Add all mapping clauses**

Append to `model/parser/decode.sail`:

```sail
// Opcode 0: NOP (no fields)
mapping clause encdec = PNOP()
    <-> 0b000000 @ 0x00000000000000 : bits(58)

// Opcode 1: HALT (1 bit: drop flag)
mapping clause encdec = PHALT(drop)
    <-> 0b000001 @ encdec_bool(drop) @ 0b0 : bits(57)

// Opcode 2: NXTP (3+8+8 = 19 bits)
mapping clause encdec = PNXTP(rs, soff, sz)
    <-> 0b000010 @ encdec_pregidx(rs) @ soff @ sz @ 0x000000000 : bits(39)

// Opcode 3: PSEEK (3+8+3+8+8+8 = 38 bits)
mapping clause encdec = PPSEEK(rd, doff, rs, soff, sz, cid)
    <-> 0b000011 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs) @ soff @ sz @ cid @ 0x00000 : bits(20)

// Opcode 4: PSEEKNXTP (3+8+3+8+8+8 = 38 bits)
mapping clause encdec = PPSEEKNXTP(rd, doff, rs, soff, sz, cid)
    <-> 0b000100 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs) @ soff @ sz @ cid @ 0x00000 : bits(20)

// Opcode 5: EXT (3+8+16+8+1 = 36 bits)
mapping clause encdec = PEXT(rd, doff, soff, sz, cd)
    <-> 0b000101 @ encdec_pregidx(rd) @ doff @ soff @ sz @ encdec_bool(cd) @ 0b0 : bits(21)

// Opcode 6: EXTNXTP (3+16+8+1 = 28 bits)
mapping clause encdec = PEXTNXTP(rd, soff, sz, cd)
    <-> 0b000110 @ encdec_pregidx(rd) @ soff @ sz @ encdec_bool(cd) @ 0b0 : bits(29)

// Opcode 7: EXTMAP (4+8+16+8 = 36 bits)
mapping clause encdec = PEXTMAP(midx, doff, poff, sz)
    <-> 0b000111 @ midx @ doff @ poff @ sz @ 0x000000 : bits(22)

// Opcode 8: MOVMAP (4+8+3+8+8 = 31 bits)
mapping clause encdec = PMOVMAP(midx, doff, rs, soff, sz)
    <-> 0b001000 @ midx @ doff @ encdec_pregidx(rs) @ soff @ sz @ 0x000000 : bits(27)

// Opcode 9: CNCTBY (3+8+3+8+8+3+8+8 = 49 bits)
mapping clause encdec = PCNCTBY(rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz)
    <-> 0b001001 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ s1sz @ encdec_pregidx(rs2) @ s2off @ s2sz @ 0b000000000 : bits(9)

// Opcode 10: CNCTBI (3+8+3+8+8+3+8+8 = 49 bits)
mapping clause encdec = PCNCTBI(rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz)
    <-> 0b001010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ s1sz @ encdec_pregidx(rs2) @ s2off @ s2sz @ 0b000000000 : bits(9)

// Opcode 11: STH (8+8+1 = 17 bits)
mapping clause encdec = PSTH(pid, oid, halt)
    <-> 0b001011 @ pid @ oid @ encdec_bool(halt) @ 0x0000000000 : bits(41)

// Opcode 12: STC (3+8+8+8+8 = 35 bits)
mapping clause encdec = PSTC(rs, soff, ssz, shift, incr)
    <-> 0b001100 @ encdec_pregidx(rs) @ soff @ ssz @ shift @ incr @ 0b00000000000000000000000 : bits(23)

// Opcode 13: STCI (16 bits)
mapping clause encdec = PSTCI(incr)
    <-> 0b001101 @ incr @ 0x0000000000 : bits(42)

// Opcode 14: STCH (16+8+8+1 = 33 bits)
mapping clause encdec = PSTCH(incr, pid, oid, halt)
    <-> 0b001110 @ incr @ pid @ oid @ encdec_bool(halt) @ 0x000000 : bits(25)

// Opcode 15: STHC (16+8+8 = 32 bits)
mapping clause encdec = PSTHC(incr, pid, oid)
    <-> 0b001111 @ incr @ pid @ oid @ 0x000000 : bits(26)

// Opcode 16: ST (3+8+8+8+1 = 28 bits)
mapping clause encdec = PST(rs, soff, doff, sz, halt)
    <-> 0b010000 @ encdec_pregidx(rs) @ soff @ doff @ sz @ encdec_bool(halt) @ 0b0 : bits(29)

// Opcode 17: STI (16+8+8 = 32 bits)
mapping clause encdec = PSTI(imm, doff, sz)
    <-> 0b010001 @ imm @ doff @ sz @ 0x000000 : bits(26)

// Opcode 18: MOV (3+8+3+8+8 = 30 bits)
mapping clause encdec = PMOV(rd, doff, rs, soff, sz)
    <-> 0b010010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs) @ soff @ sz @ 0x0000000 : bits(28)

// Opcode 19: MOVI (3+8+16+8 = 35 bits)
mapping clause encdec = PMOVI(rd, doff, imm, sz)
    <-> 0b010011 @ encdec_pregidx(rd) @ doff @ imm @ sz @ 0b00000000000000000000000 : bits(23)

// Opcode 20: MOVL (3+3+8+8+3+8+8+1 = 42 bits)
mapping clause encdec = PMOVL(rd, rs1, o1, sz1, rs2, o2, sz2, cd)
    <-> 0b010100 @ encdec_pregidx(rd) @ encdec_pregidx(rs1) @ o1 @ sz1 @ encdec_pregidx(rs2) @ o2 @ sz2 @ encdec_bool(cd) @ 0x000 : bits(15)

// Opcode 21: MOVLI (3+3+8+8+8+1 = 31 bits)
mapping clause encdec = PMOVLI(rd, rs, off, sz, imm, cd)
    <-> 0b010101 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ off @ sz @ imm @ encdec_bool(cd) @ 0x000000 : bits(26)

// Opcode 22: MOVLII (3+3+8+8+8+8+1 = 39 bits)
mapping clause encdec = PMOVLII(rd, rs, off, sz, imm, isz, cd)
    <-> 0b010110 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ off @ sz @ imm @ isz @ encdec_bool(cd) @ 0b000000000000000000 : bits(18)

// Opcode 23: MOVR (3+3+8+8+3+8+8+1 = 42 bits)
mapping clause encdec = PMOVR(rd, rs1, o1, sz1, rs2, o2, sz2, cd)
    <-> 0b010111 @ encdec_pregidx(rd) @ encdec_pregidx(rs1) @ o1 @ sz1 @ encdec_pregidx(rs2) @ o2 @ sz2 @ encdec_bool(cd) @ 0x000 : bits(15)

// Opcode 24: MOVRI (3+3+8+8+8+1 = 31 bits)
mapping clause encdec = PMOVRI(rd, rs, off, sz, imm, cd)
    <-> 0b011000 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ off @ sz @ imm @ encdec_bool(cd) @ 0x000000 : bits(26)

// Opcode 25: MOVRII (3+3+8+8+8+8+1 = 39 bits)
mapping clause encdec = PMOVRII(rd, rs, off, sz, imm, isz, cd)
    <-> 0b011001 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ off @ sz @ imm @ isz @ encdec_bool(cd) @ 0b000000000000000000 : bits(18)

// Opcode 26: ADD (3+8+3+8+3+8+8 = 41 bits)
mapping clause encdec = PADD(rd, doff, rs1, s1off, rs2, s2off, sz)
    <-> 0b011010 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ 0b00000000000000000 : bits(17)

// Opcode 27: ADDI (3+3+16+8 = 30 bits)
mapping clause encdec = PADDI(rd, rs, imm, sz)
    <-> 0b011011 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ 0x0000000 : bits(28)

// Opcode 28: SUB (3+8+3+8+3+8+8 = 41 bits)
mapping clause encdec = PSUB(rd, doff, rs1, s1off, rs2, s2off, sz)
    <-> 0b011100 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ 0b00000000000000000 : bits(17)

// Opcode 29: SUBI (3+3+16+8 = 30 bits)
mapping clause encdec = PSUBI(rd, rs, imm, sz)
    <-> 0b011101 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ 0x0000000 : bits(28)

// Opcode 30: SUBII (3+16+3+8 = 30 bits)
mapping clause encdec = PSUBII(rd, imm, rs, sz)
    <-> 0b011110 @ encdec_pregidx(rd) @ imm @ encdec_pregidx(rs) @ sz @ 0x0000000 : bits(28)

// Opcode 31: AND (3+8+3+8+3+8+8 = 41 bits)
mapping clause encdec = PAND(rd, doff, rs1, s1off, rs2, s2off, sz)
    <-> 0b011111 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ 0b00000000000000000 : bits(17)

// Opcode 32: ANDI (3+3+16+8 = 30 bits)
mapping clause encdec = PANDI(rd, rs, imm, sz)
    <-> 0b100000 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ 0x0000000 : bits(28)

// Opcode 33: OR (3+8+3+8+3+8+8 = 41 bits)
mapping clause encdec = POR(rd, doff, rs1, s1off, rs2, s2off, sz)
    <-> 0b100001 @ encdec_pregidx(rd) @ doff @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ 0b00000000000000000 : bits(17)

// Opcode 34: ORI (3+3+16+8 = 30 bits)
mapping clause encdec = PORI(rd, rs, imm, sz)
    <-> 0b100010 @ encdec_pregidx(rd) @ encdec_pregidx(rs) @ imm @ sz @ 0x0000000 : bits(28)

// Opcode 35: CMP (3+8+3+8+8 = 30 bits)
mapping clause encdec = PCMP(rs1, s1off, rs2, s2off, sz)
    <-> 0b100011 @ encdec_pregidx(rs1) @ s1off @ encdec_pregidx(rs2) @ s2off @ sz @ 0x0000000 : bits(28)

// Opcode 36: CMPIBY (3+8+16+8 = 35 bits)
mapping clause encdec = PCMPIBY(rs, soff, imm, sz)
    <-> 0b100100 @ encdec_pregidx(rs) @ soff @ imm @ sz @ 0b00000000000000000000000 : bits(23)

// Opcode 37: CMPIBI (3+8+16+8 = 35 bits)
mapping clause encdec = PCMPIBI(rs, soff, imm, sz)
    <-> 0b100101 @ encdec_pregidx(rs) @ soff @ imm @ sz @ 0b00000000000000000000000 : bits(23)

// Opcode 38: BR (3+16 = 19 bits)
mapping clause encdec = PBR(cc, target)
    <-> 0b100110 @ encdec_pcond(cc) @ target @ 0x000000000 : bits(39)

// Opcode 39: BRBTST (1+3+8+16 = 28 bits)
mapping clause encdec = PBRBTST(btcc, rs, boff, target)
    <-> 0b100111 @ encdec_pbtcond(btcc) @ encdec_pregidx(rs) @ boff @ target @ 0b000000000000000000000000000000 : bits(30)

// Opcode 40: BRNS (3+8 = 11 bits)
mapping clause encdec = PBRNS(cc, rule)
    <-> 0b101000 @ encdec_pcond(cc) @ rule @ 0x00000000000 : bits(47)

// Opcode 41: BRNXTP (3+8+16 = 27 bits)
mapping clause encdec = PBRNXTP(cc, jm, addr)
    <-> 0b101001 @ encdec_pcond(cc) @ jm @ addr @ 0b0000000000000000000000000000000 : bits(31)

// Opcode 42: BRBTSTNXTP (1+3+8+8+16 = 36 bits)
mapping clause encdec = PBRBTSTNXTP(btcc, rs, boff, jm, addr)
    <-> 0b101010 @ encdec_pbtcond(btcc) @ encdec_pregidx(rs) @ boff @ jm @ addr @ 0x000000 : bits(22)

// Opcode 43: BRBTSTNS (1+3+8+8 = 20 bits)
mapping clause encdec = PBRBTSTNS(btcc, rs, boff, rule)
    <-> 0b101011 @ encdec_pbtcond(btcc) @ encdec_pregidx(rs) @ boff @ rule @ 0x000000000 : bits(38)

end encdec

// Encode a pinstr to bits(64).
val encode_pinstr : pinstr -> bits64
function encode_pinstr(instr) = encdec(instr)

// Decode bits(64) to pinstr. Unknown opcodes decode to NOP.
val decode_pinstr : bits64 -> pinstr
function decode_pinstr(bits) = encdec(bits)
```

Note: The `end encdec` closes the scattered mapping. The `encode_pinstr` and `decode_pinstr` wrapper functions provide a clean API.

The padding literals must total exactly the right number of bits so each mapping clause produces exactly 64 bits. If Sail rejects a padding literal, adjust the bit count. The formula is: `padding_bits = 58 - field_bits`.

- [ ] **Step 2: Type-check**

Run: `./dev.sh cmake --build build --target check`
Expected: PASS (or type errors from bit-width mismatches that need fixing)

This is the step most likely to need debugging — Sail's type checker is strict about bitvector widths in `@` concatenation. If errors occur, adjust padding widths until all clauses sum to exactly 64 bits.

- [ ] **Step 3: Commit**

```bash
git add model/parser/decode.sail
git commit -m "Add encdec mapping clauses for all 43 parser instructions"
```

---

### Task 3: Switch instruction memory to binary and update fetch loop

**Files:**
- Modify: `model/parser/state.sail` (pimem, init, write_pimem, parser_load_program)
- Modify: `model/parser/exec.sail` (fetch + decode)
- Modify: `model/parser/params.sail` (document memory size)

- [ ] **Step 1: Update `model/parser/params.sail`**

Add to the end of the file:

```sail
//
// Instruction memory: 65536 entries of 64-bit words.
// The spec does not define instruction memory capacity or PC width.
// We choose bits16 for PC (matching branch address fields) and
// size the memory to match the full addressable range.
// NOP encodes as 0x0000000000000000 (opcode 0, all-zero fields).
```

- [ ] **Step 2: Replace pimem in `model/parser/state.sail`**

Remove the entire `init_pimem` function (lines 58-312 approx — the 256-entry PNOP list) and the `pimem` register declaration. Replace with:

```sail
// Instruction memory: 65536 slots of 64-bit encoded instructions.
// NOP = 0x0000000000000000 (opcode 0). Zero-initialized.
register pimem : vector(65536, bits64)
```

Note: Sail may need a default value for the register. If `vector(65536, bits64)` without a default fails, use `= sail_zeros_vec(65536, 64)` or define an init function that returns a zero vector. This may need experimentation.

- [ ] **Step 3: Update `write_pimem` in `model/parser/state.sail`**

Replace the existing `write_pimem` function:

```sail
// Write an encoded instruction into instruction memory at the given index.
val write_pimem : (int, pinstr) -> unit
function write_pimem(idx, instr) = {
    assert(0 <= idx & idx < 65536, "instruction memory index out of bounds");
    pimem[idx] = encode_pinstr(instr)
}
```

- [ ] **Step 4: Update `parser_init` in `model/parser/state.sail`**

Replace the `// Reset instruction memory to all NOPs` section:

```sail
    // Reset instruction memory (all zeros = all NOPs)
    pimem = sail_zeros(65536 * 64);  // or appropriate zero-init
```

Note: The exact Sail syntax for zero-initializing a large bitvector register may need experimentation. Alternatives: loop to zero each entry, or use `[0x0000000000000000, ...]` if Sail requires a literal. If a literal is required, we can define a helper that writes zeros in a loop instead.

- [ ] **Step 5: Update `parser_load_program` in `model/parser/state.sail`**

Update the recursive loader to encode each instruction:

```sail
val parser_load_program_rec : (list(pinstr), int) -> unit
function parser_load_program_rec(instrs, idx) = {
    match instrs {
        [||] => (),
        i :: rest => {
            write_pimem(idx, i);
            parser_load_program_rec(rest, idx + 1)
        },
    }
}

val parser_load_program : list(pinstr) -> unit
function parser_load_program(instrs) = {
    ppc = sail_zeros(16);
    // Zero instruction memory (write NOPs to used range + some margin)
    var j : int = 0;
    while j < 256 do {
        assert(0 <= j & j < 65536);
        pimem[j] = sail_zeros(64);
        j = j + 1
    };
    parser_load_program_rec(instrs, 0)
}
```

Note: We only zero the first 256 entries on load (for performance), not all 65536. Programs that branch beyond 256 should explicitly write instructions at those addresses.

- [ ] **Step 6: Update `model/parser/exec.sail`**

Replace `parser_step`:

```sail
val parser_step : unit -> ExecutionResult
function parser_step() = {
    let pc_idx : int = unsigned(ppc);
    assert(0 <= pc_idx & pc_idx < 65536, "ppc out of instruction memory bounds");
    let encoded : bits64 = pimem[pc_idx];
    let instr : pinstr = decode_pinstr(encoded);

    // Advance PC before execute (branch instructions may overwrite it)
    ppc = ppc + 0x0001;
    execute(instr)
}
```

- [ ] **Step 7: Type-check and run all tests**

Run: `./dev.sh cmake --build build --target check`
Expected: PASS

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build`
Expected: all 23 tests pass (existing tests use parser_load_program which now encodes internally)

- [ ] **Step 8: Commit**

```bash
git add model/parser/params.sail model/parser/state.sail model/parser/exec.sail
git commit -m "Switch instruction memory to 64-bit binary encoding

Replaces vector(256, pinstr) with vector(65536, bits64).
Fetch loop now decodes via encdec mapping. parser_load_program
encodes pinstr values internally so existing tests keep working.
Removes 256-line init_pimem NOP list."
```

---

### Task 4: Add encoding round-trip tests

**Files:**
- Create: `test/parser/test_encoding.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create round-trip test**

```sail
// Tests for binary instruction encoding/decoding round-trips.

// Verify encode-then-decode is identity for representative instructions.
val test_roundtrip_nop : unit -> unit
function test_roundtrip_nop() = {
    let instr = PNOP();
    let encoded = encode_pinstr(instr);
    assert(encoded == 0x0000000000000000, "NOP should encode to all zeros");
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "NOP round-trip should be identity")
}

val test_roundtrip_halt : unit -> unit
function test_roundtrip_halt() = {
    let instr = PHALT(true);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "HALT(true) round-trip should be identity")
}

val test_roundtrip_ext : unit -> unit
function test_roundtrip_ext() = {
    let instr = PEXT(PR0, 0x00, 0x0060, 0x10, true);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "EXT round-trip should be identity")
}

val test_roundtrip_br : unit -> unit
function test_roundtrip_br() = {
    let instr = PBR(PCC_AL, 0x0032);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "BR round-trip should be identity")
}

val test_roundtrip_movl : unit -> unit
function test_roundtrip_movl() = {
    let instr = PMOVL(PR2, PR0, 0x00, 0x08, PR1, 0x00, 0x03, true);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "MOVL round-trip should be identity")
}

val test_roundtrip_cnctby : unit -> unit
function test_roundtrip_cnctby() = {
    // Widest instruction (49 field bits)
    let instr = PCNCTBY(PR0, 0x00, PR1, 0x00, 0x04, PR2, 0x04, 0x04);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "CNCTBY round-trip should be identity")
}

val test_roundtrip_pseek : unit -> unit
function test_roundtrip_pseek() = {
    let instr = PPSEEK(PR1, 0x00, PR0, 0x00, 0x10, 0x00);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "PSEEK round-trip should be identity")
}

val test_nop_is_zero : unit -> unit
function test_nop_is_zero() = {
    // Any zeroed memory should decode to NOP
    let decoded = decode_pinstr(0x0000000000000000);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == 0x0000000000000000, "zero should decode to NOP and re-encode to zero")
}

val main : unit -> unit
function main() = {
    test_roundtrip_nop();
    test_roundtrip_halt();
    test_roundtrip_ext();
    test_roundtrip_br();
    test_roundtrip_movl();
    test_roundtrip_cnctby();
    test_roundtrip_pseek();
    test_nop_is_zero()
}
```

- [ ] **Step 2: Register test**

Add to `test/CMakeLists.txt`:

```cmake
add_sail_test(test_encoding test/parser/test_encoding.sail)
```

- [ ] **Step 3: Build and run**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build`
Expected: all 24 tests pass

- [ ] **Step 4: Commit**

```bash
git add test/parser/test_encoding.sail test/CMakeLists.txt
git commit -m "Add encoding round-trip tests for binary instruction format"
```

---

### Task 5: Update docs and clean up todo

**Files:**
- Modify: `docs/todo.md`
- Modify: `docs/conventions.md`

- [ ] **Step 1: Update `docs/todo.md`**

Remove or move to Resolved:
- "Instruction encoding not modeled" → Resolved
- "Instruction memory limited to 256 slots" → Resolved

- [ ] **Step 2: Update `docs/conventions.md`**

Add a section about instruction encoding:

```markdown
## Instruction Encoding

64-bit fixed-width binary encoding. See `docs/specs/2026-04-01-binary-encoding-design.md` for the opcode table and field layout.

- Opcode: bits [63:58] (6 bits)
- Fields: packed MSB-first after opcode, zero-padded at LSB
- NOP = `0x0000000000000000` (opcode 0)
- Encoding/decoding: `encdec` scattered mapping in `model/parser/decode.sail`
- `encode_pinstr(instr)` / `decode_pinstr(bits)` wrapper functions
```

- [ ] **Step 3: Commit**

```bash
git add docs/todo.md docs/conventions.md
git commit -m "Update docs for binary encoding: resolve todo items, add conventions"
```
