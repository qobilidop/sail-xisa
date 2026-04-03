// Tests for SUB, SUBI, and SUBII instructions.

val test_sub_basic : unit -> unit
function test_sub_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_00000003;

    let _ = pexecute(PSUB(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));

    assert(PR[2] == 0x00000000_00000000_00000000_00000007, "SUB: 10 - 3 = 7");
    assert(pflag_z == false, "SUB: result not zero");
    assert(pflag_n == false, "SUB: result not negative")
}

val test_sub_zero_result : unit -> unit
function test_sub_zero_result() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000005;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = pexecute(PSUB(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));

    assert(pflag_z == true, "SUB: 5 - 5 sets Z flag");
    assert(pflag_n == false, "SUB: 5 - 5 does not set N flag")
}

val test_sub_negative_result : unit -> unit
function test_sub_negative_result() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = pexecute(PSUB(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));

    assert(PR[2] == 0x00000000_00000000_00000000_000000FE, "SUB: 3 - 5 wraps to 0xFE");
    assert(pflag_z == false, "SUB: result not zero");
    assert(pflag_n == true, "SUB: 3 - 5 sets N flag")
}

val test_subi_basic : unit -> unit
function test_subi_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000F;

    let _ = pexecute(PSUBI(PR1, PR0, 0x0005, 0x08, false));

    assert(PR[1] == 0x00000000_00000000_00000000_0000000A, "SUBI: 15 - 5 = 10");
    assert(pflag_z == false, "SUBI: result not zero");
    assert(pflag_n == false, "SUBI: result not negative")
}

val test_subii_basic : unit -> unit
function test_subii_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;

    let _ = pexecute(PSUBII(PR1, 0x000A, PR0, 0x08, false));

    assert(PR[1] == 0x00000000_00000000_00000000_00000007, "SUBII: 10 - 3 = 7");
    assert(pflag_n == false, "SUBII: result not negative")
}

val test_subii_negative : unit -> unit
function test_subii_negative() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;

    let _ = pexecute(PSUBII(PR1, 0x0003, PR0, 0x08, false));

    assert(PR[1] == 0x00000000_00000000_00000000_000000F9, "SUBII: 3 - 10 wraps to 0xF9");
    assert(pflag_n == true, "SUBII: 3 - 10 sets N flag")
}

val test_sub_with_clear_dest : unit -> unit
function test_sub_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000014;
    PR[1] = 0x00000000_00000000_00000000_0000000A;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = pexecute(PSUB(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, true));
    assert(PR[2] == 0x00000000_00000000_00000000_0000000A,
        "SUB.CD should clear dest then place difference")
}

val test_subi_with_clear_dest : unit -> unit
function test_subi_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000014;
    PR[1] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = pexecute(PSUBI(PR1, PR0, 0x000A, 0x08, true));
    assert(PR[1] == 0x00000000_00000000_00000000_0000000A,
        "SUBI.CD should clear dest then place difference")
}

val test_subii_with_clear_dest : unit -> unit
function test_subii_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;
    PR[1] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = pexecute(PSUBII(PR1, 0x000A, PR0, 0x08, true));
    assert(PR[1] == 0x00000000_00000000_00000000_00000007,
        "SUBII.CD should clear dest then place difference")
}

val main : unit -> unit
function main() = {
    test_sub_basic();
    test_sub_zero_result();
    test_sub_negative_result();
    test_subi_basic();
    test_subii_basic();
    test_subii_negative();
    test_sub_with_clear_dest();
    test_subi_with_clear_dest();
    test_subii_with_clear_dest()
}
