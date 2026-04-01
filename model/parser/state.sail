// Parser general-purpose registers: 4 x 128-bit, big-endian.
register PR : vector(4, bits128)

// Parser cursor position in the packet header buffer.
// Range 0-255 (up to 256 bytes of packet header).
register pcursor : bits8

// Packet header buffer: 256 bytes.
register packet_hdr : vector(256, bits8)

// Parser halted flag.
register parser_halted : bool

// Parser drop flag (set by HALTDROP).
register parser_drop : bool

// Condition flags (set by arithmetic/compare instructions).
register pflag_z : bool  // Zero flag
register pflag_n : bool  // Negative flag

// Read a parser register. PRN always reads as zero.
val read_preg : pregidx -> bits128
function read_preg(r) =
    if is_null_reg(r) then sail_zeros(128)
    else PR[pregidx_to_nat(r)]

// Write a parser register. Writes to PRN are discarded.
val write_preg : (pregidx, bits128) -> unit
function write_preg(r, v) =
    if not_bool(is_null_reg(r)) then PR[pregidx_to_nat(r)] = v

// Initialize parser state (called before running a parser program).
val parser_init : unit -> unit
function parser_init() = {
    PR[0] = sail_zeros(128);
    PR[1] = sail_zeros(128);
    PR[2] = sail_zeros(128);
    PR[3] = sail_zeros(128);
    pcursor = sail_zeros(8);
    parser_halted = false;
    parser_drop = false;
    pflag_z = false;
    pflag_n = false;
}

// Read a range of bits from a 128-bit register value.
// offset and size are in bits. Big-endian: bit 127 is MSB, bit 0 is LSB.
// Returns the extracted bits zero-extended to 128 bits (in the low bits).
val extract_bits : (bits128, nat, nat) -> bits128
function extract_bits(reg_val, offset, size) = {
    let mask : bits128 = sail_mask(128, sail_ones(size));
    sail_shiftright(reg_val, offset) & mask
}

// Write a range of bits into a 128-bit register value.
// Returns the updated 128-bit value.
val insert_bits : (bits128, nat, nat, bits128) -> bits128
function insert_bits(reg_val, offset, size, data) = {
    let mask : bits128 = sail_shiftleft(sail_mask(128, sail_ones(size)), offset);
    let cleared = reg_val & not_vec(mask);
    let shifted_data = sail_shiftleft(data & sail_mask(128, sail_ones(size)), offset);
    cleared | shifted_data
}
