// Tests for NXTP, BRNS, BRNXTP (transition table) instructions.

// NXTP: match found — state=0, key=0x0800, rule at index 0.
val test_nxtp_match : unit -> unit
function test_nxtp_match() = {
    parser_init();
    // Set up transition rule: state 0, key 0x0800 -> PC 100, next state 1
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    // Put key 0x0800 in R0[15:0]
    PR[0] = 0x00000000_00000000_00000000_00000800;
    // NXTP: extract 16 bits from R0 at offset 0
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_matched == true, "NXTP should find a match");
    assert(nxtp_result_pc == 0x0064, "NXTP result PC should be 100");
    assert(nxtp_result_state == 0x01, "NXTP result state should be 1")
}

// NXTP: no match — key not in table.
val test_nxtp_no_match : unit -> unit
function test_nxtp_no_match() = {
    parser_init();
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    PR[0] = 0x00000000_00000000_00000000_00009999;
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_matched == false, "NXTP should not find a match")
}

// NXTP: state-sensitive — same key, different states, different results.
val test_nxtp_state_sensitive : unit -> unit
function test_nxtp_state_sensitive() = {
    parser_init();
    // Rule 0: state 0, key 0x0800 -> PC 100, next state 1
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    // Rule 1: state 1, key 0x0800 -> PC 200, next state 2
    write_transition_rule(1, 0x01, 0x000800, 0x00C8, 0x02);
    PR[0] = 0x00000000_00000000_00000000_00000800;

    // Lookup in state 0
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_result_pc == 0x0064, "State 0 should match rule 0 (PC=100)");

    // Change to state 1 and look up again
    parser_state = 0x01;
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_result_pc == 0x00C8, "State 1 should match rule 1 (PC=200)")
}

// BRNS: branch taken — condition met, jump to rule's PC.
val test_brns_taken : unit -> unit
function test_brns_taken() = {
    parser_init();
    write_transition_rule(5, 0x00, 0x000800, 0x0064, 0x01);
    // Set Z flag so EQ condition is met
    pflag_z = true;
    let _ = execute(PBRNS(PCC_EQ, 0x05));
    assert(ppc == 0x0064, "BRNS should branch to rule 5's PC (100)");
    assert(parser_state == 0x01, "BRNS should update parser_state to 1")
}

// BRNS: branch not taken — condition not met, PC unchanged.
val test_brns_not_taken : unit -> unit
function test_brns_not_taken() = {
    parser_init();
    write_transition_rule(5, 0x00, 0x000800, 0x0064, 0x01);
    ppc = 0x0010;
    pflag_z = false;
    let _ = execute(PBRNS(PCC_EQ, 0x05));
    assert(ppc == 0x0010, "BRNS should not branch when condition not met");
    assert(parser_state == 0x00, "parser_state should remain 0")
}

// BRNXTP: matched — branch to NXTP result.
val test_brnxtp_matched : unit -> unit
function test_brnxtp_matched() = {
    parser_init();
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    PR[0] = 0x00000000_00000000_00000000_00000800;
    // NXTP to set up result
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    // BRNXTP with always-branch condition, JumpMode 000
    let _ = execute(PBRNXTP(PCC_AL, 0x00, 0x0000));
    assert(ppc == 0x0064, "BRNXTP should branch to NXTP result PC");
    assert(parser_state == 0x01, "BRNXTP should update parser_state")
}

// BRNXTP: no match, JumpMode 000 — no jump, continue.
val test_brnxtp_nomatch_mode0 : unit -> unit
function test_brnxtp_nomatch_mode0() = {
    parser_init();
    ppc = 0x0010;
    PR[0] = 0x00000000_00000000_00000000_00009999;
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_matched == false, "should not match");
    let _ = execute(PBRNXTP(PCC_AL, 0x00, 0x0000));
    assert(ppc == 0x0010, "JumpMode 000 should not change PC")
}

// BRNXTP: no match, JumpMode 010 — jump to explicit address.
val test_brnxtp_nomatch_mode2 : unit -> unit
function test_brnxtp_nomatch_mode2() = {
    parser_init();
    ppc = 0x0010;
    PR[0] = 0x00000000_00000000_00000000_00009999;
    let _ = execute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_matched == false, "should not match");
    // JumpMode 010, address = 0x00FF
    let _ = execute(PBRNXTP(PCC_AL, 0x02, 0x00FF));
    assert(ppc == 0x00FF, "JumpMode 010 should jump to address 0xFF")
}

// Program: Ethernet -> IPv4 parse graph traversal.
// Packet: EtherType 0x0800 at bytes 12-13.
// Program: EXT EtherType into R0, NXTP with key, BRNXTP to IPv4 handler at PC 50.
val test_nxtp_program : unit -> unit
function test_nxtp_program() = {
    parser_init();
    // Set up packet: EtherType 0x0800 at bytes 12-13
    packet_hdr[12] = 0x08;
    packet_hdr[13] = 0x00;
    // Transition rule: state 0, key 0x0800 -> PC 50 (IPv4 handler), state 1
    write_transition_rule(0, 0x00, 0x000800, 0x0032, 0x01);

    parser_load_program(
        [|
            // EXT 16 bits from packet offset 96 (byte 12) into R0[15:0]
            PEXT(PR0, 0x00, 0x0060, 0x10, true),
            // NXTP: look up R0[15:0] as 16-bit key
            PNXTP(PR0, 0x00, 0x10),
            // BRNXTP: always branch, JumpMode 000
            PBRNXTP(PCC_AL, 0x00, 0x0000),
        |],
    );
    // Write HALT at PC 50 (the IPv4 handler entry point)
    write_pimem(50, PHALT(false));

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt at IPv4 handler");
    assert(parser_state == 0x01, "parser_state should be 1 (IPv4)");
    assert(PR[0] == 0x00000000_00000000_00000000_00000800, "R0 should have EtherType 0x0800")
}

val main : unit -> unit
function main() = {
    test_nxtp_match();
    test_nxtp_no_match();
    test_nxtp_state_sensitive();
    test_brns_taken();
    test_brns_not_taken();
    test_brnxtp_matched();
    test_brnxtp_nomatch_mode0();
    test_brnxtp_nomatch_mode2();
    test_nxtp_program()
}
