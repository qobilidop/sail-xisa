// Tests for MAP NOP and HALT instructions.

val test_nop : unit -> unit
function test_nop() = {
    map_init();
    let result = mexecute(MNOP());
    assert(result == RETIRE_SUCCESS, "NOP should return success");
    assert(map_halted == false, "NOP should not halt")
}

val test_halt : unit -> unit
function test_halt() = {
    map_init();
    let result = mexecute(MHALT());
    assert(result == RETIRE_HALT, "HALT should return RETIRE_HALT");
    assert(map_halted == true, "HALT should set map_halted")
}

val main : unit -> unit
function main() = {
    test_nop();
    test_halt()
}
