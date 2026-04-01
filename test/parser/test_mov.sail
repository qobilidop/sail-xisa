// Tests for MOV and MOVI instructions.
//
// Per the XISA spec (Section 3.12.11):
//   MOV: DestReg[i:j] = SourceReg[k:l]
//     j = DestOffsetBits (range 0-127)
//     l = SrcOffsetBits (range 0-127)
//     i = DestOffsetBits + SizeBits (range 1-128)
//     k = SrcOffsetBits + SizeBits (range 1-128)
//
//   MOVI: DestReg[i:j] = ImmediateValue[k-1:0]
//     j = DestOffsetBytes * 8
//     i = (DestOffsetBytes * 8) + SizeBits
//     k = SizeBits
//     DestOffsetBytes range 0-15, SizeBits range 1-16

val test_mov_full_register : unit -> unit
function test_mov_full_register() = {
    parser_init();
    PR[0] = 0xAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD;
    PR[1] = sail_zeros(128);

    // MOV R1, 0, R0, 0, 128 -- copy all 128 bits
    let _ = execute(PMOV(PR1, 0x00, PR0, 0x00, 0x80));

    assert(PR[1] == 0xAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD, "MOV should copy full register");
    assert(PR[0] == 0xAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD, "MOV should not modify source register")
}

val test_mov_partial_bits : unit -> unit
function test_mov_partial_bits() = {
    parser_init();

    // Source: R0 has 0xFF in bits [7:0]
    PR[0] = 0x00000000_00000000_00000000_000000FF;
    PR[1] = sail_zeros(128);

    // MOV R1, dest_offset=8, R0, src_offset=0, size=8
    // Copies R0[7:0] into R1[15:8]
    let _ = execute(PMOV(PR1, 0x08, PR0, 0x00, 0x08));

    assert(PR[1] == 0x00000000_00000000_00000000_0000FF00, "MOV should copy bits to correct offset in destination")
}

val test_mov_to_null_register : unit -> unit
function test_mov_to_null_register() = {
    parser_init();
    PR[0] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;

    // MOV to null register should be discarded
    let result = execute(PMOV(PRN, 0x00, PR0, 0x00, 0x80));

    assert(result == RETIRE_SUCCESS, "MOV to PRN should succeed");

    // PRN reads as zero, and underlying PR[0] should be unchanged
    assert(PR[0] == 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, "MOV to null register should not corrupt other registers")
}

val test_mov_preserves_other_bits : unit -> unit
function test_mov_preserves_other_bits() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0x11111111_11111111_11111111_11111100;

    // MOV R1, dest_offset=0, R0, src_offset=0, size=8
    // Should only overwrite R1[7:0], leaving R1[127:8] unchanged.
    let _ = execute(PMOV(PR1, 0x00, PR0, 0x00, 0x08));

    assert(PR[1] == 0x11111111_11111111_11111111_111111AB, "MOV should only overwrite the target bit range")
}

val test_movi_load_immediate : unit -> unit
function test_movi_load_immediate() = {
    parser_init();
    PR[0] = sail_zeros(128);

    // MOVI R0, dest_offset_bytes=0, immediate=0xABCD, size_bits=16
    // Loads 0xABCD into R0[15:0]
    let _ = execute(PMOVI(PR0, 0x00, 0xABCD, 0x10));

    assert(PR[0] == 0x00000000_00000000_00000000_0000ABCD, "MOVI should load immediate into low bits")
}

val test_movi_with_byte_offset : unit -> unit
function test_movi_with_byte_offset() = {
    parser_init();
    PR[0] = sail_zeros(128);

    // MOVI R0, dest_offset_bytes=2, immediate=0x00FF, size_bits=8
    // dest_offset_bits = 2 * 8 = 16, so loads into R0[23:16]
    let _ = execute(PMOVI(PR0, 0x02, 0x00FF, 0x08));

    assert(PR[0] == 0x00000000_00000000_00000000_00FF0000, "MOVI should load at correct byte offset")
}

val main : unit -> unit
function main() = {
    test_mov_full_register();
    test_mov_partial_bits();
    test_mov_to_null_register();
    test_mov_preserves_other_bits();
    test_movi_load_immediate();
    test_movi_with_byte_offset()
}
