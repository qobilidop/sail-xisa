// Parser instruction execution.

// Each instruction adds a clause to this scattered function.
val execute : pinstr -> ExecutionResult

scattered function execute

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
function clause execute(PMOV(rd, dest_offset, rs, src_offset, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
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
function clause execute(PMOVI(rd, dest_offset_bytes, immediate, size_bits)) = {
    let dst_val = read_preg(rd);
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
function clause execute(PADD(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
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
function clause execute(PADDI(rd, rs, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
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
function clause execute(PSUB(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
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
function clause execute(PSUBI(rd, rs, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
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
function clause execute(PSUBII(rd, immediate, rs, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
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
function clause execute(PAND(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
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
function clause execute(PANDI(rd, rs, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
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
function clause execute(POR(rd, dest_offset, rs1, src1_offset, rs2, src2_offset, size_bits)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
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
function clause execute(PORI(rd, rs, immediate, size_bits)) = {
    let src_val = read_preg(rs);
    let dst_val = read_preg(rd);
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
)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
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
)) = {
    let s1_val = read_preg(rs1);
    let s2_val = read_preg(rs2);
    let dst_val = read_preg(rd);
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

// STCI: Cursor += IncrValue.
// Increments the parser cursor by an immediate value (1-256).
// Value is truncated to 8 bits to match cursor width.
function clause execute(PSTCI(incr_value)) = {
    let incr_8 : bits8 = sail_mask(8, incr_value);
    pcursor = pcursor + incr_8;
    RETIRE_SUCCESS
}

end execute
