// Tests for MAP shift instructions: SHL, SHLI, SHR, SHRI.

val test_shl_basic : unit -> unit
function test_shl_basic() = {
    map_init();
    // Source1: R0.W3 = 0x0F (4-bit value at offset 0, size 4)
    // Source2: R1.W3 = 4 (shift amount, 5-bit value at offset 0, size 5)
    // Expected: dest gets 0x0F << 4 = 0xF0 at bits [7:4]
    write_mapword(0, 3, 0x0000000F);
    write_mapword(1, 3, 0x00000004);
    let _ = mexecute(MSHL(MR2, MW3, MR0, MW3, 0b00000, 0b00100,
                          MR1, MW3, 0b00000, 0b00101, false, false));
    assert(read_mapword(2, 3) == 0x000000F0, "SHL: 0x0F << 4 = 0xF0")
}

val test_shli_basic : unit -> unit
function test_shli_basic() = {
    map_init();
    // Source1: R0.W3 = 0x0F (4-bit value at offset 0, size 4)
    // Shift immediate: 4
    write_mapword(0, 3, 0x0000000F);
    let _ = mexecute(MSHLI(MR2, MW3, MR0, MW3, 0b00000, 0b00100,
                           0b00100, false, false));
    assert(read_mapword(2, 3) == 0x000000F0, "SHLI: 0x0F << 4 = 0xF0")
}

val test_shr_basic : unit -> unit
function test_shr_basic() = {
    map_init();
    // Source1: R0.W3 = 0xF0 (8-bit value at offset 0, size 8)
    // Source2: R1.W3 = 4 (shift amount)
    // Expected: 0xF0 >> 4 = 0x0F at bits [3:0]
    write_mapword(0, 3, 0x000000F0);
    write_mapword(1, 3, 0x00000004);
    let _ = mexecute(MSHR(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                          MR1, MW3, 0b00000, 0b00101, false, false));
    assert(read_mapword(2, 3) == 0x0000000F, "SHR: 0xF0 >> 4 = 0x0F")
}

val test_shri_basic : unit -> unit
function test_shri_basic() = {
    map_init();
    // Source1: R0.W3 = 0xF0 (8-bit value at offset 0, size 8)
    // Shift immediate: 4
    write_mapword(0, 3, 0x000000F0);
    let _ = mexecute(MSHRI(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                           0b00100, false, false));
    assert(read_mapword(2, 3) == 0x0000000F, "SHRI: 0xF0 >> 4 = 0x0F")
}

val test_shl_cd : unit -> unit
function test_shl_cd() = {
    map_init();
    // Pre-fill dest with 0xFFFFFFFF, then SHL.CD should clear first
    write_mapword(2, 3, 0xFFFFFFFF);
    write_mapword(0, 3, 0x0000000F);
    write_mapword(1, 3, 0x00000004);
    let _ = mexecute(MSHL(MR2, MW3, MR0, MW3, 0b00000, 0b00100,
                          MR1, MW3, 0b00000, 0b00101, false, true));
    assert(read_mapword(2, 3) == 0x000000F0, "SHL.CD: clears dest before write")
}

val test_shr_zero_shift : unit -> unit
function test_shr_zero_shift() = {
    map_init();
    // Shift amount >= size means m <= 0, no write; Z flag set if .F
    write_mapword(0, 3, 0x0000000F);
    write_mapword(1, 3, 0x00000004);  // shift by 4, but size is only 4 -> m = 0
    write_mapword(2, 3, 0xAAAAAAAA);  // should remain unchanged
    let _ = mexecute(MSHR(MR2, MW3, MR0, MW3, 0b00000, 0b00100,
                          MR1, MW3, 0b00000, 0b00101, true, false));
    assert(read_mapword(2, 3) == 0xAAAAAAAA, "SHR: no write when m <= 0");
    assert(mflag_z == true, "SHR.F: Z set when m <= 0")
}

val main : unit -> unit
function main() = {
    test_shl_basic();
    test_shli_basic();
    test_shr_basic();
    test_shri_basic();
    test_shl_cd();
    test_shr_zero_shift()
}
