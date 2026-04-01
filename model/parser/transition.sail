
// Parser transition table: maps (state, protocol_key) to next-state entry points.
// See XISA spec section 3.5 and docs/specs/2026-04-01-transition-table-nxtp-design.md.
//
// Uses parallel arrays (matching HDR pattern) rather than structs.
// Size: 64 entries (see model/parser/params.sail).

// NXTP result: stored by NXTP, consumed by BRNXTP.
register nxtp_result_pc : bits16
register nxtp_result_state : bits8
register nxtp_matched : bool

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

// Reset all transition table entries and NXTP result.
val transition_table_init : unit -> unit
function transition_table_init() = {
    nxtp_result_pc = sail_zeros(16);
    nxtp_result_state = sail_zeros(8);
    nxtp_matched = false;
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

// Read a transition table field by index (with bounds check).
val read_tt_valid : int -> bool
function read_tt_valid(idx) = {
    assert(0 <= idx & idx < 64, "transition table index out of bounds");
    tt_valid[idx]
}

val read_tt_state : int -> bits8
function read_tt_state(idx) = {
    assert(0 <= idx & idx < 64, "transition table index out of bounds");
    tt_state[idx]
}

val read_tt_key : int -> bits24
function read_tt_key(idx) = {
    assert(0 <= idx & idx < 64, "transition table index out of bounds");
    tt_key[idx]
}

val read_tt_next_pc : int -> bits16
function read_tt_next_pc(idx) = {
    assert(0 <= idx & idx < 64, "transition table index out of bounds");
    tt_next_pc[idx]
}

val read_tt_next_state : int -> bits8
function read_tt_next_state(idx) = {
    assert(0 <= idx & idx < 64, "transition table index out of bounds");
    tt_next_state[idx]
}

// Look up (state, key) in the transition table.
// Returns true and sets nxtp_result_pc/nxtp_result_state if found.
// Returns false if no match.
val transition_lookup : (bits8, bits24) -> bool
function transition_lookup(state, key) = {
    var found : bool = false;
    var i : int = 0;
    while i < 64 do {
        if not_bool(found) then {
            if read_tt_valid(i) then {
                if read_tt_state(i) == state then {
                    if read_tt_key(i) == key then {
                        nxtp_result_pc = read_tt_next_pc(i);
                        nxtp_result_state = read_tt_next_state(i);
                        found = true
                    }
                }
            }
        };
        i = i + 1
    };
    found
}
