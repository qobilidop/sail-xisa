// Tests for the HALT and HALTDROP instructions.

val test_halt_sets_halted_flag : unit -> unit
function test_halt_sets_halted_flag() = {
    parser_init();
    assert(parser_halted == false, "parser should start not halted");

    let result = execute(PHALT(false));

    assert(result == RETIRE_HALT, "HALT should return RETIRE_HALT");
    assert(parser_halted == true, "HALT should set parser_halted flag");
    assert(parser_drop == false, "HALT should not set drop flag");
}

val test_haltdrop_sets_both_flags : unit -> unit
function test_haltdrop_sets_both_flags() = {
    parser_init();

    let result = execute(PHALT(true));

    assert(result == RETIRE_DROP, "HALTDROP should return RETIRE_DROP");
    assert(parser_halted == true, "HALTDROP should set parser_halted flag");
    assert(parser_drop == true, "HALTDROP should set drop flag");
}

val test_halt_does_not_modify_registers : unit -> unit
function test_halt_does_not_modify_registers() = {
    parser_init();
    PR[0] = 0xDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF;

    let _ = execute(PHALT(false));

    assert(PR[0] == 0xDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF,
           "HALT should not modify registers");
}

val test_halt_does_not_modify_cursor : unit -> unit
function test_halt_does_not_modify_cursor() = {
    parser_init();
    pcursor = 0x10;

    let _ = execute(PHALT(false));

    assert(pcursor == 0x10, "HALT should not modify cursor");
}

val main : unit -> unit
function main() = {
    test_halt_sets_halted_flag();
    test_haltdrop_sets_both_flags();
    test_halt_does_not_modify_registers();
    test_halt_does_not_modify_cursor();
}
