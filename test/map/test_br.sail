// Tests for MAP branch instructions.

val test_br_unconditional : unit -> unit
function test_br_unconditional() = {
    map_init();
    write_mapword(0, 3, 0x00000042);
    let _ = mexecute(MBR(MCC_AL, MR0, MW3));
    assert(mpc == 0x0042, "BR AL: should jump to R0.W3 value")
}

val test_br_eq_taken : unit -> unit
function test_br_eq_taken() = {
    map_init();
    mflag_z = true;
    write_mapword(0, 3, 0x00000010);
    let _ = mexecute(MBR(MCC_EQ, MR0, MW3));
    assert(mpc == 0x0010, "BR EQ: should branch when Z=1")
}

val test_br_eq_not_taken : unit -> unit
function test_br_eq_not_taken() = {
    map_init();
    mflag_z = false;
    write_mapword(0, 3, 0x00000010);
    let _ = mexecute(MBR(MCC_EQ, MR0, MW3));
    assert(mpc == 0x0000, "BR EQ: should not branch when Z=0")
}

val test_bri_relative : unit -> unit
function test_bri_relative() = {
    map_init();
    mpc = 0x0010;
    let _ = mexecute(MBRI(MCC_AL, 0x0005));
    assert(mpc == 0x0015, "BRI: should add offset to PC")
}

val test_br_gt : unit -> unit
function test_br_gt() = {
    map_init();
    mflag_n = false;
    mflag_z = false;
    write_mapword(0, 3, 0x00000020);
    let _ = mexecute(MBR(MCC_GT, MR0, MW3));
    assert(mpc == 0x0020, "BR GT: should branch when N=0 and Z=0")
}

val test_brbtst_set : unit -> unit
function test_brbtst_set() = {
    map_init();
    write_mapword(0, 3, 0x00000008);
    let _ = mexecute(MBRBTST(MBT_SET, MR0, MW3, 0b00011, 0x0042));
    assert(mpc == 0x0042, "BRBTST SET: should branch when bit 3 is set")
}

val test_brbtst_clr : unit -> unit
function test_brbtst_clr() = {
    map_init();
    write_mapword(0, 3, 0x00000008);
    let _ = mexecute(MBRBTST(MBT_CLR, MR0, MW3, 0b00000, 0x0042));
    assert(mpc == 0x0042, "BRBTST CLR: should branch when bit 0 is clear")
}

val main : unit -> unit
function main() = {
    test_br_unconditional();
    test_br_eq_taken();
    test_br_eq_not_taken();
    test_bri_relative();
    test_br_gt();
    test_brbtst_set();
    test_brbtst_clr()
}
