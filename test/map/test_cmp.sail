// Tests for MAP CMP and CMPI instructions.

val test_cmp_equal : unit -> unit
function test_cmp_equal() = {
    map_init();
    write_mapword(0, 3, 0x0000000A);
    write_mapword(1, 3, 0x0000000A);
    let _ = mexecute(MCMP(MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000));
    assert(mflag_z == true, "CMP: equal sets Z");
    assert(mflag_c == false, "CMP: equal no borrow")
}

val test_cmp_less : unit -> unit
function test_cmp_less() = {
    map_init();
    write_mapword(0, 3, 0x00000003);
    write_mapword(1, 3, 0x0000000A);
    let _ = mexecute(MCMP(MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000));
    assert(mflag_z == false, "CMP: not equal");
    assert(mflag_c == true, "CMP: borrow when src1 < src2")
}

val test_cmpi_basic : unit -> unit
function test_cmpi_basic() = {
    map_init();
    write_mapword(0, 3, 0x00000042);
    let _ = mexecute(MCMPI(MR0, MW3, 0b00000, 0x0042, 0b01000));
    assert(mflag_z == true, "CMPI: equal sets Z")
}

val main : unit -> unit
function main() = {
    test_cmp_equal();
    test_cmp_less();
    test_cmpi_basic()
}
