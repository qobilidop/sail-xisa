// Tests for OR and ORI instructions.

val test_or_basic : unit -> unit
function test_or_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000F0;
    PR[1] = 0x00000000_00000000_00000000_0000000F;

    let _ = pexecute(POR(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));

    assert(PR[2] == 0x00000000_00000000_00000000_000000FF, "OR: 0xF0 | 0x0F = 0xFF");
    assert(pflag_z == false, "OR: result not zero")
}

val test_or_zero_result : unit -> unit
function test_or_zero_result() = {
    parser_init();
    PR[0] = sail_zeros(128);
    PR[1] = sail_zeros(128);

    let _ = pexecute(POR(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));

    assert(pflag_z == true, "OR: 0 | 0 sets Z flag")
}

val test_ori_basic : unit -> unit
function test_ori_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000A0;

    let _ = pexecute(PORI(PR1, PR0, 0x000F, 0x08, false));

    assert(PR[1] == 0x00000000_00000000_00000000_000000AF, "ORI: 0xA0 | 0x0F = 0xAF");
    assert(pflag_z == false, "ORI: result not zero")
}

val test_or_with_clear_dest : unit -> unit
function test_or_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000A0;
    PR[1] = 0x00000000_00000000_00000000_0000000B;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = pexecute(POR(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, true));
    assert(PR[2] == 0x00000000_00000000_00000000_000000AB,
        "OR.CD should clear dest then place OR result")
}

val test_ori_with_clear_dest : unit -> unit
function test_ori_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000A0;
    PR[1] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = pexecute(PORI(PR1, PR0, 0x000B, 0x08, true));
    assert(PR[1] == 0x00000000_00000000_00000000_000000AB,
        "ORI.CD should clear dest then place OR result")
}

val main : unit -> unit
function main() = {
    test_or_basic();
    test_or_zero_result();
    test_ori_basic();
    test_or_with_clear_dest();
    test_ori_with_clear_dest()
}
