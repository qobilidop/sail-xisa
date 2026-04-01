
// Branch condition codes for BR instructions.
enum pcond = { PCC_EQ, PCC_NEQ, PCC_LT, PCC_GT, PCC_GE, PCC_LE, PCC_AL }

// Bit-test condition codes for BRBTST instructions.
enum pbtcond = { PBT_CLR, PBT_SET }

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

// ADD: Unsigned addition of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits)
union clause pinstr = PADD : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8)

// ADDI: Unsigned addition of register sub-field and immediate.
// Fields: (dest_reg, src_reg, immediate_value, size_bits)
union clause pinstr = PADDI : (pregidx, pregidx, bits16, bits8)

// SUB: Subtraction of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits)
union clause pinstr = PSUB : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8)

// SUBI: Subtraction of immediate from register sub-field.
// Fields: (dest_reg, src_reg, immediate_value, size_bits)
union clause pinstr = PSUBI : (pregidx, pregidx, bits16, bits8)

// SUBII: Subtraction of register sub-field from immediate (reversed).
// Fields: (dest_reg, immediate_value, src_reg, size_bits)
union clause pinstr = PSUBII : (pregidx, bits16, pregidx, bits8)

// AND: Bitwise AND of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits)
union clause pinstr = PAND : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8)

// ANDI: Bitwise AND of register sub-field and immediate.
// Fields: (dest_reg, src_reg, immediate_value, size_bits)
union clause pinstr = PANDI : (pregidx, pregidx, bits16, bits8)

// OR: Bitwise OR of two register sub-fields.
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits)
union clause pinstr = POR : (pregidx, bits8, pregidx, bits8, pregidx, bits8, bits8)

// ORI: Bitwise OR of register sub-field and immediate.
// Fields: (dest_reg, src_reg, immediate_value, size_bits)
union clause pinstr = PORI : (pregidx, pregidx, bits16, bits8)

// CMP: Compare two register sub-fields (subtract, set flags, discard result).
// Fields: (src1_reg, src1_offset_bits, src2_reg, src2_offset_bits, size_bits)
union clause pinstr = PCMP : (pregidx, bits8, pregidx, bits8, bits8)

// CMPIBY: Compare register sub-field (byte offset) with immediate.
// Fields: (src_reg, src_offset_bytes, immediate_value, size_bits)
union clause pinstr = PCMPIBY : (pregidx, bits8, bits16, bits8)

// CMPIBI: Compare register sub-field (bit offset) with immediate.
// Fields: (src_reg, src_offset_bits, immediate_value, size_bits)
union clause pinstr = PCMPIBI : (pregidx, bits8, bits16, bits8)

// CNCTBY: Concatenate from two source registers (byte granularity).
// Fields: (dest_reg, dest_offset_bytes, src1_reg, src1_offset_bytes, src1_size_bytes,
//          src2_reg, src2_offset_bytes, src2_size_bytes)
union clause pinstr = PCNCTBY : (pregidx, bits8, pregidx, bits8, bits8, pregidx, bits8, bits8)

// CNCTBI: Concatenate from two source registers (bit granularity).
// Fields: (dest_reg, dest_offset_bits, src1_reg, src1_offset_bits, src1_size_bits,
//          src2_reg, src2_offset_bits, src2_size_bits)
union clause pinstr = PCNCTBI : (pregidx, bits8, pregidx, bits8, bits8, pregidx, bits8, bits8)

// BR: Branch to address if condition is met.
// Fields: (condition, target_address)
union clause pinstr = PBR : (pcond, bits16)

// BRBTST: Test bit in register and branch if condition is met.
// Fields: (condition, src_reg, bit_offset, target_address)
union clause pinstr = PBRBTST : (pbtcond, pregidx, bits8, bits16)

// STC: Set cursor from register sub-field.
// Cursor += ((SrcReg[offset+size-1:offset] + AdditionalIncr) << SrcShift)
// Fields: (src_reg, src_offset_bits, src_size_bits, src_shift, additional_incr)
union clause pinstr = PSTC : (pregidx, bits8, bits8, bits8, bits8)

// STCI: Set cursor from immediate value.
// Cursor += IncrValue
// Fields: (incr_value)
union clause pinstr = PSTCI : bits16

// STH: Set header present and offset fields at current cursor position.
// Fields: (header_present_id, header_offset_id, halt)
union clause pinstr = PSTH : (bits8, bits8, bool)

// STCH: Set cursor then header fields (STCI + STH compound).
// Fields: (incr_value, header_present_id, header_offset_id, halt)
union clause pinstr = PSTCH : (bits16, bits8, bits8, bool)

// STHC: Set header fields then cursor (STH + STCI compound).
// Fields: (incr_value, header_present_id, header_offset_id)
union clause pinstr = PSTHC : (bits16, bits8, bits8)

// ST: Store register sub-field into Struct-0.
// Fields: (src_reg, src_offset_bits, struct_offset_bits, size_bits, halt)
union clause pinstr = PST : (pregidx, bits8, bits8, bits8, bool)

// STI: Store immediate value into Struct-0.
// Fields: (immediate_value, struct_offset_bits, size_bits)
union clause pinstr = PSTI : (bits16, bits8, bits8)

// EXTMAP: Extract data from packet into a MAP register.
// Fields: (map_reg_idx, dest_offset_bits, packet_offset_bits, size_bits)
union clause pinstr = PEXTMAP : (bits4, bits8, bits16, bits8)

// MOVMAP: Move data from a parser register into a MAP register.
// Fields: (map_reg_idx, dest_offset_bits, src_reg, src_offset_bits, size_bits)
union clause pinstr = PMOVMAP : (bits4, bits8, pregidx, bits8, bits8)

// MOVL: Move left — dest offset = SrcReg2 sub-field + OffsBits1.
// Fields: (dest_reg, src1_reg, offs1, size1, src2_reg, offs2, size2, clear_dest)
union clause pinstr = PMOVL : (pregidx, pregidx, bits8, bits8, pregidx, bits8, bits8, bool)

// MOVLI: Move left immediate — dest offset = ImmValue + OffsBits.
// Fields: (dest_reg, src_reg, offs, size, imm_value, clear_dest)
union clause pinstr = PMOVLI : (pregidx, pregidx, bits8, bits8, bits8, bool)

// MOVLII: Move left immediate with immediate data — dest offset from register, data from immediate.
// Fields: (dest_reg, src_reg, offs, size, imm_value, imm_value_size, clear_dest)
union clause pinstr = PMOVLII : (pregidx, pregidx, bits8, bits8, bits8, bits8, bool)

// MOVR: Move right — dest offset = OffsBits1 - SrcReg2 sub-field.
// Fields: (dest_reg, src1_reg, offs1, size1, src2_reg, offs2, size2, clear_dest)
union clause pinstr = PMOVR : (pregidx, pregidx, bits8, bits8, pregidx, bits8, bits8, bool)

// MOVRI: Move right immediate — dest offset = OffsBits - ImmValue.
// Fields: (dest_reg, src_reg, offs, size, imm_value, clear_dest)
union clause pinstr = PMOVRI : (pregidx, pregidx, bits8, bits8, bits8, bool)

// MOVRII: Move right immediate with immediate data — dest from ImmValueSize - register sub-field.
// Fields: (dest_reg, src_reg, offs, size, imm_value, imm_value_size, clear_dest)
union clause pinstr = PMOVRII : (pregidx, pregidx, bits8, bits8, bits8, bits8, bool)

// NXTP: Calculate next-protocol entry address via transition table lookup.
// Fields: (src_reg, src_offset_bits, size_bits)
union clause pinstr = PNXTP : (pregidx, bits8, bits8)

// BRNS: Branch to next state indicated by a transition rule number.
// Fields: (condition, transition_rule_number)
union clause pinstr = PBRNS : (pcond, bits8)

// BRNXTP: Branch to next-protocol (NXTP result), with JumpMode for no-match.
// Fields: (condition, jump_mode, address_or_rule)
// jump_mode: 000=nop, 001=continue, 010=jump to address, 011=use rule
// address_or_rule: used by mode 010 (as PC address) or 011 (as rule number)
union clause pinstr = PBRNXTP : (pcond, bits8, bits16)

// EXTNXTP: Extract from packet + NXTP lookup.
// Fields: (dest_reg, source_offset_bits, size_bits, clear_dest)
union clause pinstr = PEXTNXTP : (pregidx, bits16, bits8, bool)

// BRBTSTNXTP: Bit test + branch to next protocol (NXTP result).
// Fields: (condition, src_reg, bit_offset, jump_mode, address_or_rule)
union clause pinstr = PBRBTSTNXTP : (pbtcond, pregidx, bits8, bits8, bits16)

// BRBTSTNS: Bit test + branch to next state (transition rule).
// Fields: (condition, src_reg, bit_offset, transition_rule_number)
union clause pinstr = PBRBTSTNS : (pbtcond, pregidx, bits8, bits8)

// PSEEK: Scan over protocol headers to next protocol of interest.
// Fields: (dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits, class_id)
union clause pinstr = PPSEEK : (pregidx, bits8, pregidx, bits8, bits8, bits8)

// PSEEKNXTP: PSEEK + NXTP lookup with final protocol value.
// Fields: (dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits, class_id)
union clause pinstr = PPSEEKNXTP : (pregidx, bits8, pregidx, bits8, bits8, bits8)

end pinstr
