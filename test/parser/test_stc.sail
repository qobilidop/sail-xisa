// Tests for STC and STCI (cursor manipulation) instructions.

// STCI: increment cursor from 0.
val test_stci_basic : unit -> unit
function test_stci_basic() = {
    parser_init();
    pcursor = 0x00;
    let _ = pexecute(PSTCI(0x000E));
    assert(pcursor == 0x0E, "STCI should set cursor to 14")
}

// STCI: increment cursor from non-zero position.
val test_stci_from_nonzero : unit -> unit
function test_stci_from_nonzero() = {
    parser_init();
    pcursor = 0x0A;
    let _ = pexecute(PSTCI(0x0004));
    assert(pcursor == 0x0E, "STCI should increment cursor from 10 to 14")
}

// STC: basic extraction, no shift, no additional increment.
// R0[7:0] = 0x0A, cursor += 10.
val test_stc_basic : unit -> unit
function test_stc_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    pcursor = 0x00;
    let _ = pexecute(PSTC(PR0, 0x00, 0x08, 0x00, 0x00));
    assert(pcursor == 0x0A, "STC should add extracted value to cursor")
}

// STC: left shift applied.
// R0[7:0] = 0x03, shift=2, cursor += (3 << 2) = 12.
val test_stc_with_shift : unit -> unit
function test_stc_with_shift() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;
    pcursor = 0x00;
    let _ = pexecute(PSTC(PR0, 0x00, 0x08, 0x02, 0x00));
    assert(pcursor == 0x0C, "STC with shift: cursor += (3 << 2) = 12")
}

// STC: additional increment, no shift.
// R0[7:0] = 0x03, additional_incr=2, cursor += (3 + 2) = 5.
val test_stc_with_additional_incr : unit -> unit
function test_stc_with_additional_incr() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;
    pcursor = 0x00;
    let _ = pexecute(PSTC(PR0, 0x00, 0x08, 0x00, 0x02));
    assert(pcursor == 0x05, "STC with additional_incr: cursor += (3 + 2) = 5")
}

// STC: both shift and additional increment.
// R0[7:0] = 0x02, additional_incr=1, shift=1, cursor += ((2 + 1) << 1) = 6.
val test_stc_with_shift_and_incr : unit -> unit
function test_stc_with_shift_and_incr() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000002;
    pcursor = 0x00;
    let _ = pexecute(PSTC(PR0, 0x00, 0x08, 0x01, 0x01));
    assert(pcursor == 0x06, "STC with shift and incr: cursor += ((2 + 1) << 1) = 6")
}

// STC: PRN reads as zero, only additional_incr and shift contribute.
// PRN[7:0] = 0, additional_incr=1, shift=2, cursor += ((0 + 1) << 2) = 4.
val test_stc_with_null_reg : unit -> unit
function test_stc_with_null_reg() = {
    parser_init();
    pcursor = 0x00;
    let _ = pexecute(PSTC(PRN, 0x00, 0x08, 0x02, 0x01));
    assert(pcursor == 0x04, "STC with PRN: cursor += ((0 + 1) << 2) = 4")
}

// Program: EXT two bytes, STCI to advance cursor, EXT again at new position.
// Packet: [0xAA, 0xBB, 0xCC, 0xDD, ...]
// Step 1: EXT 8 bits at cursor=0 -> R0 = 0xAA
// Step 2: STCI(2) -> cursor = 2
// Step 3: EXT 8 bits at cursor=2 -> R1 = 0xCC
// Step 4: HALT
val test_stci_program : unit -> unit
function test_stci_program() = {
    parser_init();
    packet_hdr[0] = 0xAA;
    packet_hdr[1] = 0xBB;
    packet_hdr[2] = 0xCC;
    packet_hdr[3] = 0xDD;

    parser_load_program(
        [|
            PEXT(PR0, 0x00, 0x0000, 0x08, true),
            PSTCI(0x0002),
            PEXT(PR1, 0x00, 0x0000, 0x08, true),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[0] == 0x00000000_00000000_00000000_000000AA, "first EXT at cursor=0 should get 0xAA");
    assert(PR[1] == 0x00000000_00000000_00000000_000000CC, "second EXT at cursor=2 should get 0xCC");
    assert(pcursor == 0x02, "cursor should be at 2 after STCI")
}

val main : unit -> unit
function main() = {
    test_stci_basic();
    test_stci_from_nonzero();
    test_stc_basic();
    test_stc_with_shift();
    test_stc_with_additional_incr();
    test_stc_with_shift_and_incr();
    test_stc_with_null_reg();
    test_stci_program()
}
