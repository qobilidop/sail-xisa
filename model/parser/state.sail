
// Parser general-purpose registers: 4 x 128-bit, big-endian.
register PR : vector(4, bits128)

// Parser cursor position in the packet header buffer.
// Range 0-255 (up to 256 bytes of packet header).
register pcursor : bits8

// Packet header buffer: 256 bytes.
register packet_hdr : vector(256, bits8)

// Parser state ID for transition table lookups.
// Tracks which protocol/state the parser is currently in.
register parser_state : bits8

// Parser halted flag.
register parser_halted : bool

// Parser drop flag (set by HALTDROP).
register parser_drop : bool

// Header present flags: 32 entries, indexed by header ID.
// Assumption: 32 entries is a reasonable default; the white paper does not
// specify the exact count. Adjust when more information is available.
register hdr_present : vector(32, bool)

// Header offset values: 32 entries, indexed by header offset ID.
// Records the cursor position (byte offset) when a header was identified.
register hdr_offset : vector(32, bits8)

// Struct-0: 128-bit Standard Metadata (SMD) register.
// Passed from the parser to the MAP after parsing completes.
// Bits 6-31 are HW-controlled in real hardware; not enforced in this model.
register struct0 : bits128

val init_hdr_present : unit -> vector(32, bool)
function init_hdr_present() = [
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
]

val init_hdr_offset : unit -> vector(32, bits8)
function init_hdr_offset() = [
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
]

// Parser program counter.
register ppc : bits16

// Instruction memory: 65536 slots of 64-bit encoded instructions.
// NOP = 0x0000000000000000 (opcode 0). See model/parser/params.sail.
register pimem : vector(65536, bits(64))

// Condition flags (set by arithmetic/compare instructions).
register pflag_z :
    bool // Zero flag
register pflag_n :
    bool // Negative flag
// Evaluate a branch condition code against the current flags.
val eval_pcond : pcond -> bool
function eval_pcond(cc) = match cc {
    PCC_EQ  => pflag_z,
    PCC_NEQ => not_bool(pflag_z),
    PCC_LT  => pflag_n,
    PCC_GT  => not_bool(pflag_n) & not_bool(pflag_z),
    PCC_GE  => not_bool(pflag_n),
    PCC_LE  => pflag_n | pflag_z,
    PCC_AL  => true,
}

// Read a parser register. PRN always reads as zero.
val read_preg : pregidx -> bits128
function read_preg(r) =
    if is_null_reg(r) then {
        sail_zeros(128)
    } else {
        PR[pregidx_to_nat(r)]
    }

// Write a parser register. Writes to PRN are discarded.
val write_preg : (pregidx, bits128) -> unit
function write_preg(r, v) =
    if not_bool(is_null_reg(r)) then {
        PR[pregidx_to_nat(r)] = v
    }

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

// Write a raw 64-bit value into instruction memory (with bounds check).
val write_pimem_raw : (int, bits(64)) -> unit
function write_pimem_raw(idx, v) = {
    assert(0 <= idx & idx < 65536, "pimem index out of bounds");
    pimem[idx] = v
}

// Read a raw 64-bit value from instruction memory (with bounds check).
val read_pimem_raw : int -> bits(64)
function read_pimem_raw(idx) = {
    assert(0 <= idx & idx < 65536, "pimem index out of bounds");
    pimem[idx]
}

// Zero a range of instruction memory (for init and program loading).
val pimem_zero_range : (int, int) -> unit
function pimem_zero_range(start, count) = {
    var i : int = start;
    while i < start + count do {
        write_pimem_raw(i, sail_zeros(64));
        i = i + 1
    }
}

// Initialize parser state (called before running a parser program).
val parser_init : unit -> unit
function parser_init() = {
    PR[0] = sail_zeros(128);
    PR[1] = sail_zeros(128);
    PR[2] = sail_zeros(128);
    PR[3] = sail_zeros(128);
    pcursor = sail_zeros(8);
    ppc = sail_zeros(16);
    parser_state = sail_zeros(8);
    parser_halted = false;
    parser_drop = false;
    pflag_z = false;
    pflag_n = false;

    // Reset header metadata
    hdr_present = init_hdr_present();
    hdr_offset = init_hdr_offset();

    // Reset Struct-0 (Standard Metadata)
    struct0 = sail_zeros(128);

    // Reset transition table and NXTP result
    transition_table_init();

    // Reset PSEEK table
    pseek_table_init();

    // Reset MAP registers
    MAP = init_map();

    // Reset instruction memory (first 256 entries — sufficient for test programs)
    pimem_zero_range(0, 256)
}

// Write an encoded instruction into instruction memory at the given index.
val write_pimem : (int, pinstr) -> unit
function write_pimem(idx, instr) = {
    write_pimem_raw(idx, encode_pinstr(instr))
}

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

// Load a program (list of pinstr) into instruction memory.
// Encodes each instruction to binary. Resets ppc to 0.
val parser_load_program : list(pinstr) -> unit
function parser_load_program(instrs) = {
    ppc = sail_zeros(16);
    pimem_zero_range(0, 256);
    parser_load_program_rec(instrs, 0)
}

// Read a byte from the packet header buffer.
// Uses assert to prove the index is in bounds for the type checker.
val read_packet_byte : int -> bits8
function read_packet_byte(idx) = {
    assert(0 <= idx & idx < 256, "packet byte index out of bounds");
    packet_hdr[idx]
}

// Read a range of bits from a 128-bit register value.
// offset and size are in bits. Big-endian: bit 127 is MSB, bit 0 is LSB.
// Returns the extracted bits zero-extended to 128 bits (in the low bits).
// extract_bits and insert_bits accept 'int' for offset/size because Sail's
// type checker cannot always prove non-negativity of intermediate arithmetic.
// The shift and mask functions accept int, and callers using nat (a subtype
// of int) work seamlessly.

val extract_bits : forall 'o 's, 'o >= 0 & 's >= 0. (bits128, int('o), int('s)) -> bits128
function extract_bits(reg_val, offset, size) = {
    let mask : bits128 = sail_mask(128, sail_ones(size));
    sail_shiftright(reg_val, offset) & mask
}

// Write a range of bits into a 128-bit register value.
// Returns the updated 128-bit value.
val insert_bits : forall 'o 's, 'o >= 0 & 's >= 0. (bits128, int('o), int('s), bits128) -> bits128
function insert_bits(reg_val, offset, size, data) = {
    let mask : bits128 = sail_shiftleft(sail_mask(128, sail_ones(size)), offset);
    let cleared = reg_val & not_vec(mask);
    let shifted_data = sail_shiftleft(data & sail_mask(128, sail_ones(size)), offset);
    cleared | shifted_data
}
