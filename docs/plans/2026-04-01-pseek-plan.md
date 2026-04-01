# PSEEK, PSEEKNXTP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the PSEEK table model and PSEEK/PSEEKNXTP instructions for fast-forwarding past known protocol headers.

**Architecture:** Create `model/parser/pseek.sail` for the PSEEK table (32-entry parallel arrays). PSEEK scans forward through packet headers in a loop, skipping protocols that match table entries. PSEEKNXTP additionally performs an NXTP transition lookup with the final protocol value.

**Tech Stack:** Sail, CMake/CTest

---

### Task 1: Create PSEEK table model

**Files:**
- Create: `model/parser/pseek.sail`
- Modify: `model/main.sail` (add $include)
- Modify: `model/parser/state.sail` (add init call to parser_init)
- Modify: `model/parser/params.sail` (document PSEEK params)

- [ ] **Step 1: Update `model/parser/params.sail`**

Append to the file:

```sail
//
// PSEEK table: 32 entries.
// Each entry defines a skippable protocol header.
// The spec does not define table capacity or entry field widths.
//
// Parameters:
//   Table size:         32 entries (indexed 0-31)
//   Class ID:           8 bits (bits8), range 0-3 per spec
//   Protocol value:     16 bits (bits16), max from SizeBits range 1-16
//   Header length:      8 bits (bits8), fixed bytes per entry
//   Next proto offset:  8 bits (bits8), byte offset within header
//   Next proto size:    8 bits (bits8), size in bits
//
// See docs/specs/2026-04-01-pseek-design.md for assumptions.
```

- [ ] **Step 2: Create `model/parser/pseek.sail`**

```sail

// PSEEK table: defines skippable protocol headers for fast-forward scanning.
// See XISA spec section 3.6 and docs/specs/2026-04-01-pseek-design.md.
//
// Uses parallel arrays (matching transition table pattern).
// Size: 32 entries (see model/parser/params.sail).

register pseek_valid           : vector(32, bool)
register pseek_class_id        : vector(32, bits8)
register pseek_protocol_value  : vector(32, bits16)
register pseek_hdr_length      : vector(32, bits8)
register pseek_next_proto_off  : vector(32, bits8)
register pseek_next_proto_size : vector(32, bits8)

val init_pseek_valid : unit -> vector(32, bool)
function init_pseek_valid() = [
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
]

val init_pseek_bits8 : unit -> vector(32, bits8)
function init_pseek_bits8() = [
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
]

val init_pseek_bits16 : unit -> vector(32, bits16)
function init_pseek_bits16() = [
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
]

// Reset all PSEEK table entries.
val pseek_table_init : unit -> unit
function pseek_table_init() = {
    pseek_valid = init_pseek_valid();
    pseek_class_id = init_pseek_bits8();
    pseek_protocol_value = init_pseek_bits16();
    pseek_hdr_length = init_pseek_bits8();
    pseek_next_proto_off = init_pseek_bits8();
    pseek_next_proto_size = init_pseek_bits8()
}

// Accessor functions (needed for Sail type checker with loop variables).
val read_pseek_valid : int -> bool
function read_pseek_valid(idx) = {
    assert(0 <= idx & idx < 32, "PSEEK table index out of bounds");
    pseek_valid[idx]
}

val read_pseek_class_id : int -> bits8
function read_pseek_class_id(idx) = {
    assert(0 <= idx & idx < 32, "PSEEK table index out of bounds");
    pseek_class_id[idx]
}

val read_pseek_protocol_value : int -> bits16
function read_pseek_protocol_value(idx) = {
    assert(0 <= idx & idx < 32, "PSEEK table index out of bounds");
    pseek_protocol_value[idx]
}

val read_pseek_hdr_length : int -> bits8
function read_pseek_hdr_length(idx) = {
    assert(0 <= idx & idx < 32, "PSEEK table index out of bounds");
    pseek_hdr_length[idx]
}

val read_pseek_next_proto_off : int -> bits8
function read_pseek_next_proto_off(idx) = {
    assert(0 <= idx & idx < 32, "PSEEK table index out of bounds");
    pseek_next_proto_off[idx]
}

val read_pseek_next_proto_size : int -> bits8
function read_pseek_next_proto_size(idx) = {
    assert(0 <= idx & idx < 32, "PSEEK table index out of bounds");
    pseek_next_proto_size[idx]
}

// Write a PSEEK table entry (for test setup and configuration).
val write_pseek_entry : (int, bits8, bits16, bits8, bits8, bits8) -> unit
function write_pseek_entry(idx, class_id, proto_val, hdr_len, next_off, next_size) = {
    assert(0 <= idx & idx < 32, "PSEEK table index out of bounds");
    pseek_valid[idx] = true;
    pseek_class_id[idx] = class_id;
    pseek_protocol_value[idx] = proto_val;
    pseek_hdr_length[idx] = hdr_len;
    pseek_next_proto_off[idx] = next_off;
    pseek_next_proto_size[idx] = next_size
}

// Look up (class_id, proto_val) in the PSEEK table.
// Returns the index of the matching entry, or -1 if not found.
val pseek_lookup : (bits8, bits16) -> int
function pseek_lookup(class_id, proto_val) = {
    var result : int = negate(1);
    var i : int = 0;
    while i < 32 do {
        if result < 0 then {
            if read_pseek_valid(i) then {
                if read_pseek_class_id(i) == class_id then {
                    if read_pseek_protocol_value(i) == proto_val then {
                        result = i
                    }
                }
            }
        };
        i = i + 1
    };
    result
}

// Extract a protocol field from the packet at a byte offset with a given bit size.
// Used by the PSEEK scan loop to read next-protocol fields from packet headers.
val pseek_extract_proto : (int, int) -> bits16
function pseek_extract_proto(byte_offset, size_bits) = {
    // Read enough bytes to cover the field, big-endian
    let bit_offset : int = byte_offset * 8;
    let pbo_bv : bits(20) = get_slice_int(20, bit_offset, 0);
    let start_byte = unsigned(sail_shiftright(pbo_bv, 3));
    let bit_in_byte = unsigned(pbo_bv & 0x00007);

    let sum_bv : bits(20) = get_slice_int(20, bit_in_byte + size_bits + 7, 0);
    let bytes_needed = unsigned(sail_shiftright(sum_bv, 3));

    var acc : bits128 = sail_zeros(128);
    var i : int = 0;
    while i < bytes_needed do {
        let bidx : int = start_byte + i;
        let bval : bits128 = sail_zero_extend(read_packet_byte(bidx), 128);
        acc = acc | sail_shiftleft(bval, 8 * (bytes_needed - 1 - i));
        i = i + 1
    };

    let shift_amount : int = bytes_needed * 8 - bit_in_byte - size_bits;
    let extracted : bits128 = sail_shiftright(acc, shift_amount) & sail_mask(128, sail_ones(size_bits));
    sail_mask(16, extracted)
}
```

- [ ] **Step 3: Add `$include` in `model/main.sail`**

Insert after `transition.sail`, before `state.sail`:

```sail
$include "parser/transition.sail"
$include "parser/pseek.sail"
$include "parser/state.sail"
```

- [ ] **Step 4: Add `pseek_table_init()` call to `parser_init()` in `model/parser/state.sail`**

Insert after the `transition_table_init();` line:

```sail
    // Reset transition table and NXTP result
    transition_table_init();

    // Reset PSEEK table
    pseek_table_init();

    // Reset MAP registers
```

- [ ] **Step 5: Type-check and run existing tests**

Run: `./dev.sh cmake --build build --target check`
Expected: PASS

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build`
Expected: all 22 tests pass

- [ ] **Step 6: Commit**

```bash
git add model/parser/params.sail model/parser/pseek.sail model/main.sail model/parser/state.sail
git commit -m "Add PSEEK table model (32-entry parallel arrays)"
```

---

### Task 2: Add union clauses and execute clauses

**Files:**
- Modify: `model/parser/types.sail` (before `end pinstr`)
- Modify: `model/parser/insts.sail` (before `end execute`)

- [ ] **Step 1: Add union clauses to `model/parser/types.sail`**

Insert before `end pinstr`:

```sail
// PSEEK: Scan over protocol headers to next protocol of interest.
// Fields: (dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits, class_id)
union clause pinstr = PPSEEK : (pregidx, bits8, pregidx, bits8, bits8, bits8)

// PSEEKNXTP: PSEEK + NXTP lookup with final protocol value.
// Fields: (dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits, class_id)
union clause pinstr = PPSEEKNXTP : (pregidx, bits8, pregidx, bits8, bits8, bits8)
```

- [ ] **Step 2: Add execute clauses to `model/parser/insts.sail`**

Insert before `end execute`:

```sail
// PSEEK: Scan forward through packet headers, skipping protocols in the PSEEK table.
// Advances cursor past each matched header. Stores final (unmatched) protocol in DestReg.
function clause execute(PPSEEK(rd, dest_offset_bits, rs, src_offset_bits, size_bits, class_id)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let sz : nat = unsigned(size_bits);
    let doff : nat = unsigned(dest_offset_bits);

    // Extract initial protocol value from source register
    let initial = extract_bits(src_val, soff, sz);
    var proto : bits16 = sail_mask(16, initial);
    var current_size : int = sz;

    // Scan loop: keep skipping while protocol matches a PSEEK entry
    var scanning : bool = true;
    while scanning do {
        let entry_idx = pseek_lookup(class_id, proto);
        if entry_idx < 0 then {
            // No match — stop scanning
            scanning = false
        } else {
            // Match: advance cursor by header length
            let hdr_len : bits8 = read_pseek_hdr_length(entry_idx);
            pcursor = pcursor + hdr_len;
            // Extract next protocol from packet
            let next_off : int = unsigned(pcursor) + unsigned(read_pseek_next_proto_off(entry_idx));
            let next_sz : int = unsigned(read_pseek_next_proto_size(entry_idx));
            proto = pseek_extract_proto(next_off, next_sz);
            current_size = next_sz
        }
    };

    // Store final protocol value in DestReg at DestOffsetBits
    let dst_val = read_preg(rd);
    let proto_128 : bits128 = sail_zero_extend(proto, 128);
    let result = insert_bits(dst_val, doff, current_size, proto_128);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// PSEEKNXTP: PSEEK scan + NXTP lookup with final protocol value.
function clause execute(PPSEEKNXTP(rd, dest_offset_bits, rs, src_offset_bits, size_bits, class_id)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let sz : nat = unsigned(size_bits);
    let doff : nat = unsigned(dest_offset_bits);

    // Extract initial protocol value from source register
    let initial = extract_bits(src_val, soff, sz);
    var proto : bits16 = sail_mask(16, initial);
    var current_size : int = sz;

    // Scan loop (same as PSEEK)
    var scanning : bool = true;
    while scanning do {
        let entry_idx = pseek_lookup(class_id, proto);
        if entry_idx < 0 then {
            scanning = false
        } else {
            let hdr_len : bits8 = read_pseek_hdr_length(entry_idx);
            pcursor = pcursor + hdr_len;
            let next_off : int = unsigned(pcursor) + unsigned(read_pseek_next_proto_off(entry_idx));
            let next_sz : int = unsigned(read_pseek_next_proto_size(entry_idx));
            proto = pseek_extract_proto(next_off, next_sz);
            current_size = next_sz
        }
    };

    // Store final protocol value in DestReg
    let dst_val = read_preg(rd);
    let proto_128 : bits128 = sail_zero_extend(proto, 128);
    let result = insert_bits(dst_val, doff, current_size, proto_128);
    write_preg(rd, result);

    // NXTP lookup with final protocol
    let key : bits24 = sail_zero_extend(proto, 24);
    nxtp_matched = transition_lookup(parser_state, key);
    RETIRE_SUCCESS
}
```

- [ ] **Step 3: Type-check**

Run: `./dev.sh cmake --build build --target check`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add model/parser/types.sail model/parser/insts.sail
git commit -m "Add PSEEK and PSEEKNXTP union and execute clauses"
```

---

### Task 3: Add tests

**Files:**
- Create: `test/parser/test_pseek.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create `test/parser/test_pseek.sail`**

```sail
// Tests for PSEEK and PSEEKNXTP (protocol seek accelerator) instructions.

// PSEEK: no match — protocol not in table, cursor unchanged.
val test_pseek_no_skip : unit -> unit
function test_pseek_no_skip() = {
    parser_init();
    // R0 has protocol value 0x0800 (IPv4)
    PR[0] = 0x00000000_00000000_00000000_00000800;
    // No PSEEK entries configured — 0x0800 not in table
    // PPSEEK(dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits, class_id)
    let _ = execute(PPSEEK(PR1, 0x00, PR0, 0x00, 0x10, 0x00));
    assert(PR[1] == 0x00000000_00000000_00000000_00000800,
        "PSEEK should store original protocol in R1");
    assert(pcursor == 0x00, "cursor should not advance when no match")
}

// PSEEK: skip one VLAN tag.
// Packet layout at cursor:
//   [VLAN tag: 4 bytes] [inner EtherType: 2 bytes at offset 2 within VLAN]
// VLAN EtherType = 0x8100, inner EtherType = 0x0800
val test_pseek_skip_one : unit -> unit
function test_pseek_skip_one() = {
    parser_init();
    // Set cursor to byte 12 (after Ethernet dst+src)
    pcursor = 0x0C;
    // Packet: EtherType=0x8100 at bytes 12-13, VLAN tag bytes 14-15,
    //         inner EtherType=0x0800 at bytes 16-17
    packet_hdr[12] = 0x81;
    packet_hdr[13] = 0x00;
    packet_hdr[14] = 0x00;  // VLAN TCI
    packet_hdr[15] = 0x01;
    packet_hdr[16] = 0x08;  // inner EtherType
    packet_hdr[17] = 0x00;

    // PSEEK entry: class 0, proto 0x8100 (VLAN), hdr_length=4, next_proto at offset 2, size 16 bits
    write_pseek_entry(0, 0x00, 0x8100, 0x04, 0x02, 0x10);

    // R0 has initial protocol 0x8100
    PR[0] = 0x00000000_00000000_00000000_00008100;
    let _ = execute(PPSEEK(PR1, 0x00, PR0, 0x00, 0x10, 0x00));

    assert(pcursor == 0x10, "cursor should advance by 4 (from 12 to 16)");
    assert(PR[1] == 0x00000000_00000000_00000000_00000800,
        "PSEEK should store inner EtherType 0x0800 in R1")
}

// PSEEK: skip two stacked VLAN tags (QinQ).
// Packet at cursor 12:
//   [outer VLAN: 0x8100, 4 bytes] [inner VLAN: 0x8100, 4 bytes] [EtherType: 0x0800]
val test_pseek_skip_two : unit -> unit
function test_pseek_skip_two() = {
    parser_init();
    pcursor = 0x0C;
    // Outer VLAN at byte 12
    packet_hdr[12] = 0x81; packet_hdr[13] = 0x00;
    packet_hdr[14] = 0x00; packet_hdr[15] = 0x01;
    // Inner VLAN at byte 16
    packet_hdr[16] = 0x81; packet_hdr[17] = 0x00;
    packet_hdr[18] = 0x00; packet_hdr[19] = 0x02;
    // Final EtherType at byte 20
    packet_hdr[20] = 0x08; packet_hdr[21] = 0x00;

    // PSEEK entry for VLAN
    write_pseek_entry(0, 0x00, 0x8100, 0x04, 0x02, 0x10);

    PR[0] = 0x00000000_00000000_00000000_00008100;
    let _ = execute(PPSEEK(PR1, 0x00, PR0, 0x00, 0x10, 0x00));

    assert(pcursor == 0x14, "cursor should advance by 8 (from 12 to 20)");
    assert(PR[1] == 0x00000000_00000000_00000000_00000800,
        "PSEEK should store final EtherType 0x0800 after skipping two VLANs")
}

// PSEEKNXTP: skip VLAN + NXTP lookup.
val test_pseeknxtp : unit -> unit
function test_pseeknxtp() = {
    parser_init();
    pcursor = 0x0C;
    packet_hdr[12] = 0x81; packet_hdr[13] = 0x00;
    packet_hdr[14] = 0x00; packet_hdr[15] = 0x01;
    packet_hdr[16] = 0x08; packet_hdr[17] = 0x00;

    write_pseek_entry(0, 0x00, 0x8100, 0x04, 0x02, 0x10);
    // Transition rule: state 0, key 0x0800 -> PC 100, state 1
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);

    PR[0] = 0x00000000_00000000_00000000_00008100;
    let _ = execute(PPSEEKNXTP(PR1, 0x00, PR0, 0x00, 0x10, 0x00));

    assert(pcursor == 0x10, "cursor should advance past VLAN");
    assert(PR[1] == 0x00000000_00000000_00000000_00000800,
        "R1 should have inner EtherType");
    assert(nxtp_matched == true, "PSEEKNXTP should find transition match");
    assert(nxtp_result_pc == 0x0064, "result PC should be 100")
}

// PSEEK with RN dest: cursor advances but no register written.
val test_pseek_rn_dest : unit -> unit
function test_pseek_rn_dest() = {
    parser_init();
    pcursor = 0x0C;
    packet_hdr[12] = 0x81; packet_hdr[13] = 0x00;
    packet_hdr[14] = 0x00; packet_hdr[15] = 0x01;
    packet_hdr[16] = 0x08; packet_hdr[17] = 0x00;

    write_pseek_entry(0, 0x00, 0x8100, 0x04, 0x02, 0x10);

    PR[0] = 0x00000000_00000000_00000000_00008100;
    let _ = execute(PPSEEK(PRN, 0x00, PR0, 0x00, 0x10, 0x00));

    assert(pcursor == 0x10, "cursor should still advance");
    assert(read_preg(PRN) == sail_zeros(128), "RN should read as zero")
}

// Program: Ethernet with VLAN -> skip VLAN -> NXTP -> BRNXTP to IPv4.
val test_pseek_program : unit -> unit
function test_pseek_program() = {
    parser_init();
    // Ethernet frame: dst(6) + src(6) + EtherType(2) = 14 bytes
    // EtherType = 0x8100 (VLAN) at bytes 12-13
    packet_hdr[12] = 0x81; packet_hdr[13] = 0x00;
    // VLAN tag: TCI(2) + inner EtherType(2) at bytes 14-17
    packet_hdr[14] = 0x00; packet_hdr[15] = 0x01;
    packet_hdr[16] = 0x08; packet_hdr[17] = 0x00;

    // PSEEK: skip 0x8100, hdr_length=4, next_proto at offset 2, 16 bits
    write_pseek_entry(0, 0x00, 0x8100, 0x04, 0x02, 0x10);
    // Transition: 0x0800 in state 0 -> PC 50, state 1
    write_transition_rule(0, 0x00, 0x000800, 0x0032, 0x01);

    parser_load_program(
        [|
            // Set cursor to byte 12 (EtherType position)
            PSTCI(0x000C),
            // EXT EtherType into R0[15:0]
            PEXT(PR0, 0x00, 0x0000, 0x10, true),
            // PSEEKNXTP: skip VLANs, lookup final protocol
            PPSEEKNXTP(PR1, 0x00, PR0, 0x00, 0x10, 0x00),
            // BRNXTP to IPv4 handler
            PBRNXTP(PCC_AL, 0x00, 0x0000),
        |],
    );
    write_pimem(50, PHALT(false));

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt at IPv4 handler");
    assert(parser_state == 0x01, "parser_state should be 1 (IPv4)");
    assert(pcursor == 0x10, "cursor should be past VLAN tag at byte 16");
    assert(PR[1] == 0x00000000_00000000_00000000_00000800,
        "R1 should have inner EtherType 0x0800")
}

val main : unit -> unit
function main() = {
    test_pseek_no_skip();
    test_pseek_skip_one();
    test_pseek_skip_two();
    test_pseeknxtp();
    test_pseek_rn_dest();
    test_pseek_program()
}
```

- [ ] **Step 2: Register test in `test/CMakeLists.txt`**

Add at the end:

```cmake
add_sail_test(test_pseek test/parser/test_pseek.sail)
```

- [ ] **Step 3: Build and run**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_pseek -V`
Expected: PASS

- [ ] **Step 4: Run full suite**

Run: `./dev.sh ctest --test-dir build`
Expected: all 23 tests pass

- [ ] **Step 5: Commit**

```bash
git add test/parser/test_pseek.sail test/CMakeLists.txt
git commit -m "Add tests for PSEEK and PSEEKNXTP instructions"
```

---

### Task 4: Update coverage, modeling decisions, and params

**Files:**
- Modify: `docs/coverage.md`
- Modify: `docs/modeling-decisions.md`

- [ ] **Step 1: Update `docs/coverage.md`**

Change lines 17-18 from:

```markdown
| 9 | PSEEK | 3.12.2 | Not started | Requires PSEEK table model |
| 10 | PSEEKNXTP | 3.12.2 | Not started | |
```

to:

```markdown
| 9 | PSEEK | 3.12.2 | Done | No PSEEK_ERROR/trap, no .CD. Fixed hdr length per entry |
| 10 | PSEEKNXTP | 3.12.2 | Done | No .CD |
```

- [ ] **Step 2: Add PSEEK section to `docs/modeling-decisions.md`**

Add after the "Transition Table" section:

```markdown
## PSEEK Table

- **Table size is 32 entries.** The spec does not define capacity. 32 entries covers typical protocol stacks.

- **Fixed header length per entry.** The spec says each PSEEK entry includes "next header offset and size." We interpret "size" as a fixed header length in bytes stored per entry, rather than reading a variable-length field from the packet. This simplifies the model; a more faithful implementation could read a length field at a configured offset.

- **Protocol value is 16 bits.** Inferred from the instruction's SizeBits range of 1-16.

- **No PSEEK_ERROR flag.** The spec describes a PSEEK_ERROR status flag set when the cursor would exceed the 256B packet header limit. We don't model this — the assert in `read_packet_byte` catches out-of-bounds access instead.
```

- [ ] **Step 3: Commit**

```bash
git add docs/coverage.md docs/modeling-decisions.md
git commit -m "Update coverage and modeling decisions for PSEEK"
```
