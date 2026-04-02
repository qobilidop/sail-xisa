// Tests for MAP ADD and ADDI instructions.

val test_add_basic : unit -> unit
function test_add_basic() = {
    map_init();
    write_mapword(0, 3, 0x0000000A);
    write_mapword(1, 3, 0x00000014);
    // ADD R2.W3, R0.W3[0:8], R1.W3[0:8]
    let _ = mexecute(MADD(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                          MR1, MW3, 0b00000, 0b01000, false, false, false));
    assert(read_mapword(2, 3) == 0x0000001E, "ADD: 10 + 20 = 30")
}

val test_add_flags : unit -> unit
function test_add_flags() = {
    map_init();
    write_mapword(0, 3, 0x7FFFFFFF);
    write_mapword(1, 3, 0x00000001);
    // ADD.F R2.W3, R0.W3[0:32], R1.W3[0:32] — size 0b00000 means 32
    let _ = mexecute(MADD(MR2, MW3, MR0, MW3, 0b00000, 0b00000,
                          MR1, MW3, 0b00000, 0b00000, true, false, false));
    assert(read_mapword(2, 3) == 0x80000000, "ADD.F: 0x7FFFFFFF + 1 = 0x80000000");
    assert(mflag_z == false, "ADD.F: not zero");
    assert(mflag_n == true, "ADD.F: negative (bit 31 set)");
    assert(mflag_v == true, "ADD.F: signed overflow")
}

val test_add_zero_flag : unit -> unit
function test_add_zero_flag() = {
    map_init();
    write_mapword(0, 3, 0x00000000);
    write_mapword(1, 3, 0x00000000);
    let _ = mexecute(MADD(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                          MR1, MW3, 0b00000, 0b01000, true, false, false));
    assert(mflag_z == true, "ADD.F: zero flag set when result is 0")
}

val test_add_short : unit -> unit
function test_add_short() = {
    map_init();
    write_mapword(0, 3, 0xFFFF00FF);
    write_mapword(1, 3, 0x00000001);
    // ADD.SH R0.W3, R0.W3[0:16], R1.W3[0:16]
    let _ = mexecute(MADD(MR0, MW3, MR0, MW3, 0b00000, 0b10000,
                          MR1, MW3, 0b00000, 0b10000, false, false, true));
    assert(read_mapword(0, 3) == 0xFFFF0100, "ADD.SH: only low 16 bits modified")
}

val test_addi_basic : unit -> unit
function test_addi_basic() = {
    map_init();
    write_mapword(0, 3, 0x0000000A);
    let _ = mexecute(MADDI(MR1, MW3, MR0, MW3, 0b00000, 0b01000,
                           0x0005, false, false, false));
    assert(read_mapword(1, 3) == 0x0000000F, "ADDI: 10 + 5 = 15")
}

val test_addi_flags : unit -> unit
function test_addi_flags() = {
    map_init();
    write_mapword(0, 3, 0x000000FF);
    let _ = mexecute(MADDI(MR1, MW3, MR0, MW3, 0b00000, 0b01000,
                           0x0001, true, false, false));
    assert(read_mapword(1, 3) == 0x00000100, "ADDI.F: 255 + 1 = 256")
}

val main : unit -> unit
function main() = {
    test_add_basic();
    test_add_flags();
    test_add_zero_flag();
    test_add_short();
    test_addi_basic();
    test_addi_flags()
}
