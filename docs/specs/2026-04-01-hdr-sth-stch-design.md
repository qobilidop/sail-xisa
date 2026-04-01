# HDR Model + STH + STCH/STHC Design Spec

## Overview

STH, STCH, and STHC are header metadata instructions (XISA spec sections 3.12.7, 3.12.9). They record which protocol headers are present in the packet and where they start, by writing to the HDR.PRESENT and HDR.OFFSET register arrays.

- **STH**: Set header present and offset fields at current cursor position.
- **STCH**: Compound STCI + STH — increment cursor, then set header fields (offset = new cursor).
- **STHC**: Compound STH + STCI — set header fields (offset = current cursor), then increment cursor.

All three also support JumpMode and .SCSM/.ECSM, which are deferred. STH and STCH support .H (halt after operation).

Reference: [XISA white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf), sections 3.12.7, 3.12.9.

## HDR Model

The parser maintains two arrays indexed by header ID:

- `hdr_present`: 32-entry boolean array — set to true when a header is identified
- `hdr_offset`: 32-entry bits8 array — records the cursor position (byte offset) where the header starts

**Assumption:** 32 entries is a reasonable default. The white paper does not specify the exact count. This can be adjusted when more information is available.

Both arrays are initialized to false/zero in `parser_init()`.

A helper function `set_hdr(present_id, offset_id)` sets `hdr_present[present_id] = true` and `hdr_offset[offset_id] = pcursor`.

## Instruction Semantics

### STH (3.12.7)

**Syntax:** `STH[.SCSM|.ECSM][.H] HdrID, HdrOffsetID, JumpMode`

**Operation:**
1. `HDR.PRESENT[HeaderPresentID] = 1`
2. `HDR.OFFSET[HeaderOffsetID] = Cursor`
3. If .H: halt (set `parser_halted`, return `RETIRE_HALT`)

### STCH (3.12.9)

**Syntax:** `STCH[.SCSM|.ECSM][.H] IncrValue, HdrID, HdrOffsetID, JumpMode`

**Operation:** Compound of STCI followed by STH:
1. `Cursor += IncrValue`
2. `HDR.PRESENT[HeaderPresentID] = 1`
3. `HDR.OFFSET[HeaderOffsetID] = Cursor` (new cursor position)
4. If .H: halt

### STHC (3.12.9)

**Syntax:** `STHC[.SCSM|.ECSM] IncrValue, HdrID, HdrOffsetID, JumpMode`

**Operation:** Compound of STH followed by STCI:
1. `HDR.PRESENT[HeaderPresentID] = 1`
2. `HDR.OFFSET[HeaderOffsetID] = Cursor` (current cursor position, before increment)
3. `Cursor += IncrValue`

Note: STHC does not support .H per the spec.

## Deferred

- **JumpMode**: Requires transition table model (deferred to step 6 in roadmap). Modeled as if JumpMode=0 (no jump).
- **.SCSM/.ECSM**: Checksum start/end modifiers require hardware checksum state not yet modeled.

## Union Clauses

```sail
// STH: Set header present and offset fields.
// Fields: (header_present_id, header_offset_id, halt)
union clause pinstr = PSTH : (bits8, bits8, bool)

// STCH: Set cursor then header fields (STCI + STH).
// Fields: (incr_value, header_present_id, header_offset_id, halt)
union clause pinstr = PSTCH : (bits16, bits8, bits8, bool)

// STHC: Set header fields then cursor (STH + STCI).
// Fields: (incr_value, header_present_id, header_offset_id)
union clause pinstr = PSTHC : (bits16, bits8, bits8)
```

## State Additions

```sail
// Header present flags: 32 entries, indexed by header ID.
register hdr_present : vector(32, bool)

// Header offset values: 32 entries, indexed by header offset ID.
register hdr_offset : vector(32, bits8)
```

## Helper Function

```sail
// Set header present flag and offset for the given IDs.
// Uses the current cursor position as the offset value.
val set_hdr : (bits8, bits8) -> unit
function set_hdr(present_id, offset_id) = {
    let pid : int = unsigned(present_id);
    let oid : int = unsigned(offset_id);
    assert(0 <= pid & pid < 32, "header present ID out of bounds");
    assert(0 <= oid & oid < 32, "header offset ID out of bounds");
    hdr_present[pid] = true;
    hdr_offset[oid] = pcursor
}
```

## Execute Clauses

```sail
// STH: Set header present and offset, optionally halt.
function clause execute(PSTH(present_id, offset_id, halt)) = {
    set_hdr(present_id, offset_id);
    if halt then {
        parser_halted = true;
        RETIRE_HALT
    } else {
        RETIRE_SUCCESS
    }
}

// STCH: Increment cursor, then set header (STCI + STH).
function clause execute(PSTCH(incr_value, present_id, offset_id, halt)) = {
    let incr_8 : bits8 = sail_mask(8, incr_value);
    pcursor = pcursor + incr_8;
    set_hdr(present_id, offset_id);
    if halt then {
        parser_halted = true;
        RETIRE_HALT
    } else {
        RETIRE_SUCCESS
    }
}

// STHC: Set header at current cursor, then increment cursor (STH + STCI).
function clause execute(PSTHC(incr_value, present_id, offset_id)) = {
    set_hdr(present_id, offset_id);
    let incr_8 : bits8 = sail_mask(8, incr_value);
    pcursor = pcursor + incr_8;
    RETIRE_SUCCESS
}
```

## Tests (test/parser/test_sth.sail)

1. **STH basic**: cursor=14, STH(0, 0, false) -> hdr_present[0]=true, hdr_offset[0]=14
2. **STH with halt**: STH(0, 0, true) -> sets header and returns RETIRE_HALT
3. **STH different IDs**: present_id=1, offset_id=2 -> updates different array entries
4. **STCH basic**: cursor=0, STCH(14, 0, 0, false) -> cursor=14, hdr_offset[0]=14 (new cursor)
5. **STHC basic**: cursor=0, STHC(14, 0, 0) -> hdr_offset[0]=0 (old cursor), cursor=14
6. **STCH vs STHC ordering**: same values, verify STCH records new cursor, STHC records old cursor
7. **Program-level**: EXT + STCH to parse Ethernet header, STCH to advance and record, EXT at new position
