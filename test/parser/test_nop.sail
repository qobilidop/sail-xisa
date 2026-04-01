// Tests for the NOP instruction.
// NOP should not modify any parser state.

val test_nop_does_not_change_registers : unit -> unit
function test_nop_does_not_change_registers() = {
    parser_init();
    PR[0] = 0xAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD;
    PR[1] = 0x11111111_22222222_33333333_44444444;
    PR[2] = 0x55555555_66666666_77777777_88888888;
    PR[3] = 0x99999999_AABBCCDD_EEFF0011_22334455;

    let result = execute(PNOP());

    assert(result == RETIRE_SUCCESS, "NOP should return RETIRE_SUCCESS");
    assert(PR[0] == 0xAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD, "NOP should not modify R0");
    assert(PR[1] == 0x11111111_22222222_33333333_44444444, "NOP should not modify R1");
    assert(PR[2] == 0x55555555_66666666_77777777_88888888, "NOP should not modify R2");
    assert(PR[3] == 0x99999999_AABBCCDD_EEFF0011_22334455, "NOP should not modify R3");
}

val test_nop_does_not_change_cursor : unit -> unit
function test_nop_does_not_change_cursor() = {
    parser_init();
    pcursor = 0x42;

    let _ = execute(PNOP());

    assert(pcursor == 0x42, "NOP should not modify cursor");
}

val test_nop_does_not_change_flags : unit -> unit
function test_nop_does_not_change_flags() = {
    parser_init();
    pflag_z = true;
    pflag_n = true;

    let _ = execute(PNOP());

    assert(pflag_z == true, "NOP should not modify Z flag");
    assert(pflag_n == true, "NOP should not modify N flag");
}

val main : unit -> unit
function main() = {
    test_nop_does_not_change_registers();
    test_nop_does_not_change_cursor();
    test_nop_does_not_change_flags();
}
