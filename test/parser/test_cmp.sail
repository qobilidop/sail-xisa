// Tests for CMP, CMPIBY, and CMPIBI instructions.

val test_cmp_equal : unit -> unit
function test_cmp_equal() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000042;
    PR[1] = 0x00000000_00000000_00000000_00000042;

    let _ = execute(PCMP(PR0, 0x00, PR1, 0x00, 0x08));

    assert(pflag_z == true, "CMP: equal values set Z flag");
    assert(pflag_n == false, "CMP: equal values do not set N flag")
}

val test_cmp_greater : unit -> unit
function test_cmp_greater() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = execute(PCMP(PR0, 0x00, PR1, 0x00, 0x08));

    assert(pflag_z == false, "CMP: 10 > 5, Z not set");
    assert(pflag_n == false, "CMP: 10 > 5, N not set")
}

val test_cmp_less : unit -> unit
function test_cmp_less() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = execute(PCMP(PR0, 0x00, PR1, 0x00, 0x08));

    assert(pflag_z == false, "CMP: 3 < 5, Z not set");
    assert(pflag_n == true, "CMP: 3 < 5, N set")
}

val test_cmp_does_not_store : unit -> unit
function test_cmp_does_not_store() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = execute(PCMP(PR0, 0x00, PR1, 0x00, 0x08));

    assert(PR[0] == 0x00000000_00000000_00000000_0000000A, "CMP should not modify source registers");
    assert(PR[1] == 0x00000000_00000000_00000000_00000005, "CMP should not modify source registers")
}

val test_cmpiby_equal : unit -> unit
function test_cmpiby_equal() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00420000;

    let _ = execute(PCMPIBY(PR0, 0x02, 0x0042, 0x08));

    assert(pflag_z == true, "CMPIBY: equal values set Z flag");
    assert(pflag_n == false, "CMPIBY: equal values do not set N flag")
}

val test_cmpibi_less : unit -> unit
function test_cmpibi_less() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;

    let _ = execute(PCMPIBI(PR0, 0x00, 0x000A, 0x08));

    assert(pflag_z == false, "CMPIBI: 3 < 10, Z not set");
    assert(pflag_n == true, "CMPIBI: 3 < 10, N set")
}

val main : unit -> unit
function main() = {
    test_cmp_equal();
    test_cmp_greater();
    test_cmp_less();
    test_cmp_does_not_store();
    test_cmpiby_equal();
    test_cmpibi_less()
}
