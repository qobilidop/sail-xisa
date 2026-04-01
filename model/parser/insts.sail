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
    let sz   : nat = unsigned(size_bits);
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
    let sz   : nat = unsigned(size_bits);
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
    let sz   = unsigned(size_bits);
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
        i = i + 1;
    };

    // Shift right to align the extracted bits, then mask to sz bits.
    let shift_amount : int = bytes_needed * 8 - bit_in_byte - sz;
    let extracted : bits128 = sail_shiftright(acc, shift_amount) & sail_mask(128, sail_ones(sz));

    // Write to destination register
    let dst_val : bits128 = if clear_dest then sail_zeros(128) else read_preg(rd);
    let result = insert_bits(dst_val, doff, sz, extracted);
    write_preg(rd, result);
    RETIRE_SUCCESS
}

end execute
