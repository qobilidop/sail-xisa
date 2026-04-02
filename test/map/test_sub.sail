// Tests for MAP SUB and SUBI instructions.

val test_sub_basic : unit -> unit
function test_sub_basic() = {
    map_init();
    write_mapword(0, 3, 0x00000014);
    write_mapword(1, 3, 0x0000000A);
    let _ = mexecute(MSUB(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                          MR1, MW3, 0b00000, 0b01000, false, false, false));
    assert(read_mapword(2, 3) == 0x0000000A, "SUB: 20 - 10 = 10")
}

val test_sub_flags_borrow : unit -> unit
function test_sub_flags_borrow() = {
    map_init();
    write_mapword(0, 3, 0x00000003);
    write_mapword(1, 3, 0x00000005);
    let _ = mexecute(MSUB(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                          MR1, MW3, 0b00000, 0b01000, true, false, false));
    assert(mflag_c == true, "SUB.F: borrow when A < B");
    assert(mflag_n == true, "SUB.F: negative result")
}

val test_subi_basic : unit -> unit
function test_subi_basic() = {
    map_init();
    write_mapword(0, 3, 0x0000000F);
    let _ = mexecute(MSUBI(MR1, MW3, MR0, MW3, 0b00000, 0b01000,
                           0x0005, false, false, false));
    assert(read_mapword(1, 3) == 0x0000000A, "SUBI: 15 - 5 = 10")
}

val main : unit -> unit
function main() = {
    test_sub_basic();
    test_sub_flags_borrow();
    test_subi_basic()
}
