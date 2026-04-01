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

end execute
