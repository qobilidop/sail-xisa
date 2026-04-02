// Tests for CNCTBY and CNCTBI instructions.

val test_cnctby_basic : unit -> unit
function test_cnctby_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AA;
    PR[1] = 0x00000000_00000000_00000000_000000BB;

    let _ = execute(PCNCTBY(PR2, 0x00, PR0, 0x00, 0x01, PR1, 0x00, 0x01, false));

    assert(PR[2] == 0x00000000_00000000_00000000_0000AABB, "CNCTBY: concatenate two bytes")
}

val test_cnctby_with_offsets : unit -> unit
function test_cnctby_with_offsets() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000CC00;
    PR[1] = 0x00000000_00000000_00000000_00DD0000;

    let _ = execute(PCNCTBY(PR2, 0x00, PR0, 0x01, 0x01, PR1, 0x02, 0x01, false));

    assert(PR[2] == 0x00000000_00000000_00000000_0000CCDD, "CNCTBY: bytes from different offsets")
}

val test_cnctbi_basic : unit -> unit
function test_cnctbi_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = execute(PCNCTBI(PR2, 0x00, PR0, 0x00, 0x04, PR1, 0x00, 0x04, false));

    assert(PR[2] == 0x00000000_00000000_00000000_000000A5, "CNCTBI: concatenate two 4-bit fields")
}

val test_cnctby_with_clear_dest : unit -> unit
function test_cnctby_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0x00000000_00000000_00000000_000000CD;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PCNCTBY(PR2, 0x00, PR0, 0x00, 0x01, PR1, 0x00, 0x01, true));
    assert(PR[2] == 0x00000000_00000000_00000000_0000ABCD,
        "CNCTBY.CD should clear dest then place concatenated bytes")
}

val test_cnctbi_with_clear_dest : unit -> unit
function test_cnctbi_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_0000000B;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PCNCTBI(PR2, 0x00, PR0, 0x00, 0x04, PR1, 0x00, 0x04, true));
    assert(PR[2] == 0x00000000_00000000_00000000_000000AB,
        "CNCTBI.CD should clear dest then place concatenated bits")
}

val main : unit -> unit
function main() = {
    test_cnctby_basic();
    test_cnctby_with_offsets();
    test_cnctbi_basic();
    test_cnctby_with_clear_dest();
    test_cnctbi_with_clear_dest()
}
