// Program-level tests that run through the fetch-decode-execute loop.

// Simple program: load a value then halt.
val test_movi_halt : unit -> unit
function test_movi_halt() = {
    parser_init();
    parser_load_program([|PMOVI(PR0, 0x00, 0x0042, 0x08), PHALT(false)|]);

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[0] == 0x00000000_00000000_00000000_00000042, "R0 should have 0x42");
    assert(parser_halted == true, "parser should be halted")
}

// Arithmetic program: load two values, add them, halt.
val test_add_program : unit -> unit
function test_add_program() = {
    parser_init();
    parser_load_program(
        [|
            PMOVI(PR0, 0x00, 0x000A, 0x08),
            PMOVI(PR1, 0x00, 0x0014, 0x08),
            PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[2] == 0x00000000_00000000_00000000_0000001E, "R2 = 0x0A + 0x14 = 0x1E")
}

// Branch program: compare and branch to halt at different addresses.
val test_branch_program : unit -> unit
function test_branch_program() = {
    parser_init();

    // Program:
    //   0: MOVI R0, 5
    //   1: MOVI R1, 5
    //   2: CMP R0, R1
    //   3: BREQ -> addr 6
    //   4: MOVI R2, 0xFF  (should be skipped)
    //   5: HALT
    //   6: MOVI R2, 0xAA  (branch target)
    //   7: HALT
    parser_load_program(
        [|
            PMOVI(PR0, 0x00, 0x0005, 0x08),
            PMOVI(PR1, 0x00, 0x0005, 0x08),
            PCMP(PR0, 0x00, PR1, 0x00, 0x08),
            PBR(PCC_EQ, 0x0006),
            PMOVI(PR2, 0x00, 0x00FF, 0x08),
            PHALT(false),
            PMOVI(PR2, 0x00, 0x00AA, 0x08),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[2] == 0x00000000_00000000_00000000_000000AA, "branch should skip to addr 6, R2 = 0xAA not 0xFF")
}

// Branch not taken: fall through.
val test_branch_not_taken_program : unit -> unit
function test_branch_not_taken_program() = {
    parser_init();

    // Program:
    //   0: MOVI R0, 3
    //   1: MOVI R1, 5
    //   2: CMP R0, R1   (3 < 5, so Z=0, N=1)
    //   3: BREQ -> addr 6  (not taken, Z=0)
    //   4: MOVI R2, 0xBB   (fall through here)
    //   5: HALT
    //   6: MOVI R2, 0xCC
    //   7: HALT
    parser_load_program(
        [|
            PMOVI(PR0, 0x00, 0x0003, 0x08),
            PMOVI(PR1, 0x00, 0x0005, 0x08),
            PCMP(PR0, 0x00, PR1, 0x00, 0x08),
            PBR(PCC_EQ, 0x0006),
            PMOVI(PR2, 0x00, 0x00BB, 0x08),
            PHALT(false),
            PMOVI(PR2, 0x00, 0x00CC, 0x08),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[2] == 0x00000000_00000000_00000000_000000BB, "branch not taken, fall through, R2 = 0xBB")
}

// Counting loop: decrement from 3 to 0.
val test_loop_program : unit -> unit
function test_loop_program() = {
    parser_init();

    // Program:
    //   0: MOVI R0, 3       (counter = 3)
    //   1: SUBI R0, R0, 1   (counter--)
    //   2: CMP R0 vs 0      (check if zero)
    //   3: BRNEQ -> addr 1  (loop back if not zero)
    //   4: HALT
    parser_load_program(
        [|
            PMOVI(PR0, 0x00, 0x0003, 0x08),
            PSUBI(PR0, PR0, 0x0001, 0x08),
            PCMPIBI(PR0, 0x00, 0x0000, 0x08),
            PBR(PCC_NEQ, 0x0001),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[0] == 0x00000000_00000000_00000000_00000000, "counter should be 0 after loop")
}

// HALTDROP program.
val test_drop_program : unit -> unit
function test_drop_program() = {
    parser_init();
    parser_load_program([|PMOVI(PR0, 0x00, 0x0001, 0x08), PHALT(true)|]);

    let result = parser_run();

    assert(result == RETIRE_DROP, "program should drop");
    assert(parser_drop == true, "drop flag should be set")
}

val main : unit -> unit
function main() = {
    test_movi_halt();
    test_add_program();
    test_branch_program();
    test_branch_not_taken_program();
    test_loop_program();
    test_drop_program()
}
