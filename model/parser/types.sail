// Parser register indices.
// The Parser has 4 general-purpose 128-bit registers (R0-R3).

// RN is a null register used when the destination is not needed.
enum pregidx = { PR0, PR1, PR2, PR3, PRN }

// Convert parser register index to numeric index (0-3).
// PRN maps to 0 but writes to PRN are discarded (see state.sail).
val pregidx_to_nat : pregidx -> range(0, 3)
function pregidx_to_nat(r) = match r {
    PR0 => 0,
    PR1 => 1,
    PR2 => 2,
    PR3 => 3,
    PRN => 0,
}

// Is this the null register?
val is_null_reg : pregidx -> bool
function is_null_reg(r) = match r {
    PRN => true,
    _   => false,
}

// Parser instruction union (scattered -- each file adds clauses).
scattered union pinstr

// NOP: No operation.
union clause pinstr = PNOP : unit

// HALT: Terminate parsing. Bool indicates drop (true = HALTDROP).
union clause pinstr = PHALT : bool

// MOV: Copy SizeBits bits from SourceReg at SrcOffset to DestReg at DestOffset.
// Fields: (dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits)
union clause pinstr = PMOV : (pregidx, bits8, pregidx, bits8, bits8)

// MOVI: Load immediate value into DestReg.
// Fields: (dest_reg, dest_offset_bytes, immediate_value, size_bits)
union clause pinstr = PMOVI : (pregidx, bits8, bits16, bits8)

// EXT: Extract data from packet buffer at cursor-relative offset into DestReg.
// Fields: (dest_reg, dest_offset_bits, source_offset_bits, size_bits, clear_dest)
// source_offset_bits is relative to the current cursor position.
// clear_dest corresponds to the .CD optional modifier.
union clause pinstr = PEXT : (pregidx, bits8, bits16, bits8, bool)

end pinstr
