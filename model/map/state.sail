
// MAP register file: 14 x 128-bit registers (R0-R13).
// See XISA spec section 4.2.
// The parser can write these via EXTMAP and MOVMAP instructions.
// After parsing, HW pre-loads R7.0 (SMD bytes 0-3), R11 (HDR.PRESENT),
// R12-R13 (HDR.OFFSET0/1) — that step is not modeled here.
register MAP : vector(14, bits128)

val init_map : unit -> vector(14, bits128)
function init_map() = [
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128),
]

// Read a MAP register by index (0-13).
val read_mapreg : int -> bits128
function read_mapreg(idx) = {
    assert(0 <= idx & idx < 14, "MAP register index out of bounds");
    MAP[idx]
}

// Write a MAP register by index (0-13).
val write_mapreg : (int, bits128) -> unit
function write_mapreg(idx, v) = {
    assert(0 <= idx & idx < 14, "MAP register index out of bounds");
    MAP[idx] = v
}
