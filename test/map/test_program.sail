// Multi-instruction MAP program tests using map_run.

val test_simple_program : unit -> unit
function test_simple_program() = {
    map_init();
    map_load_program([|encode_minstr(MMOVI(MR0, MW3, 0x00000042, false)),
                       encode_minstr(MHALT())|]);
    let result = map_run();
    assert(result == RETIRE_HALT, "Program should halt");
    assert(read_mapword(0, 3) == 0x00000042, "R0.W3 should be 0x42")
}

val test_add_program : unit -> unit
function test_add_program() = {
    map_init();
    // MOVI R0.W3, 10; MOVI R1.W3, 20; ADD R2.W3, R0.W3[0:8], R1.W3[0:8]; HALT
    map_load_program([|
        encode_minstr(MMOVI(MR0, MW3, 0x0000000A, false)),
        encode_minstr(MMOVI(MR1, MW3, 0x00000014, false)),
        encode_minstr(MADD(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                           MR1, MW3, 0b00000, 0b01000, false, false, false)),
        encode_minstr(MHALT())
    |]);
    let result = map_run();
    assert(result == RETIRE_HALT, "Program should halt");
    assert(read_mapword(2, 3) == 0x0000001E, "10 + 20 = 30")
}

val test_branch_program : unit -> unit
function test_branch_program() = {
    map_init();
    // 0: MOVI R0.W3, 5
    // 1: MOVI R1.W3, 5
    // 2: CMP R0.W3[0:8], R1.W3[0:8]
    // 3: BRI EQ, +2 (skip to 6, since PC is already at 4 after fetch)
    // 4: MOVI R2.W3, 0xBB  (skipped)
    // 5: HALT              (skipped)
    // 6: MOVI R2.W3, 0xAA
    // 7: HALT
    map_load_program([|
        encode_minstr(MMOVI(MR0, MW3, 0x00000005, false)),
        encode_minstr(MMOVI(MR1, MW3, 0x00000005, false)),
        encode_minstr(MCMP(MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000)),
        encode_minstr(MBRI(MCC_EQ, 0x0002)),
        encode_minstr(MMOVI(MR2, MW3, 0x000000BB, false)),
        encode_minstr(MHALT()),
        encode_minstr(MMOVI(MR2, MW3, 0x000000AA, false)),
        encode_minstr(MHALT())
    |]);
    let result = map_run();
    assert(result == RETIRE_HALT, "Program should halt");
    assert(read_mapword(2, 3) == 0x000000AA, "Branch should skip to MOVI 0xAA")
}

val main : unit -> unit
function main() = {
    test_simple_program();
    test_add_program();
    test_branch_program()
}
