
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

