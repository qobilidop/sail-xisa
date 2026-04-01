# Modeling Decisions

Deliberate choices about how we map XISA hardware behavior to our Sail model. These are intentional simplifications for functional correctness modeling, not things we plan to fix.

## Timing and Async Operations

- **All operations modeled synchronously.** The spec marks NXTP, PSEEK, EXTNXTP, and branch-taken as "asynchronous operation." In hardware, these initiate lookups that complete in parallel with subsequent instructions. In our model, all operations complete immediately. This is correct for functional semantics — the program must wait for the result (via a branch instruction) before using it regardless.

## Register Models

- **HDR array size is 32 entries.** The white paper does not specify the exact count for HDR.PRESENT and HDR.OFFSET arrays. We assume 32 entries, which covers all examples in the spec. Adjust if more information becomes available.

- **Struct-0 HW bits 6-31 not write-restricted.** The spec notes bits 6-31 of Struct-0 (SMD) are HW-controlled. We model the full 128-bit register with no write restrictions — the HW-controlled region is a hardware detail that doesn't affect instruction semantics.

- **MAP registers: full 128-bit access only.** The MAP spec (section 4.3) supports word-mode addressing (Ri.0 through Ri.3). From the parser's perspective (EXTMAP/MOVMAP), only full 128-bit register access is used. Word-mode addressing is a MAP ISA concern.

## Transition Table

- **Table size is 64 entries.** The spec defines the transition table interface (section 3.5) but not its capacity. 64 entries is sufficient for typical parser programs. This is an implementation-chosen parameter documented in `model/parser/params.sail`.

- **State ID is 8 bits.** The spec does not define the bit width of parser state IDs. 8 bits (256 states) covers typical protocol graphs. Documented in `model/parser/params.sail`.

- **NXTP lookup is synchronous.** See "Timing and Async Operations" above.

- **JumpMode 100 (trap) not supported.** Requires trap address configuration which is not yet modeled.

## PSEEK Table

- **Table size is 32 entries.** The spec does not define capacity. 32 entries covers typical protocol stacks.

- **Fixed header length per entry.** The spec says each PSEEK entry includes "next header offset and size." We interpret this as a fixed header length in bytes stored per entry, rather than reading a variable-length field from the packet. This simplifies the model; a more faithful implementation could read a length field at a configured offset.

- **Protocol value is 16 bits.** Inferred from the instruction's SizeBits range of 1-16.

- **No PSEEK_ERROR flag.** The spec describes a PSEEK_ERROR status flag set when the cursor would exceed the 256B packet header limit. We don't model this — the assert in `read_packet_byte` catches out-of-bounds access instead.

- **next_proto_offset is relative to new cursor.** After advancing the cursor by hdr_length, the next protocol field is read at `cursor + next_proto_offset`. This is an offset into the next header, not the current one.

## Instruction Memory

- **Union-value instruction memory, not binary.** Instructions are stored as `pinstr` union values in a 256-slot vector. The XISA white paper does not publish binary encoding formats. If encodings become available, switch to byte-level memory with `encdec` mappings. The `execute` function is unchanged — only fetch/decode changes.

## Packet and Cursor

- **Packet header buffer is 256 bytes.** Matches the spec's stated maximum (section 3.1). No header-violation error is modeled for cursor overflow — the assert in `read_packet_byte` catches out-of-bounds access.

## Deferred Modifiers

These instruction modifiers are not modeled because they require subsystems we haven't built:

- **.SCSM / .ECSM** (checksum accelerator start/end) — requires IPv4 checksum accelerator model (section 3.7)
- **.PR** (present bit) on EXT/EXTMAP/EXTNXTP — appends a 1 as MSbit; simple but deferred for batch addition
- **.RP** (reparse) on HALT — requires MAP thread handoff and reparse flow (section 3.9)
- **JumpMode** on STC/STH/STCH/STCI/STHC — requires transition table for modes 001-100 (section 3.5.1)
