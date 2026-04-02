
// MAP register file and execution state.
// See XISA spec sections 4.2-4.3, 4.8.2.

// MAP register file: 16 x 128-bit registers.
// R0-R10: general purpose
// R11: HDR.PRESENT (preloaded by parser)
// R12-R13: HDR.OFFSET0/1 (preloaded by parser)
// R14: debug (not modeled)
// R15: null register (reads zero, writes discarded)
register MAP : vector(16, bits128)

// Condition code flags (Section 4.8.2).
// Only updated when .F modifier is used (except CMP which always updates).
register mflag_z : bool  // Zero
register mflag_n : bool  // Negative
register mflag_c : bool  // Carry
register mflag_v : bool  // Overflow

// MAP program counter (16-bit, matching parser convention).
register mpc : bits16

// MAP halted flag.
register map_halted : bool

// MAP instruction memory: 65536 x 64-bit slots.
register map_imem : vector(65536, bits(64))

val init_map_regs : unit -> vector(16, bits128)
function init_map_regs() = [
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
]

// Write a raw 64-bit value into MAP instruction memory (with bounds check).
val write_map_imem_raw : (int, bits(64)) -> unit
function write_map_imem_raw(idx, v) = {
    assert(0 <= idx & idx < 65536, "map_imem index out of bounds");
    map_imem[idx] = v
}

// Zero a range of MAP instruction memory.
val map_imem_zero_range : (int, int) -> unit
function map_imem_zero_range(start, count) = {
    var i : int = start;
    while i < start + count do {
        write_map_imem_raw(i, sail_zeros(64));
        i = i + 1
    }
}

// Initialize all MAP state.
val map_init : unit -> unit
function map_init() = {
    MAP = init_map_regs();
    mflag_z = false;
    mflag_n = false;
    mflag_c = false;
    mflag_v = false;
    mpc = 0x0000;
    map_halted = false;
    // Zero first 256 entries (sufficient for test programs)
    map_imem_zero_range(0, 256)
}

// Read a full 128-bit MAP register.
// R15 always reads as zero (null register).
val read_mapreg : int -> bits128
function read_mapreg(idx) = {
    assert(0 <= idx & idx < 16, "MAP register index out of bounds");
    if idx == 15 then sail_zeros(128)
    else MAP[idx]
}

// Write a full 128-bit MAP register.
// Writes to R15 are silently discarded.
val write_mapreg : (int, bits128) -> unit
function write_mapreg(idx, v) = {
    assert(0 <= idx & idx < 16, "MAP register index out of bounds");
    if idx != 15 then MAP[idx] = v
}

// Read a 32-bit word from a MAP register.
// word_sel: 0=MSW (bits 127:96), 1=(95:64), 2=(63:32), 3=LSW (31:0).
val read_mapword : (int, int) -> bits(32)
function read_mapword(reg_idx, word_sel) = {
    let full = read_mapreg(reg_idx);
    let shift_amount = (3 - word_sel) * 32;
    sail_mask(32, sail_shiftright(full, shift_amount))
}

// Write a 32-bit word to a MAP register.
// Preserves other words in the register.
val write_mapword : (int, int, bits(32)) -> unit
function write_mapword(reg_idx, word_sel, val32) = {
    if reg_idx != 15 then {
        let full = read_mapreg(reg_idx);
        let bit_offset = (3 - word_sel) * 32;
        let mask : bits128 = sail_shiftleft(sail_zero_extend(0xFFFFFFFF : bits(32), 128), bit_offset);
        let cleared = full & not_vec(mask);
        let new_val = cleared | sail_shiftleft(sail_zero_extend(val32, 128), bit_offset);
        write_mapreg(reg_idx, new_val)
    }
}

// Read raw instruction memory slot.
val read_map_imem_raw : int -> bits(64)
function read_map_imem_raw(idx) = {
    assert(0 <= idx & idx < 65536, "MAP instruction memory index out of bounds");
    map_imem[idx]
}

// Load a MAP program (as a list of 64-bit encoded instructions) starting at address 0.
val map_load_program : list(bits(64)) -> unit
function map_load_program(instrs) = {
    var i : int = 0;
    var remaining = instrs;
    while match remaining { _ :: _ => true, [||] => false } do {
        match remaining {
            instr :: rest => {
                write_map_imem_raw(i, instr);
                i = i + 1;
                remaining = rest
            },
            [||] => (),
        }
    }
}
