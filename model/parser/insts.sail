// Parser instruction execution.

// Each instruction adds a clause to this scattered function.
val execute : pinstr -> ExecutionResult

scattered function execute

// Extract a protocol field from the packet at an absolute byte offset with a given bit size.
// Used by the PSEEK scan loop to read next-protocol fields from packet headers.
val pseek_extract_proto : (int, nat) -> bits16
function pseek_extract_proto(byte_offset, size_bits) = {
    let bit_offset : int = byte_offset * 8;
    let pbo_bv : bits(20) = get_slice_int(20, bit_offset, 0);
    let start_byte = unsigned(sail_shiftright(pbo_bv, 3));
    let bit_in_byte = unsigned(pbo_bv & 0x00007);

    let sum_bv : bits(20) = get_slice_int(20, bit_in_byte + size_bits + 7, 0);
    let bytes_needed = unsigned(sail_shiftright(sum_bv, 3));

    var acc : bits128 = sail_zeros(128);
    var i : int = 0;
    while i < bytes_needed do {
        let bidx : int = start_byte + i;
        let bval : bits128 = sail_zero_extend(read_packet_byte(bidx), 128);
        acc = acc | sail_shiftleft(bval, 8 * (bytes_needed - 1 - i));
        i = i + 1
    };

    let shift_amount : int = bytes_needed * 8 - bit_in_byte - size_bits;
    let extracted : bits128 = sail_shiftright(acc, shift_amount) & sail_mask(128, sail_ones(size_bits));
    sail_mask(16, extracted)
}

// NOP: No operation. Does nothing, returns success.
function clause execute(PNOP()) = RETIRE_SUCCESS

// HALT: Terminate parsing.
// PHALT(false) = HALT -- stop parsing, hand off to MAP.
// PHALT(true)  = HALTDROP -- stop parsing, drop the packet.
function clause execute(PHALT(drop)) = {
    parser_halted = true;
    if drop then {
        parser_drop = true;
        RETIRE_DROP
    } else {
        RETIRE_HALT
    }
}

// MOV: DestReg[dest_offset + size - 1 : dest_offset] = SourceReg[src_offset + size - 1 : src_offset]
// Bit-field copy between registers. Other bits in destination are preserved.
function clause execute(PMOV(rd, dest_offset, rs, src_offset, size_bits, clear_dest)) = {
    let src_val = read_preg(rs);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let doff : nat = unsigned(dest_offset);
    let soff : nat = unsigned(src_offset);
    let sz : nat = unsigned(size_bits);
    let extracted = extract_bits(src_val, soff, sz);
    let result = insert_bits(dst_val, doff, sz, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVI: DestReg[(dest_offset_bytes*8) + size_bits - 1 : (dest_offset_bytes*8)] = immediate[size_bits-1:0]
// Load an immediate value (up to 16 bits) into a register at a byte-aligned offset.
function clause execute(PMOVI(rd, dest_offset_bytes, immediate, size_bits, clear_dest)) = {
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let doff : nat = unsigned(dest_offset_bytes) * 8;
    let sz : nat = unsigned(size_bits);
    let imm_128 : bits128 = sail_zero_extend(immediate, 128);
    let result = insert_bits(dst_val, doff, sz, imm_128);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// EXT: Extract data from packet buffer into a register.
// DestReg[dest_offset + size - 1 : dest_offset] = Packet[cursor*8 + src_offset + size - 1 : cursor*8 + src_offset]
//
// The source offset is in bits, relative to the cursor position (which is in bytes).
// Data is extracted from the packet in big-endian order.
// If clear_dest is true (.CD modifier), the destination register is cleared before extraction.
function clause execute(PEXT(rd, dest_offset, src_offset_bits, size_bits, clear_dest)) = {
    let doff = unsigned(dest_offset);
    let soff = unsigned(src_offset_bits);
    let sz = unsigned(size_bits);
    let cursor_bit_offset = unsigned(pcursor) * 8;
    let packet_bit_offset = cursor_bit_offset + soff;

    // Compute byte index and bit-within-byte using bitvector shift/mask (avoids int division).
    let pbo_bv : bits(20) = get_slice_int(20, packet_bit_offset, 0);
    let start_byte = unsigned(sail_shiftright(pbo_bv, 3));
    let bit_in_byte = unsigned(pbo_bv & 0x00007);

    // bytes_needed = ceil((bit_in_byte + sz) / 8)
    let sum_bv : bits(20) = get_slice_int(20, bit_in_byte + sz + 7, 0);
    let bytes_needed = unsigned(sail_shiftright(sum_bv, 3));

    // Accumulate bytes into a 128-bit value (big-endian).
    var acc : bits128 = sail_zeros(128);
    var i : int = 0;
    while i < bytes_needed do {
        let byte_idx : int = start_byte + i;
        let byte_val : bits128 = sail_zero_extend(read_packet_byte(byte_idx), 128);

        // Place this byte: first byte is most significant
        acc = acc | sail_shiftleft(byte_val, 8 * (bytes_needed - 1 - i));
        i = i + 1
    };

    // Shift right to align the extracted bits, then mask to sz bits.
    let shift_amount : int = bytes_needed * 8 - bit_in_byte - sz;
    let extracted : bits128 = sail_shiftright(acc, shift_amount) & sail_mask(128, sail_ones(sz));

    // Write to destination register
    let dst_val : bits128 = if clear_dest then {
            sail_zeros(128)
        } else {
            read_preg(rd)
        };
    let result = insert_bits(dst_val, doff, sz, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// ADD: DestReg[dest_off + sz - 1 : dest_off] = Src1Reg[s1_off...] + Src2Reg[s2_off...]
// Unsigned 16-bit addition. Sets Z flag.
function clause execute(PADD(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits, clear_dest)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let doff : nat = unsigned(dest_offset);
    let s1off : nat = unsigned(src1_offset);
    let s2off : nat = unsigned(src2_offset);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(s1_val, s1off, sz);
    let op2 = extract_bits(s2_val, s2off, sz);
    let sum : bits128 = sail_mask(128, sail_ones(sz)) & (op1 + op2);
    pflag_z = sum == sail_zeros(128);
    let result = insert_bits(dst_val, doff, sz, sum);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// ADDI: DestReg[sz - 1 : 0] = SrcReg[sz - 1 : 0] + ImmediateValue
// Unsigned addition with immediate. Sets Z flag.
function clause execute(PADDI(rd, rs, immediate, size_bits, clear_dest)) = {
    let src_val = read_preg(rs);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, 0, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let sum : bits128 = sail_mask(128, sail_ones(sz)) & (op1 + op2);
    pflag_z = sum == sail_zeros(128);
    let result = insert_bits(dst_val, 0, sz, sum);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// SUB: DestReg[dest_off + sz - 1 : dest_off] = Src1Reg[s1_off...] - Src2Reg[s2_off...]
// 16-bit subtraction. Sets Z and N flags.
function clause execute(PSUB(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits, clear_dest)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let doff : nat = unsigned(dest_offset);
    let s1off : nat = unsigned(src1_offset);
    let s2off : nat = unsigned(src2_offset);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(s1_val, s1off, sz);
    let op2 = extract_bits(s2_val, s2off, sz);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & sub_bits(op1, op2);
    pflag_z = diff == sail_zeros(128);
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    let result = insert_bits(dst_val, doff, sz, diff);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// SUBI: DestReg[sz - 1 : 0] = SrcReg[sz - 1 : 0] - ImmediateValue
function clause execute(PSUBI(rd, rs, immediate, size_bits, clear_dest)) = {
    let src_val = read_preg(rs);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, 0, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & sub_bits(op1, op2);
    pflag_z = diff == sail_zeros(128);
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    let result = insert_bits(dst_val, 0, sz, diff);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// SUBII: DestReg[sz - 1 : 0] = ImmediateValue - SrcReg[sz - 1 : 0]
function clause execute(PSUBII(rd, immediate, rs, size_bits, clear_dest)) = {
    let src_val = read_preg(rs);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let sz : nat = unsigned(size_bits);
    let op1 : bits128 = sail_zero_extend(immediate, 128);
    let op2 = extract_bits(src_val, 0, sz);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & sub_bits(op1, op2);
    pflag_z = diff == sail_zeros(128);
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    let result = insert_bits(dst_val, 0, sz, diff);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// AND: DestReg[dest_off + sz - 1 : dest_off] = Src1Reg[s1_off...] & Src2Reg[s2_off...]
// Bitwise AND. Sets Z flag.
function clause execute(PAND(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits, clear_dest)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let doff : nat = unsigned(dest_offset);
    let s1off : nat = unsigned(src1_offset);
    let s2off : nat = unsigned(src2_offset);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(s1_val, s1off, sz);
    let op2 = extract_bits(s2_val, s2off, sz);
    let res : bits128 = op1 & op2;
    pflag_z = res == sail_zeros(128);
    let result = insert_bits(dst_val, doff, sz, res);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// ANDI: DestReg[sz - 1 : 0] = SrcReg[sz - 1 : 0] & ImmediateValue
function clause execute(PANDI(rd, rs, immediate, size_bits, clear_dest)) = {
    let src_val = read_preg(rs);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, 0, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let res : bits128 = op1 & op2;
    pflag_z = res == sail_zeros(128);
    let result = insert_bits(dst_val, 0, sz, res);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// OR: DestReg[dest_off + sz - 1 : dest_off] = Src1Reg[s1_off...] | Src2Reg[s2_off...]
// Bitwise OR. Sets Z flag.
function clause execute(POR(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits, clear_dest)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let doff : nat = unsigned(dest_offset);
    let s1off : nat = unsigned(src1_offset);
    let s2off : nat = unsigned(src2_offset);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(s1_val, s1off, sz);
    let op2 = extract_bits(s2_val, s2off, sz);
    let res : bits128 = op1 | op2;
    pflag_z = res == sail_zeros(128);
    let result = insert_bits(dst_val, doff, sz, res);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// ORI: DestReg[sz - 1 : 0] = SrcReg[sz - 1 : 0] | ImmediateValue
function clause execute(PORI(rd, rs, immediate, size_bits, clear_dest)) = {
    let src_val = read_preg(rs);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, 0, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let res : bits128 = op1 | op2;
    pflag_z = res == sail_zeros(128);
    let result = insert_bits(dst_val, 0, sz, res);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// CMP: Compare two register sub-fields. Sets Z and N flags. Does not store result.
function clause execute(PCMP(rs1, src1_offset, rs2, src2_offset, size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let s1off : nat = unsigned(src1_offset);
    let s2off : nat = unsigned(src2_offset);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(s1_val, s1off, sz);
    let op2 = extract_bits(s2_val, s2off, sz);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & sub_bits(op1, op2);
    pflag_z = diff == sail_zeros(128);
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    RETIRE_SUCCESS
}

// CMPIBY: Compare register sub-field (byte offset) with immediate.
function clause execute(PCMPIBY(rs, src_offset_bytes, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bytes) * 8;
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, soff, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & sub_bits(op1, op2);
    pflag_z = diff == sail_zeros(128);
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    RETIRE_SUCCESS
}

// CMPIBI: Compare register sub-field (bit offset) with immediate.
function clause execute(PCMPIBI(rs, src_offset_bits, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let sz : nat = unsigned(size_bits);
    let op1 = extract_bits(src_val, soff, sz);
    let op2 : bits128 = sail_zero_extend(immediate, 128);
    let diff : bits128 = sail_mask(128, sail_ones(sz)) & sub_bits(op1, op2);
    pflag_z = diff == sail_zeros(128);
    pflag_n = (sail_shiftright(diff, sz - 1) & sail_mask(128, 0x01)) != sail_zeros(128);
    RETIRE_SUCCESS
}

// CNCTBY: Concatenate from two source registers (byte granularity).
// Src1 at higher bits, Src2 at lower bits.
function clause execute(PCNCTBY(
    rd,
    dest_offset_bytes,
    rs1,
    src1_offset_bytes,
    src1_size_bytes,
    rs2,
    src2_offset_bytes,
    src2_size_bytes,
    clear_dest,
)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let doff : nat = unsigned(dest_offset_bytes) * 8;
    let s1off : nat = unsigned(src1_offset_bytes) * 8;
    let s1sz : nat = unsigned(src1_size_bytes) * 8;
    let s2off : nat = unsigned(src2_offset_bytes) * 8;
    let s2sz : nat = unsigned(src2_size_bytes) * 8;
    let part1 = extract_bits(s1_val, s1off, s1sz);
    let part2 = extract_bits(s2_val, s2off, s2sz);
    let combined : bits128 = sail_shiftleft(part1, s2sz) | part2;
    let total_sz : nat = s1sz + s2sz;
    let result = insert_bits(dst_val, doff, total_sz, combined);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// CNCTBI: Concatenate from two source registers (bit granularity).
function clause execute(PCNCTBI(
    rd,
    dest_offset_bits,
    rs1,
    src1_offset_bits,
    src1_size_bits,
    rs2,
    src2_offset_bits,
    src2_size_bits,
    clear_dest,
)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let doff : nat = unsigned(dest_offset_bits);
    let s1off : nat = unsigned(src1_offset_bits);
    let s1sz : nat = unsigned(src1_size_bits);
    let s2off : nat = unsigned(src2_offset_bits);
    let s2sz : nat = unsigned(src2_size_bits);
    let part1 = extract_bits(s1_val, s1off, s1sz);
    let part2 = extract_bits(s2_val, s2off, s2sz);
    let combined : bits128 = sail_shiftleft(part1, s2sz) | part2;
    let total_sz : nat = s1sz + s2sz;
    let result = insert_bits(dst_val, doff, total_sz, combined);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// BR: Branch to target address if condition is met.
// Updates ppc when the branch is taken.
function clause execute(PBR(cc, target)) = {
    if eval_pcond(cc) then {
        ppc = target
    };
    RETIRE_SUCCESS
}

// BRBTST: Test a single bit in a register and branch if condition is met.
// PBT_CLR branches if the bit is 0, PBT_SET branches if the bit is 1.
function clause execute(PBRBTST(btcc, rs, bit_offset, target)) = {
    let src_val = read_preg(rs);
    let boff : nat = unsigned(bit_offset);
    let bit_val = extract_bits(src_val, boff, 1);
    let bit_is_set = bit_val != sail_zeros(128);
    let take_branch : bool = match btcc {
        PBT_CLR => not_bool(bit_is_set),
        PBT_SET => bit_is_set,
    };
    if take_branch then {
        ppc = target
    };
    RETIRE_SUCCESS
}

// STC: Cursor += ((SrcReg[offset+size-1:offset] + AdditionalIncr) << SrcShift)
// Extracts 1-8 bits from a register sub-field, adds AdditionalIncr,
// left-shifts by SrcShift, and adds the result to the cursor.
function clause execute(PSTC(rs, src_offset_bits, src_size_bits, src_shift, additional_incr)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let sz : nat = unsigned(src_size_bits);
    let extracted = extract_bits(src_val, soff, sz);
    let base : bits8 = sail_mask(8, extracted) + sail_mask(8, additional_incr);
    let shift_amount : nat = unsigned(src_shift);
    let shifted : bits8 = sail_shiftleft(base, shift_amount);
    pcursor = pcursor + shifted;
    RETIRE_SUCCESS
}

// STCI: Cursor += IncrValue.
// Increments the parser cursor by an immediate value (1-256).
// Value is truncated to 8 bits to match cursor width.
function clause execute(PSTCI(incr_value)) = {
    let incr_8 : bits8 = sail_mask(8, incr_value);
    pcursor = pcursor + incr_8;
    RETIRE_SUCCESS
}

// STH: Set header present and offset fields.
// Optionally halt (.H modifier) after setting the header.
function clause execute(PSTH(present_id, offset_id, halt)) = {
    set_hdr(present_id, offset_id);
    if halt then {
        parser_halted = true;
        RETIRE_HALT
    } else {
        RETIRE_SUCCESS
    }
}

// STCH: Increment cursor, then set header (STCI + STH compound).
// The header offset records the NEW cursor position (after increment).
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

// STHC: Set header at current cursor, then increment cursor (STH + STCI compound).
// The header offset records the OLD cursor position (before increment).
function clause execute(PSTHC(incr_value, present_id, offset_id)) = {
    set_hdr(present_id, offset_id);
    let incr_8 : bits8 = sail_mask(8, incr_value);
    pcursor = pcursor + incr_8;
    RETIRE_SUCCESS
}

// ST: Struct0[struct_off + size - 1 : struct_off] = SrcReg[src_off + size - 1 : src_off]
// Copies a bit-field from a parser register into Struct-0.
// Optionally halt (.H modifier) after the store.
function clause execute(PST(rs, src_offset_bits, struct_offset_bits, size_bits, halt)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let doff : nat = unsigned(struct_offset_bits);
    let sz : nat = unsigned(size_bits);
    let extracted = extract_bits(src_val, soff, sz);
    struct0 = insert_bits(struct0, doff, sz, extracted);
    if halt then {
        parser_halted = true;
        RETIRE_HALT
    } else {
        RETIRE_SUCCESS
    }
}

// STI: Struct0[struct_off + size - 1 : struct_off] = ImmediateValue[size-1:0]
// Stores an immediate value (up to 16 bits) into Struct-0.
function clause execute(PSTI(immediate, struct_offset_bits, size_bits)) = {
    let doff : nat = unsigned(struct_offset_bits);
    let sz : nat = unsigned(size_bits);
    let imm_128 : bits128 = sail_zero_extend(immediate, 128);
    struct0 = insert_bits(struct0, doff, sz, imm_128);
    RETIRE_SUCCESS
}

// EXTMAP: MAPReg[dest_off + size - 1 : dest_off] = Packet[cursor*8 + pkt_off + size - 1 : cursor*8 + pkt_off]
// Same extraction logic as EXT, but writes to a MAP register.
function clause execute(PEXTMAP(map_idx, dest_offset, pkt_offset_bits, size_bits)) = {
    let midx : int = unsigned(map_idx);
    let doff = unsigned(dest_offset);
    let soff = unsigned(pkt_offset_bits);
    let sz = unsigned(size_bits);
    let cursor_bit_offset = unsigned(pcursor) * 8;
    let packet_bit_offset = cursor_bit_offset + soff;

    // Compute byte index and bit-within-byte (same as EXT).
    let pbo_bv : bits(20) = get_slice_int(20, packet_bit_offset, 0);
    let start_byte = unsigned(sail_shiftright(pbo_bv, 3));
    let bit_in_byte = unsigned(pbo_bv & 0x00007);

    // bytes_needed = ceil((bit_in_byte + sz) / 8)
    let sum_bv : bits(20) = get_slice_int(20, bit_in_byte + sz + 7, 0);
    let bytes_needed = unsigned(sail_shiftright(sum_bv, 3));

    // Accumulate bytes into a 128-bit value (big-endian).
    var acc : bits128 = sail_zeros(128);
    var i : int = 0;
    while i < bytes_needed do {
        let byte_idx : int = start_byte + i;
        let byte_val : bits128 = sail_zero_extend(read_packet_byte(byte_idx), 128);
        acc = acc | sail_shiftleft(byte_val, 8 * (bytes_needed - 1 - i));
        i = i + 1
    };

    // Shift right to align the extracted bits, then mask to sz bits.
    let shift_amount : int = bytes_needed * 8 - bit_in_byte - sz;
    let extracted : bits128 = sail_shiftright(acc, shift_amount) & sail_mask(128, sail_ones(sz));

    // Write to MAP register
    let dst_val = read_mapreg(midx);
    let result = insert_bits(dst_val, doff, sz, extracted);
    write_mapreg(midx, result);
    RETIRE_SUCCESS
}

// MOVMAP: MAPReg[dest_off + size - 1 : dest_off] = SrcReg[src_off + size - 1 : src_off]
// Copies a bit-field from a parser register into a MAP register.
function clause execute(PMOVMAP(map_idx, dest_offset, rs, src_offset, size_bits)) = {
    let midx : int = unsigned(map_idx);
    let doff : nat = unsigned(dest_offset);
    let soff : nat = unsigned(src_offset);
    let sz : nat = unsigned(size_bits);

    let src_val = read_preg(rs);
    let extracted = extract_bits(src_val, soff, sz);

    let dst_val = read_mapreg(midx);
    let result = insert_bits(dst_val, doff, sz, extracted);
    write_mapreg(midx, result);
    RETIRE_SUCCESS
}

// MOVL: DestReg[m:k] = SrcReg1[i1:j1]
// k = SrcReg2[i2:j2] + OffsBits1 (dynamic offset, shift left)
// m = k + SizeBits1 - 1
function clause execute(PMOVL(rd, rs1, offs1, size1, rs2, offs2, size2, clear_dest)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let o1 : nat = unsigned(offs1);
    let sz1 : nat = unsigned(size1);
    let o2 : nat = unsigned(offs2);
    let sz2 : nat = unsigned(size2);
    let dynamic_offset : nat = unsigned(extract_bits(s2_val, o2, sz2));
    let k : nat = dynamic_offset + o1;
    let extracted = extract_bits(s1_val, o1, sz1);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, k, sz1, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVLI: DestReg[m:k] = SrcReg[i:j]
// k = ImmValue + OffsBits (immediate offset, shift left)
// m = k + SizeBits - 1
function clause execute(PMOVLI(rd, rs, offs, size_bits, imm_value, clear_dest)) = {
    let src_val = read_preg(rs);
    let o : nat = unsigned(offs);
    let sz : nat = unsigned(size_bits);
    let imm : nat = unsigned(imm_value);
    let k : nat = imm + o;
    let extracted = extract_bits(src_val, o, sz);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, k, sz, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVLII: DestReg[m-1:k] = ImmValue[n-1:0]
// k = SrcReg[i:j] (register sub-field is the dest offset)
// m = k + ImmValueSize
function clause execute(PMOVLII(rd, rs, offs, size_bits, imm_value, imm_value_size, clear_dest)) = {
    let src_val = read_preg(rs);
    let o : nat = unsigned(offs);
    let sz : nat = unsigned(size_bits);
    let imm_sz : nat = unsigned(imm_value_size);
    let k : nat = unsigned(extract_bits(src_val, o, sz));
    let imm_128 : bits128 = sail_zero_extend(sail_mask(128, imm_value), 128);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, k, imm_sz, imm_128);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVR: DestReg[m:k] = SrcReg1[i1:j1]
// k = OffsBits1 - SrcReg2[i2:j2] (dynamic offset, shift right)
// m = k + SizeBits1 - 1
function clause execute(PMOVR(rd, rs1, offs1, size1, rs2, offs2, size2, clear_dest)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let o1 : nat = unsigned(offs1);
    let sz1 : nat = unsigned(size1);
    let o2 : nat = unsigned(offs2);
    let sz2 : nat = unsigned(size2);
    let dynamic_offset : nat = unsigned(extract_bits(s2_val, o2, sz2));
    let k : int = o1 - dynamic_offset;
    let k_clamped : nat = if k < 0 then 0 else k;
    let extracted = extract_bits(s1_val, o1, sz1);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, k_clamped, sz1, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVRI: DestReg[m:k] = SrcReg[i:j]
// k = OffsBits - ImmValue (immediate offset, shift right)
// m = k + SizeBits - 1
function clause execute(PMOVRI(rd, rs, offs, size_bits, imm_value, clear_dest)) = {
    let src_val = read_preg(rs);
    let o : nat = unsigned(offs);
    let sz : nat = unsigned(size_bits);
    let imm : nat = unsigned(imm_value);
    let k : int = o - imm;
    let k_clamped : nat = if k < 0 then 0 else k;
    let extracted = extract_bits(src_val, o, sz);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, k_clamped, sz, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// MOVRII: DestReg[m-1:0] = ImmValue[n-1:k]
// k = SrcReg[i:j] (register sub-field)
// m = ImmValueSize - SrcReg[i:j]
function clause execute(PMOVRII(rd, rs, offs, size_bits, imm_value, imm_value_size, clear_dest)) = {
    let src_val = read_preg(rs);
    let o : nat = unsigned(offs);
    let sz : nat = unsigned(size_bits);
    let imm_sz : nat = unsigned(imm_value_size);
    let reg_offset : nat = unsigned(extract_bits(src_val, o, sz));
    let data_size : int = imm_sz - reg_offset;
    let data_size_nat : nat = if data_size < 0 then 0 else data_size;
    // Extract from ImmValue starting at bit reg_offset, for data_size_nat bits
    let imm_128 : bits128 = sail_zero_extend(sail_mask(128, imm_value), 128);
    let extracted = extract_bits(imm_128, reg_offset, data_size_nat);
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, 0, data_size_nat, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// NXTP: Extract protocol key from register, look up in transition table.
// Stores result in nxtp_result_pc/nxtp_result_state/nxtp_matched.
function clause execute(PNXTP(rs, src_offset_bits, size_bits)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let sz : nat = unsigned(size_bits);
    let extracted = extract_bits(src_val, soff, sz);
    // Protocol key is up to 24 bits — truncate to bits24.
    let key : bits24 = sail_mask(24, extracted);
    nxtp_matched = transition_lookup(parser_state, key);
    RETIRE_SUCCESS
}

// BRNS: Branch to the next-state PC from a specific transition rule.
// Updates parser_state and ppc if condition is met.
function clause execute(PBRNS(cc, rule_num)) = {
    if eval_pcond(cc) then {
        let idx : int = unsigned(rule_num);
        ppc = read_tt_next_pc(idx);
        parser_state = read_tt_next_state(idx)
    };
    RETIRE_SUCCESS
}

// BRNXTP: Branch to next-protocol entry point (from NXTP result).
// JumpMode controls behavior when NXTP had no match.
// jump_mode encoding: 000=nop, 001=continue, 010=jump to address, 011=use rule
function clause execute(PBRNXTP(cc, jump_mode, addr_or_rule)) = {
    if eval_pcond(cc) then {
        if nxtp_matched then {
            // Match: branch to NXTP result
            ppc = nxtp_result_pc;
            parser_state = nxtp_result_state
        } else {
            // No match: follow JumpMode
            let mode : int = unsigned(jump_mode);
            if mode == 0 then {
                // 000: No jump
                ()
            } else if mode == 1 then {
                // 001: Continue to next instruction
                ()
            } else if mode == 2 then {
                // 010: Jump to explicit address
                ppc = addr_or_rule
            } else if mode == 3 then {
                // 011: Transition to state from specified rule
                let idx : int = unsigned(addr_or_rule);
                ppc = read_tt_next_pc(idx);
                parser_state = read_tt_next_state(idx)
            } else {
                // 100 (trap) and others: not yet supported
                ()
            }
        }
    };
    RETIRE_SUCCESS
}

// EXTNXTP: Extract data from packet into register, then NXTP lookup with extracted key.
// Combines EXT (at dest offset 0) + NXTP in one instruction. Size limited to 1-24 bits.
function clause execute(PEXTNXTP(rd, src_offset_bits, size_bits, clear_dest)) = {
    let soff = unsigned(src_offset_bits);
    let sz = unsigned(size_bits);
    let cursor_bit_offset = unsigned(pcursor) * 8;
    let packet_bit_offset = cursor_bit_offset + soff;

    // Packet extraction logic (same as EXT)
    let pbo_bv : bits(20) = get_slice_int(20, packet_bit_offset, 0);
    let start_byte = unsigned(sail_shiftright(pbo_bv, 3));
    let bit_in_byte = unsigned(pbo_bv & 0x00007);

    let sum_bv : bits(20) = get_slice_int(20, bit_in_byte + sz + 7, 0);
    let bytes_needed = unsigned(sail_shiftright(sum_bv, 3));

    var acc : bits128 = sail_zeros(128);
    var i : int = 0;
    while i < bytes_needed do {
        let byte_idx : int = start_byte + i;
        let byte_val : bits128 = sail_zero_extend(read_packet_byte(byte_idx), 128);
        acc = acc | sail_shiftleft(byte_val, 8 * (bytes_needed - 1 - i));
        i = i + 1
    };

    let shift_amount : int = bytes_needed * 8 - bit_in_byte - sz;
    let extracted : bits128 = sail_shiftright(acc, shift_amount) & sail_mask(128, sail_ones(sz));

    // Write to destination register at offset 0
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, 0, sz, extracted);
    write_preg(rd, result);

    // NXTP: use extracted value as transition key (up to 24 bits)
    let key : bits24 = sail_mask(24, extracted);
    nxtp_matched = transition_lookup(parser_state, key);
    RETIRE_SUCCESS
}

// BRBTSTNXTP: Test bit in register, branch to next protocol if condition met.
// Combines BRBTST condition check + BRNXTP branch logic.
function clause execute(PBRBTSTNXTP(btcc, rs, bit_offset, jump_mode, addr_or_rule)) = {
    let src_val = read_preg(rs);
    let boff : nat = unsigned(bit_offset);
    let bit_val = extract_bits(src_val, boff, 1);
    let bit_is_set = bit_val != sail_zeros(128);
    let take_branch : bool = match btcc {
        PBT_CLR => not_bool(bit_is_set),
        PBT_SET => bit_is_set,
    };
    if take_branch then {
        if nxtp_matched then {
            ppc = nxtp_result_pc;
            parser_state = nxtp_result_state
        } else {
            let mode : int = unsigned(jump_mode);
            if mode == 0 then {
                ()
            } else if mode == 1 then {
                ()
            } else if mode == 2 then {
                ppc = addr_or_rule
            } else if mode == 3 then {
                let idx : int = unsigned(addr_or_rule);
                ppc = read_tt_next_pc(idx);
                parser_state = read_tt_next_state(idx)
            } else {
                ()
            }
        }
    };
    RETIRE_SUCCESS
}

// BRBTSTNS: Test bit in register, branch to next state from transition rule if condition met.
// Combines BRBTST condition check + BRNS branch logic.
function clause execute(PBRBTSTNS(btcc, rs, bit_offset, rule_num)) = {
    let src_val = read_preg(rs);
    let boff : nat = unsigned(bit_offset);
    let bit_val = extract_bits(src_val, boff, 1);
    let bit_is_set = bit_val != sail_zeros(128);
    let take_branch : bool = match btcc {
        PBT_CLR => not_bool(bit_is_set),
        PBT_SET => bit_is_set,
    };
    if take_branch then {
        let idx : int = unsigned(rule_num);
        ppc = read_tt_next_pc(idx);
        parser_state = read_tt_next_state(idx)
    };
    RETIRE_SUCCESS
}

// PSEEK: Scan forward through packet headers, skipping protocols in the PSEEK table.
// Advances cursor past each matched header. Stores final (unmatched) protocol in DestReg.
function clause execute(PPSEEK(rd, dest_offset_bits, rs, src_offset_bits, size_bits, class_id)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let sz : nat = unsigned(size_bits);
    let doff : nat = unsigned(dest_offset_bits);

    // Extract initial protocol value from source register
    let initial = extract_bits(src_val, soff, sz);
    var proto : bits16 = sail_mask(16, initial);
    var current_size : nat = sz;

    // Scan loop: keep skipping while protocol matches a PSEEK entry
    var scanning : bool = true;
    while scanning do {
        let entry_idx = pseek_lookup(class_id, proto);
        if entry_idx < 0 then {
            // No match — stop scanning
            scanning = false
        } else {
            // Match: advance cursor by header length
            let hdr_len : bits8 = read_pseek_hdr_length(entry_idx);
            pcursor = pcursor + hdr_len;
            // Extract next protocol from packet
            let next_off : int = unsigned(pcursor) + unsigned(read_pseek_next_proto_off(entry_idx));
            let next_sz : nat = unsigned(read_pseek_next_proto_size(entry_idx));
            proto = pseek_extract_proto(next_off, next_sz);
            current_size = next_sz
        }
    };

    // Store final protocol value in DestReg at DestOffsetBits
    let dst_val = read_preg(rd);
    let proto_128 : bits128 = sail_zero_extend(proto, 128);
    let result = insert_bits(dst_val, doff, current_size, proto_128);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

// PSEEKNXTP: PSEEK scan + NXTP lookup with final protocol value.
function clause execute(PPSEEKNXTP(rd, dest_offset_bits, rs, src_offset_bits, size_bits, class_id)) = {
    let src_val = read_preg(rs);
    let soff : nat = unsigned(src_offset_bits);
    let sz : nat = unsigned(size_bits);
    let doff : nat = unsigned(dest_offset_bits);

    // Extract initial protocol value from source register
    let initial = extract_bits(src_val, soff, sz);
    var proto : bits16 = sail_mask(16, initial);
    var current_size : nat = sz;

    // Scan loop (same as PSEEK)
    var scanning : bool = true;
    while scanning do {
        let entry_idx = pseek_lookup(class_id, proto);
        if entry_idx < 0 then {
            scanning = false
        } else {
            let hdr_len : bits8 = read_pseek_hdr_length(entry_idx);
            pcursor = pcursor + hdr_len;
            let next_off : int = unsigned(pcursor) + unsigned(read_pseek_next_proto_off(entry_idx));
            let next_sz : nat = unsigned(read_pseek_next_proto_size(entry_idx));
            proto = pseek_extract_proto(next_off, next_sz);
            current_size = next_sz
        }
    };

    // Store final protocol value in DestReg
    let dst_val = read_preg(rd);
    let proto_128 : bits128 = sail_zero_extend(proto, 128);
    let result = insert_bits(dst_val, doff, current_size, proto_128);
    write_preg(rd, result);

    // NXTP lookup with final protocol
    let key : bits24 = sail_zero_extend(proto, 24);
    nxtp_matched = transition_lookup(parser_state, key);
    RETIRE_SUCCESS
}

end execute
