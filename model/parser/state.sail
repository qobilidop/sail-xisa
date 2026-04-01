
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

// Parser program counter.
register ppc : bits16

// Instruction memory: 256 slots of pinstr values.
// No binary encoding — instructions are stored directly.
// Future: replace with byte-level memory + encdec mapping.
val init_pimem : unit -> vector(256, pinstr)
function init_pimem() = [
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
    PNOP(),
]

register pimem : vector(256, pinstr) = init_pimem()

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

// Initialize parser state (called before running a parser program).
val parser_init : unit -> unit
function parser_init() = {
    PR[0] = sail_zeros(128);
    PR[1] = sail_zeros(128);
    PR[2] = sail_zeros(128);
    PR[3] = sail_zeros(128);
    pcursor = sail_zeros(8);
    ppc = sail_zeros(16);
    parser_halted = false;
    parser_drop = false;
    pflag_z = false;
    pflag_n = false;

    // Reset instruction memory to all NOPs
    pimem = init_pimem()
}

// Load a program (list of instructions) into instruction memory starting at address 0.
// Remaining slots are filled with NOP. Resets ppc to 0.
// Write an instruction into instruction memory at the given index.
val write_pimem : (int, pinstr) -> unit
function write_pimem(idx, instr) = {
    assert(0 <= idx & idx < 256, "instruction memory index out of bounds");
    pimem[idx] = instr
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

val parser_load_program : list(pinstr) -> unit
function parser_load_program(instrs) = {
    ppc = sail_zeros(16);
    pimem = init_pimem();
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
