// Tests for MAP MOV and MOVI instructions.

val test_mov_basic : unit -> unit
function test_mov_basic() = {
    map_init();
    write_mapword(0, 3, 0xDEADBEEF);
    let _ = mexecute(MMOV(MR1, MW3, MR0, MW3, false));
    assert(read_mapword(1, 3) == 0xDEADBEEF, "MOV should copy word")
}

val test_mov_word_select : unit -> unit
function test_mov_word_select() = {
    map_init();
    write_mapword(0, 0, 0x12345678);
    let _ = mexecute(MMOV(MR1, MW2, MR0, MW0, false));
    assert(read_mapword(1, 2) == 0x12345678, "MOV should copy across word positions")
}

val test_mov_cd : unit -> unit
function test_mov_cd() = {
    map_init();
    write_mapreg(1, 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF);
    write_mapword(0, 3, 0x000000AB);
    let _ = mexecute(MMOV(MR1, MW3, MR0, MW3, true));
    assert(read_mapreg(1) == 0x00000000_00000000_00000000_000000AB,
        "MOV.CD should clear entire 16B register then copy word")
}

val test_mov_null_reg : unit -> unit
function test_mov_null_reg() = {
    map_init();
    write_mapword(0, 3, 0xDEADBEEF);
    let _ = mexecute(MMOV(MRN, MW3, MR0, MW3, false));
    assert(read_mapword(15, 3) == 0x00000000, "Null register should always read zero")
}

val test_movi_basic : unit -> unit
function test_movi_basic() = {
    map_init();
    let _ = mexecute(MMOVI(MR0, MW3, 0x00000042, false));
    assert(read_mapword(0, 3) == 0x00000042, "MOVI should load immediate")
}

val test_movi_32bit : unit -> unit
function test_movi_32bit() = {
    map_init();
    let _ = mexecute(MMOVI(MR0, MW0, 0xDEADBEEF, false));
    assert(read_mapword(0, 0) == 0xDEADBEEF, "MOVI should load full 32-bit immediate")
}

val test_movi_cd : unit -> unit
function test_movi_cd() = {
    map_init();
    write_mapreg(0, 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF);
    let _ = mexecute(MMOVI(MR0, MW3, 0x000000AB, true));
    assert(read_mapreg(0) == 0x00000000_00000000_00000000_000000AB,
        "MOVI.CD should clear entire 16B register then load immediate")
}

val main : unit -> unit
function main() = {
    test_mov_basic();
    test_mov_word_select();
    test_mov_cd();
    test_mov_null_reg();
    test_movi_basic();
    test_movi_32bit();
    test_movi_cd()
}
