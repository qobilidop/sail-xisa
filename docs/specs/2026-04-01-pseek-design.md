# PSEEK, PSEEKNXTP Design Spec

## Overview

PSEEK is a parser accelerator that scans forward through a chain of protocol headers, skipping known protocols until reaching one not in the PSEEK table. PSEEKNXTP additionally performs an NXTP lookup with the final protocol value.

This is sub-project B of the transition table work.

Reference: [XISA white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf), sections 3.6, 3.12.2.

## Assumptions (not in spec)

The spec defines the PSEEK table interface but not its internal structure. These are our modeling choices, documented in `docs/modeling-decisions.md` and `model/parser/params.sail`:

- **Table size: 32 entries.** The spec does not define capacity.
- **Protocol value: bits16.** Inferred from SizeBits range 1-16 in section 3.12.2.
- **Fixed header length per entry.** The spec says each entry has "next header offset and size." We interpret this as: each entry stores a fixed header length (in bytes) that PSEEK uses to advance the cursor. This avoids needing to read a variable-length field from the packet. A more faithful model would read a length field from the packet at a configured offset — this can be added later if needed.
- **Next protocol field: offset + size within header.** Each entry stores where the next protocol ID is located relative to the current cursor, so PSEEK can extract it for the next iteration.
- **Synchronous execution.** Spec says "asynchronous operation" — we model synchronously per our modeling decisions.

## PSEEK Table Model

Located in `model/parser/pseek.sail`. Parallel arrays (matching transition table pattern). Size: 32 entries.

Each entry:
- `valid : bool` — whether this entry is active
- `class_id : bits8` — partition key (range 0-3 per spec)
- `protocol_value : bits16` — protocol ID value to match
- `hdr_length : bits8` — fixed header length in bytes (how far to advance cursor)
- `next_proto_offset : bits8` — byte offset within header where next protocol field starts
- `next_proto_size : bits8` — size of next protocol field in bits (for next iteration's extraction)

### Helpers
- `write_pseek_entry(idx, class_id, proto_val, hdr_len, next_offset, next_size)` — configure an entry
- `pseek_lookup(class_id, proto_val)` — search for matching `(class_id, protocol_value)`, return index or -1

## Instruction Semantics

### PSEEK (3.12.2)

**Syntax:** `PSEEK[.CD] Rd, DestOffsetBits, Rs, SrcOffsetBits, SizeBits, ClassID`

**Operation:**
1. Extract initial protocol value: `proto = SrcReg[SrcOffsetBits + SizeBits - 1 : SrcOffsetBits]`
2. Search PSEEK table for `(ClassID, proto)` match
3. If match found:
   - Advance cursor by `entry.hdr_length`
   - Extract next protocol from packet at `cursor + entry.next_proto_offset`, size `entry.next_proto_size` bits
   - `proto = extracted_next_proto`
   - Repeat from step 2
4. If no match: stop scanning
5. Store final `proto` in `DestReg` at `DestOffsetBits` (truncated to SizeBits from last entry, or original SizeBits if no match)
6. Return RETIRE_SUCCESS

### PSEEKNXTP (3.12.2)

**Syntax:** `PSEEKNXTP[.CD] Rd, DestOffsetBits, Rs, SrcOffsetBits, SizeBits, ClassID`

**Operation:** Same as PSEEK, then additionally:
7. Perform NXTP: `transition_lookup(parser_state, proto[23:0])`

## Union Clauses

```sail
// PSEEK: Scan over protocol headers to next protocol of interest.
// Fields: (dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits, class_id)
union clause pinstr = PPSEEK : (pregidx, bits8, pregidx, bits8, bits8, bits8)

// PSEEKNXTP: PSEEK + NXTP lookup with final protocol value.
// Fields: (dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits, class_id)
union clause pinstr = PPSEEKNXTP : (pregidx, bits8, pregidx, bits8, bits8, bits8)
```

## Deferred

- PSEEK_ERROR flag / trap on cursor overflow past 256B
- .CD modifier on PSEEK/PSEEKNXTP
- Variable header length (reading length field from packet instead of fixed per-entry)

## Tests (test/parser/test_pseek.sail)

1. **PSEEK no skip**: protocol not in PSEEK table → DestReg gets original value, cursor unchanged
2. **PSEEK skip one VLAN**: VLAN tag (EtherType 0x8100) in table with hdr_length=4 → cursor advances by 4, DestReg has inner EtherType
3. **PSEEK skip two stacked VLANs**: two VLAN tags → cursor advances by 8 total
4. **PSEEKNXTP**: skip VLAN + NXTP lookup → nxtp_matched with final EtherType
5. **PSEEK with RN dest**: DestReg=RN → no register written but cursor still advances
6. **Program**: Full Ethernet with VLAN tag: EXT EtherType → PSEEK to skip VLAN → NXTP → BRNXTP to IPv4 handler
