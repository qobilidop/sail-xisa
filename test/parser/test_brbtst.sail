// Tests for BRBTST (bit-test branch) instruction.

val test_brbtst_set_taken : unit -> unit
function test_brbtst_set_taken() = {
    parser_init();

    // R0 bit 0 = 1
    PR[0] = 0x00000000_00000000_00000000_00000001;

    let _ = execute(PBRBTST(PBT_SET, PR0, 0x00, 0x0100));

    assert(ppc == 0x0100, "BRBTSTSET: bit 0 is set, should branch")
}

val test_brbtst_set_not_taken : unit -> unit
function test_brbtst_set_not_taken() = {
    parser_init();

    // R0 bit 0 = 0
    PR[0] = sail_zeros(128);

    let _ = execute(PBRBTST(PBT_SET, PR0, 0x00, 0x0100));

    assert(ppc == 0x0000, "BRBTSTSET: bit 0 is clear, should not branch")
}

val test_brbtst_clr_taken : unit -> unit
function test_brbtst_clr_taken() = {
    parser_init();

    // R0 bit 4 = 0 (R0 = 0x01, so bit 4 is 0)
    PR[0] = 0x00000000_00000000_00000000_00000001;

    let _ = execute(PBRBTST(PBT_CLR, PR0, 0x04, 0x0200));

    assert(ppc == 0x0200, "BRBTSTCLR: bit 4 is clear, should branch")
}

val test_brbtst_clr_not_taken : unit -> unit
function test_brbtst_clr_not_taken() = {
    parser_init();

    // R0 bit 4 = 1 (R0 = 0x10, bit 4 is set)
    PR[0] = 0x00000000_00000000_00000000_00000010;

    let _ = execute(PBRBTST(PBT_CLR, PR0, 0x04, 0x0200));

    assert(ppc == 0x0000, "BRBTSTCLR: bit 4 is set, should not branch")
}

val test_brbtst_high_bit : unit -> unit
function test_brbtst_high_bit() = {
    parser_init();

    // R0 bit 127 (MSB) = 1
    PR[0] = 0x80000000_00000000_00000000_00000000;

    let _ = execute(PBRBTST(PBT_SET, PR0, 0x7F, 0x0300));

    assert(ppc == 0x0300, "BRBTSTSET: bit 127 is set, should branch")
}

val test_brbtst_does_not_modify_register : unit -> unit
function test_brbtst_does_not_modify_register() = {
    parser_init();
    PR[0] = 0xDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF;

    let _ = execute(PBRBTST(PBT_SET, PR0, 0x00, 0x0400));

    assert(PR[0] == 0xDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF, "BRBTST should not modify the source register")
}

val main : unit -> unit
function main() = {
    test_brbtst_set_taken();
    test_brbtst_set_not_taken();
    test_brbtst_clr_taken();
    test_brbtst_clr_not_taken();
    test_brbtst_high_bit();
    test_brbtst_does_not_modify_register()
}
