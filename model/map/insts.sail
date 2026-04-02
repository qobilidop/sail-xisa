
// MAP instruction execution.

val mexecute : minstr -> ExecutionResult
scattered function mexecute

// Extract a bit-field from a 32-bit word and zero-extend to 32 bits.
// When size == 0, treat as 32 (full word) since 32 cannot fit in 5 bits.
val map_extract : (bits(32), nat, nat) -> bits(32)
function map_extract(word, offset, size) = {
    let sz : nat = if size == 0 then 32 else size;
    let shifted = sail_mask(32, sail_shiftright(sail_zero_extend(word, 64), offset));
    shifted & sail_mask(32, sail_ones(sz))
}

// Extract and sign-extend a bit-field from a 32-bit word to 32 bits.
// When size == 0, treat as 32 (full word) since 32 cannot fit in 5 bits.
val map_extract_sx : (bits(32), nat, nat) -> bits(32)
function map_extract_sx(word, offset, size) = {
    let sz : nat = if size == 0 then 32 else size;
    let extracted = map_extract(word, offset, sz);
    let sign_bit = sail_shiftright(extracted, sz - 1) & 0x00000001;
    if sign_bit == 0x00000001 then {
        let sign_mask : bits(32) = not_vec(sail_mask(32, sail_ones(sz)));
        extracted | sign_mask
    } else {
        extracted
    }
}

// Write result to destination word.
// Normal mode: writes full 32-bit word.
// Short mode (.SH): writes only low 16 bits, preserving upper 16.
val map_write_result : (int, int, bits(32), bool) -> unit
function map_write_result(rd_idx, rw_idx, result, short_mode) = {
    if short_mode then {
        let existing = read_mapword(rd_idx, rw_idx);
        let merged = (existing & 0xFFFF0000) | (result & 0x0000FFFF);
        write_mapword(rd_idx, rw_idx, merged)
    } else {
        write_mapword(rd_idx, rw_idx, result)
    }
}

// Set ZNCV flags for addition.
val map_set_flags_add : (bits(32), bits(32), bits(32), bool) -> unit
function map_set_flags_add(op1, op2, result, short_mode) = {
    let n : nat = if short_mode then 15 else 31;
    mflag_z = result == 0x00000000;
    mflag_n = (sail_shiftright(result, n) & 0x00000001) == 0x00000001;
    let wide_sum : bits(64) = sail_zero_extend(op1, 64) + sail_zero_extend(op2, 64);
    let limit : nat = if short_mode then 16 else 32;
    mflag_c = (sail_shiftright(wide_sum, limit) & sail_zero_extend(0x00000001 : bits(32), 64)) != sail_zeros(64);
    let a_sign = sail_shiftright(op1, n) & 0x00000001;
    let b_sign = sail_shiftright(op2, n) & 0x00000001;
    let r_sign = sail_shiftright(result, n) & 0x00000001;
    mflag_v = (a_sign == b_sign) & (r_sign != a_sign)
}

// Set ZNCV flags for subtraction (A - B).
val map_set_flags_sub : (bits(32), bits(32), bits(32), bool) -> unit
function map_set_flags_sub(op1, op2, result, short_mode) = {
    let n : nat = if short_mode then 15 else 31;
    mflag_z = result == 0x00000000;
    mflag_n = (sail_shiftright(result, n) & 0x00000001) == 0x00000001;
    mflag_c = unsigned(op1) < unsigned(op2);
    let a_sign = sail_shiftright(op1, n) & 0x00000001;
    let b_sign = sail_shiftright(op2, n) & 0x00000001;
    let r_sign = sail_shiftright(result, n) & 0x00000001;
    mflag_v = (a_sign != b_sign) & (r_sign != a_sign)
}

// Set ZNCV flags for logic operations.
val map_set_flags_logic : bits(32) -> unit
function map_set_flags_logic(result) = {
    mflag_z = result == 0x00000000;
    mflag_n = (sail_shiftright(result, 31) & 0x00000001) == 0x00000001;
    mflag_c = false;
    mflag_v = false
}

// NOP: No operation.
function clause mexecute(MNOP()) = RETIRE_SUCCESS

// HALT: End MAP execution.
function clause mexecute(MHALT()) = {
    map_halted = true;
    RETIRE_HALT
}

// MOV: Copy 4B word from source to destination.
// If clear_dest, clear the entire 16B destination register first.
function clause mexecute(MMOV(rd, rw, rs, sw, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let rs_idx = mregidx_to_nat(rs);
    let sw_idx = mwordsel_to_nat(sw);
    if clear_dest then write_mapreg(rd_idx, sail_zeros(128));
    let val32 = read_mapword(rs_idx, sw_idx);
    write_mapword(rd_idx, rw_idx, val32);
    RETIRE_SUCCESS
}

// MOVI: Load immediate (up to 32b) into a 4B word.
// If clear_dest, clear the entire 16B destination register first.
function clause mexecute(MMOVI(rd, rw, imm32, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    if clear_dest then write_mapreg(rd_idx, sail_zeros(128));
    write_mapword(rd_idx, rw_idx, imm32);
    RETIRE_SUCCESS
}

// ADD: Dest[N:0] = Source1[i1:j1] + Source2[i2:j2]
function clause mexecute(MADD(rd, rw, rs1, sw1, s1off, s1sz, rs2, sw2, s2off, s2sz,
                              set_flags, sign_extend, short_mode)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let w2 = read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2));
    let op1 : bits(32) = if sign_extend then map_extract_sx(w1, unsigned(s1off), unsigned(s1sz))
                          else map_extract(w1, unsigned(s1off), unsigned(s1sz));
    let op2 : bits(32) = if sign_extend then map_extract_sx(w2, unsigned(s2off), unsigned(s2sz))
                          else map_extract(w2, unsigned(s2off), unsigned(s2sz));
    let mask : bits(32) = if short_mode then 0x0000FFFF else 0xFFFFFFFF;
    let result : bits(32) = (op1 + op2) & mask;
    if set_flags then map_set_flags_add(op1, op2, result, short_mode);
    map_write_result(rd_idx, rw_idx, result, short_mode);
    RETIRE_SUCCESS
}

// ADDI: Dest[N:0] = Source1[i1:j1] + ImmediateValue
function clause mexecute(MADDI(rd, rw, rs1, sw1, s1off, s1sz, imm16,
                               set_flags, sign_extend, short_mode)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let op1 : bits(32) = if sign_extend then map_extract_sx(w1, unsigned(s1off), unsigned(s1sz))
                          else map_extract(w1, unsigned(s1off), unsigned(s1sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let mask : bits(32) = if short_mode then 0x0000FFFF else 0xFFFFFFFF;
    let result : bits(32) = (op1 + op2) & mask;
    if set_flags then map_set_flags_add(op1, op2, result, short_mode);
    map_write_result(rd_idx, rw_idx, result, short_mode);
    RETIRE_SUCCESS
}

// SUB: Dest[N:0] = Source1[i1:j1] - Source2[i2:j2]
function clause mexecute(MSUB(rd, rw, rs1, sw1, s1off, s1sz, rs2, sw2, s2off, s2sz,
                              set_flags, sign_extend, short_mode)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let w2 = read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2));
    let op1 : bits(32) = if sign_extend then map_extract_sx(w1, unsigned(s1off), unsigned(s1sz))
                          else map_extract(w1, unsigned(s1off), unsigned(s1sz));
    let op2 : bits(32) = if sign_extend then map_extract_sx(w2, unsigned(s2off), unsigned(s2sz))
                          else map_extract(w2, unsigned(s2off), unsigned(s2sz));
    let mask : bits(32) = if short_mode then 0x0000FFFF else 0xFFFFFFFF;
    let result : bits(32) = sub_bits(op1, op2) & mask;
    if set_flags then map_set_flags_sub(op1, op2, result, short_mode);
    map_write_result(rd_idx, rw_idx, result, short_mode);
    RETIRE_SUCCESS
}

// SUBI: Dest[N:0] = Source1[i1:j1] - ImmediateValue
function clause mexecute(MSUBI(rd, rw, rs1, sw1, s1off, s1sz, imm16,
                               set_flags, sign_extend, short_mode)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let op1 : bits(32) = if sign_extend then map_extract_sx(w1, unsigned(s1off), unsigned(s1sz))
                          else map_extract(w1, unsigned(s1off), unsigned(s1sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let mask : bits(32) = if short_mode then 0x0000FFFF else 0xFFFFFFFF;
    let result : bits(32) = sub_bits(op1, op2) & mask;
    if set_flags then map_set_flags_sub(op1, op2, result, short_mode);
    map_write_result(rd_idx, rw_idx, result, short_mode);
    RETIRE_SUCCESS
}

// CMP: Compare. Always sets Z and C flags. Result discarded.
function clause mexecute(MCMP(rs1, sw1, s1off, rs2, sw2, s2off, sz)) = {
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let w2 = read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2));
    let op1 = map_extract(w1, unsigned(s1off), unsigned(sz));
    let op2 = map_extract(w2, unsigned(s2off), unsigned(sz));
    let result : bits(32) = sub_bits(op1, op2);
    mflag_z = result == 0x00000000;
    mflag_c = unsigned(op1) < unsigned(op2);
    RETIRE_SUCCESS
}

// CMPI: Compare with immediate. Always sets Z and C flags.
function clause mexecute(MCMPI(rs1, sw1, s1off, imm16, sz)) = {
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let op1 = map_extract(w1, unsigned(s1off), unsigned(sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let result : bits(32) = sub_bits(op1, op2);
    mflag_z = result == 0x00000000;
    mflag_c = unsigned(op1) < unsigned(op2);
    RETIRE_SUCCESS
}

// AND: Dest[Size-1:0] = Src1[i1:j1] & Src2[i2:j2]
function clause mexecute(MAND(rd, rw, rs1, sw1, s1off, rs2, sw2, s2off, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 = map_extract(read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2)), unsigned(s2off), unsigned(sz));
    let result : bits(32) = op1 & op2;
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// ANDI: Dest[Size-1:0] = Src1[i1:j1] & ImmediateValue
function clause mexecute(MANDI(rd, rw, rs1, sw1, s1off, imm16, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let result : bits(32) = op1 & op2;
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// OR: Dest[Size-1:0] = Src1[i1:j1] | Src2[i2:j2]
function clause mexecute(MOR(rd, rw, rs1, sw1, s1off, rs2, sw2, s2off, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 = map_extract(read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2)), unsigned(s2off), unsigned(sz));
    let result : bits(32) = op1 | op2;
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// ORI: Dest[Size-1:0] = Src1[i1:j1] | ImmediateValue
function clause mexecute(MORI(rd, rw, rs1, sw1, s1off, imm16, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let result : bits(32) = op1 | op2;
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// XOR: Dest[Size-1:0] = Src1[i1:j1] ^ Src2[i2:j2]
function clause mexecute(MXOR(rd, rw, rs1, sw1, s1off, rs2, sw2, s2off, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 = map_extract(read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2)), unsigned(s2off), unsigned(sz));
    let result : bits(32) = xor_vec(op1, op2);
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// XORI: Dest[Size-1:0] = Src1[i1:j1] ^ ImmediateValue
function clause mexecute(MXORI(rd, rw, rs1, sw1, s1off, imm16, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let result : bits(32) = xor_vec(op1, op2);
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// NOT: Dest[Size-1:0] = ~Src[i:j]
function clause mexecute(MNOT(rd, rw, rs, sw, soff, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs), mwordsel_to_nat(sw)), unsigned(soff), unsigned(sz));
    let result : bits(32) = not_vec(op1) & sail_mask(32, sail_ones(unsigned(sz)));
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// Evaluate a MAP branch condition.
val eval_mcond : mcond -> bool
function eval_mcond(cc) = match cc {
    MCC_EQ  => mflag_z,
    MCC_NEQ => not_bool(mflag_z),
    MCC_LT  => mflag_n,
    MCC_GT  => not_bool(mflag_n) & not_bool(mflag_z),
    MCC_GE  => not_bool(mflag_n),
    MCC_LE  => mflag_n | mflag_z,
    MCC_C   => mflag_c,
    MCC_NC  => not_bool(mflag_c),
    MCC_V   => mflag_v,
    MCC_NV  => not_bool(mflag_v),
    MCC_AL  => true,
}

// BR: Branch to absolute address in register if condition met.
function clause mexecute(MBR(cc, rs, sw)) = {
    if eval_mcond(cc) then {
        let target = read_mapword(mregidx_to_nat(rs), mwordsel_to_nat(sw));
        mpc = sail_mask(16, target)
    };
    RETIRE_SUCCESS
}

// BRI: Branch to PC-relative offset if condition met.
function clause mexecute(MBRI(cc, offset)) = {
    if eval_mcond(cc) then {
        mpc = mpc + offset
    };
    RETIRE_SUCCESS
}

// BRBTST: Test bit in register word and branch.
function clause mexecute(MBRBTST(btcc, rs, sw, bit_offset, target)) = {
    let word = read_mapword(mregidx_to_nat(rs), mwordsel_to_nat(sw));
    let bit_val = (sail_shiftright(word, unsigned(bit_offset)) & 0x00000001) == 0x00000001;
    let take_branch : bool = match btcc {
        MBT_CLR => not_bool(bit_val),
        MBT_SET => bit_val,
    };
    if take_branch then mpc = target;
    RETIRE_SUCCESS
}

// SHL: Shift left. Dest[m:k] = Source1 << shift_amount
// k = shift_amount, m = k + Source1Size
// If m <= 0 or m > 32: no write, Z flag set when .F
function clause mexecute(MSHL(rd, rw, rs1, sw1, s1off, s1sz, rs2, sw2, s2off, s2sz,
                              set_flags, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let src_val = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)),
                              unsigned(s1off), unsigned(s1sz));
    let shift_val = map_extract(read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2)),
                                unsigned(s2off), unsigned(s2sz));
    let k : nat = unsigned(shift_val);
    let src_size : nat = unsigned(s1sz);
    let m : int = k + src_size;
    if clear_dest then write_mapword(rd_idx, rw_idx, 0x00000000);
    if m > 0 & m <= 32 then {
        let shifted : bits(32) = sail_shiftleft(src_val, k);
        let existing = read_mapword(rd_idx, rw_idx);
        let write_mask : bits(32) = sail_shiftleft(sail_mask(32, sail_ones(src_size)), k);
        let result = (existing & not_vec(write_mask)) | (shifted & write_mask);
        write_mapword(rd_idx, rw_idx, result);
        if set_flags then map_set_flags_logic(shifted)
    } else {
        if set_flags then { mflag_z = true; mflag_n = false; mflag_c = false; mflag_v = false }
    };
    RETIRE_SUCCESS
}

// SHLI: Shift left immediate.
function clause mexecute(MSHLI(rd, rw, rs1, sw1, s1off, s1sz, shift_imm,
                               set_flags, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let src_val = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)),
                              unsigned(s1off), unsigned(s1sz));
    let k : nat = unsigned(shift_imm);
    let src_size : nat = unsigned(s1sz);
    let m : int = k + src_size;
    if clear_dest then write_mapword(rd_idx, rw_idx, 0x00000000);
    if m > 0 & m <= 32 then {
        let shifted : bits(32) = sail_shiftleft(src_val, k);
        let existing = read_mapword(rd_idx, rw_idx);
        let write_mask : bits(32) = sail_shiftleft(sail_mask(32, sail_ones(src_size)), k);
        let result = (existing & not_vec(write_mask)) | (shifted & write_mask);
        write_mapword(rd_idx, rw_idx, result);
        if set_flags then map_set_flags_logic(shifted)
    } else {
        if set_flags then { mflag_z = true; mflag_n = false; mflag_c = false; mflag_v = false }
    };
    RETIRE_SUCCESS
}

// SHR: Shift right. Dest[m:0] = Source1 >> shift_amount
// k = shift_amount, m = Source1Size - k
function clause mexecute(MSHR(rd, rw, rs1, sw1, s1off, s1sz, rs2, sw2, s2off, s2sz,
                              set_flags, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let src_val = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)),
                              unsigned(s1off), unsigned(s1sz));
    let shift_val = map_extract(read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2)),
                                unsigned(s2off), unsigned(s2sz));
    let k : nat = unsigned(shift_val);
    let src_size : nat = unsigned(s1sz);
    let m : int = src_size - k;
    if clear_dest then write_mapword(rd_idx, rw_idx, 0x00000000);
    if m > 0 then {
        let shifted : bits(32) = sail_shiftright(src_val, k);
        let existing = read_mapword(rd_idx, rw_idx);
        assert(m > 0);
        let write_mask : bits(32) = sail_mask(32, sail_ones(m));
        let result = (existing & not_vec(write_mask)) | (shifted & write_mask);
        write_mapword(rd_idx, rw_idx, result);
        if set_flags then map_set_flags_logic(shifted)
    } else {
        if set_flags then { mflag_z = true; mflag_n = false; mflag_c = false; mflag_v = false }
    };
    RETIRE_SUCCESS
}

// SHRI: Shift right immediate.
function clause mexecute(MSHRI(rd, rw, rs1, sw1, s1off, s1sz, shift_imm,
                               set_flags, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let src_val = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)),
                              unsigned(s1off), unsigned(s1sz));
    let k : nat = unsigned(shift_imm);
    let src_size : nat = unsigned(s1sz);
    let m : int = src_size - k;
    if clear_dest then write_mapword(rd_idx, rw_idx, 0x00000000);
    if m > 0 then {
        let shifted : bits(32) = sail_shiftright(src_val, k);
        let existing = read_mapword(rd_idx, rw_idx);
        assert(m > 0);
        let write_mask : bits(32) = sail_mask(32, sail_ones(m));
        let result = (existing & not_vec(write_mask)) | (shifted & write_mask);
        write_mapword(rd_idx, rw_idx, result);
        if set_flags then map_set_flags_logic(shifted)
    } else {
        if set_flags then { mflag_z = true; mflag_n = false; mflag_c = false; mflag_v = false }
    };
    RETIRE_SUCCESS
}

// CONCAT: DestReg[m:k] = (Src2 << Src1Size) | Src1
function clause mexecute(MCONCAT(rd, rw, doff, rs1, sw1, s1off, s1sz,
                                 rs2, sw2, s2off, s2sz, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let part1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)),
                            unsigned(s1off), unsigned(s1sz));
    let part2 = map_extract(read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2)),
                            unsigned(s2off), unsigned(s2sz));
    let combined : bits(32) = sail_shiftleft(part2, unsigned(s1sz)) | part1;
    let total_size : nat = unsigned(s1sz) + unsigned(s2sz);
    let dest_off : nat = unsigned(doff);
    if clear_dest then write_mapword(rd_idx, rw_idx, 0x00000000);
    let existing = read_mapword(rd_idx, rw_idx);
    let write_mask : bits(32) = sail_shiftleft(sail_mask(32, sail_ones(total_size)), dest_off);
    let placed : bits(32) = sail_shiftleft(combined & sail_mask(32, sail_ones(total_size)), dest_off);
    write_mapword(rd_idx, rw_idx, (existing & not_vec(write_mask)) | placed);
    RETIRE_SUCCESS
}

// FFI: Find first non-zero field.
// Scans a 32-bit value for the first non-zero field of a given size.
// Result: DestReg[4:0] = field offset, DestReg[11:8] = field content.
// Z flag set if not found.
function clause mexecute(MFFI(rd, rw, vr, vw, ore, ow, field_size_imm, scan_dir)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let value = read_mapword(mregidx_to_nat(vr), mwordsel_to_nat(vw));
    let start_offset : nat = unsigned(read_mapword(mregidx_to_nat(ore), mwordsel_to_nat(ow)) & 0x0000001F);
    let fsz : nat = unsigned(field_size_imm) + 1;

    var found : bool = false;
    var result_offset : int = 0;
    var result_content : bits(32) = 0x00000000;

    // Use a simple bit-extraction approach: shift and mask
    let field_mask : bits(32) = sail_mask(32, sail_ones(fsz));
    if scan_dir then {
        // LSb to MSb: scan upward from start_offset
        var pos : int = start_offset;
        while pos + fsz <= 32 & not_bool(found) do {
            let field_val : bits(32) = sail_shiftright(value, pos) & field_mask;
            if field_val != 0x00000000 then {
                found = true;
                result_offset = pos;
                result_content = field_val
            };
            pos = pos + fsz
        }
    } else {
        // MSb to LSb: scan downward from start_offset
        var pos : int = start_offset;
        while pos >= 0 & not_bool(found) do {
            let field_start : int = pos - fsz + 1;
            if field_start >= 0 then {
                let field_val : bits(32) = sail_shiftright(value, field_start) & field_mask;
                if field_val != 0x00000000 then {
                    found = true;
                    result_offset = field_start;
                    result_content = field_val
                }
            };
            pos = pos - fsz
        }
    };

    if found then {
        let offset_bits : bits(32) = get_slice_int(32, result_offset, 0);
        let dest_val : bits(32) = (sail_shiftleft(result_content & 0x0000000F, 8)) |
                                  (offset_bits & 0x0000001F);
        write_mapword(rd_idx, rw_idx, dest_val);
        mflag_z = false
    } else {
        mflag_z = true
    };
    RETIRE_SUCCESS
}

end mexecute
