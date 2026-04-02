// Tests for MAP logic instructions: AND, OR, XOR, NOT.

val test_and_basic : unit -> unit
function test_and_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000FF);
    write_mapword(1, 3, 0x0000000F);
    let _ = mexecute(MAND(MR2, MW3, MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000, false));
    assert(read_mapword(2, 3) == 0x0000000F, "AND: 0xFF & 0x0F = 0x0F")
}

val test_and_flags : unit -> unit
function test_and_flags() = {
    map_init();
    write_mapword(0, 3, 0x000000FF);
    write_mapword(1, 3, 0x00000000);
    let _ = mexecute(MAND(MR2, MW3, MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000, true));
    assert(mflag_z == true, "AND.F: zero result sets Z");
    assert(mflag_c == false, "AND.F: C cleared");
    assert(mflag_v == false, "AND.F: V cleared")
}

val test_or_basic : unit -> unit
function test_or_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000A0);
    write_mapword(1, 3, 0x0000000B);
    let _ = mexecute(MOR(MR2, MW3, MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000, false));
    assert(read_mapword(2, 3) == 0x000000AB, "OR: 0xA0 | 0x0B = 0xAB")
}

val test_xor_basic : unit -> unit
function test_xor_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000FF);
    write_mapword(1, 3, 0x0000000F);
    let _ = mexecute(MXOR(MR2, MW3, MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000, false));
    assert(read_mapword(2, 3) == 0x000000F0, "XOR: 0xFF ^ 0x0F = 0xF0")
}

val test_not_basic : unit -> unit
function test_not_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000F0);
    let _ = mexecute(MNOT(MR1, MW3, MR0, MW3, 0b00000, 0b01000, false));
    assert(read_mapword(1, 3) == 0x0000000F, "NOT: ~0xF0 (8-bit) = 0x0F")
}

val test_andi_basic : unit -> unit
function test_andi_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000AB);
    let _ = mexecute(MANDI(MR1, MW3, MR0, MW3, 0b00000, 0x000F, 0b01000, false));
    assert(read_mapword(1, 3) == 0x0000000B, "ANDI: 0xAB & 0x0F = 0x0B")
}

val test_ori_basic : unit -> unit
function test_ori_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000A0);
    let _ = mexecute(MORI(MR1, MW3, MR0, MW3, 0b00000, 0x000B, 0b01000, false));
    assert(read_mapword(1, 3) == 0x000000AB, "ORI: 0xA0 | 0x0B = 0xAB")
}

val test_xori_basic : unit -> unit
function test_xori_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000FF);
    let _ = mexecute(MXORI(MR1, MW3, MR0, MW3, 0b00000, 0x00FF, 0b01000, false));
    assert(read_mapword(1, 3) == 0x00000000, "XORI: 0xFF ^ 0xFF = 0")
}

val main : unit -> unit
function main() = {
    test_and_basic();
    test_and_flags();
    test_or_basic();
    test_xor_basic();
    test_not_basic();
    test_andi_basic();
    test_ori_basic();
    test_xori_basic()
}
