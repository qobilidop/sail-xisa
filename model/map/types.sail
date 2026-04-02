
// MAP ISA types: register indices, word select, conditions, instruction union.

// MAP register indices (4-bit, 0-15).
enum mregidx = { MR0, MR1, MR2, MR3, MR4, MR5, MR6, MR7,
                 MR8, MR9, MR10, MR11, MR12, MR13, MR14, MRN }

val mregidx_to_nat : mregidx -> range(0, 15)
function mregidx_to_nat(r) = match r {
    MR0  => 0,  MR1  => 1,  MR2  => 2,  MR3  => 3,
    MR4  => 4,  MR5  => 5,  MR6  => 6,  MR7  => 7,
    MR8  => 8,  MR9  => 9,  MR10 => 10, MR11 => 11,
    MR12 => 12, MR13 => 13, MR14 => 14, MRN  => 15,
}

// Word select within a 128-bit register (2-bit, 0-3).
// Word 0 = MSW (bits 127:96), Word 3 = LSW (bits 31:0).
enum mwordsel = { MW0, MW1, MW2, MW3 }

val mwordsel_to_nat : mwordsel -> range(0, 3)
function mwordsel_to_nat(w) = match w {
    MW0 => 0, MW1 => 1, MW2 => 2, MW3 => 3,
}

// Branch condition codes (4-bit).
enum mcond = {
    MCC_EQ,    // Z = 1
    MCC_NEQ,   // Z = 0
    MCC_LT,    // N = 1
    MCC_GT,    // N = 0 and Z = 0
    MCC_GE,    // N = 0
    MCC_LE,    // N = 1 or Z = 1
    MCC_C,     // C = 1
    MCC_NC,    // C = 0
    MCC_V,     // V = 1
    MCC_NV,    // V = 0
    MCC_AL,    // Always
}

// Bit-test condition for BRBTST.
enum mbtcond = { MBT_CLR, MBT_SET }

// MAP instruction union (scattered).
scattered union minstr

// NOP: No operation.
union clause minstr = MNOP : unit

// HALT: End MAP execution.
union clause minstr = MHALT : unit

// MOV: Copy 4B word. Fields: (dest_reg, dest_word, src_reg, src_word, clear_dest)
union clause minstr = MMOV : (mregidx, mwordsel, mregidx, mwordsel, bool)

// MOVI: Load immediate into 4B word.
// Fields: (dest_reg, dest_word, immediate32, clear_dest)
union clause minstr = MMOVI : (mregidx, mwordsel, bits(32), bool)

// ADD: Dest[N:0] = Src1[i1:j1] + Src2[i2:j2]
// Fields: (dest_reg, dest_word, src1_reg, src1_word, src1_offset, src1_size,
//          src2_reg, src2_word, src2_offset, src2_size, set_flags, sign_extend, short_mode)
union clause minstr = MADD : (mregidx, mwordsel, mregidx, mwordsel, bits(5), bits(5),
                              mregidx, mwordsel, bits(5), bits(5), bool, bool, bool)

// ADDI: Dest[N:0] = Src1[i1:j1] + ImmediateValue
// Fields: (dest_reg, dest_word, src1_reg, src1_word, src1_offset, src1_size,
//          immediate16, set_flags, sign_extend, short_mode)
union clause minstr = MADDI : (mregidx, mwordsel, mregidx, mwordsel, bits(5), bits(5),
                               bits16, bool, bool, bool)

// SUB: Dest[N:0] = Src1[i1:j1] - Src2[i2:j2]
// Fields: same as ADD
union clause minstr = MSUB : (mregidx, mwordsel, mregidx, mwordsel, bits(5), bits(5),
                              mregidx, mwordsel, bits(5), bits(5), bool, bool, bool)

// SUBI: Dest[N:0] = Src1[i1:j1] - ImmediateValue
// Fields: same as ADDI
union clause minstr = MSUBI : (mregidx, mwordsel, mregidx, mwordsel, bits(5), bits(5),
                               bits16, bool, bool, bool)

// CMP: Compare two register sub-fields. Always sets Z and C flags. Result discarded.
// Fields: (src1_reg, src1_word, src1_offset, src2_reg, src2_word, src2_offset, size)
union clause minstr = MCMP : (mregidx, mwordsel, bits(5), mregidx, mwordsel, bits(5), bits(5))

// CMPI: Compare register sub-field with immediate.
// Fields: (src1_reg, src1_word, src1_offset, immediate16, size)
union clause minstr = MCMPI : (mregidx, mwordsel, bits(5), bits16, bits(5))

// AND: Dest[Size-1:0] = Src1[i1:j1] & Src2[i2:j2]
// Fields: (dest_reg, dest_word, src1_reg, src1_word, src1_offset,
//          src2_reg, src2_word, src2_offset, size, set_flags)
union clause minstr = MAND : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                              mregidx, mwordsel, bits(5), bits(5), bool)

// ANDI: Dest[Size-1:0] = Src1[i1:j1] & ImmediateValue
// Fields: (dest_reg, dest_word, src1_reg, src1_word, src1_offset,
//          immediate16, size, set_flags)
union clause minstr = MANDI : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                               bits16, bits(5), bool)

// OR: Dest[Size-1:0] = Src1[i1:j1] | Src2[i2:j2]
// Fields: same as AND
union clause minstr = MOR : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                             mregidx, mwordsel, bits(5), bits(5), bool)

// ORI: Dest[Size-1:0] = Src1[i1:j1] | ImmediateValue
// Fields: same as ANDI
union clause minstr = MORI : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                              bits16, bits(5), bool)

// XOR: Dest[Size-1:0] = Src1[i1:j1] ^ Src2[i2:j2]
// Fields: same as AND
union clause minstr = MXOR : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                              mregidx, mwordsel, bits(5), bits(5), bool)

// XORI: Dest[Size-1:0] = Src1[i1:j1] ^ ImmediateValue
// Fields: same as ANDI
union clause minstr = MXORI : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                               bits16, bits(5), bool)

// NOT: Dest[Size-1:0] = ~Src[i:j]
// Fields: (dest_reg, dest_word, src_reg, src_word, src_offset, size, set_flags)
union clause minstr = MNOT : (mregidx, mwordsel, mregidx, mwordsel, bits(5), bits(5), bool)

// BR: Branch to address in register if condition met (absolute address).
// Fields: (condition, src_reg, src_word)
union clause minstr = MBR : (mcond, mregidx, mwordsel)

// BRI: Branch to PC-relative offset if condition met.
// Fields: (condition, offset16)
union clause minstr = MBRI : (mcond, bits16)

// BRBTST: Test bit in register word and branch.
// Fields: (bit_test_cond, src_reg, src_word, bit_offset, target16)
union clause minstr = MBRBTST : (mbtcond, mregidx, mwordsel, bits(5), bits16)

end minstr
