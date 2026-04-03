// Tests for compound instructions (EXTNXTP, BRBTSTNXTP, BRBTSTNS).

// EXTNXTP: extract EtherType 0x0800 from packet, lookup matches.
val test_extnxtp_match : unit -> unit
function test_extnxtp_match() = {
    parser_init();
    packet_hdr[0] = 0x08;
    packet_hdr[1] = 0x00;
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    // PEXTNXTP(dest_reg, source_offset_bits, size_bits, clear_dest)
    let _ = pexecute(PEXTNXTP(PR0, 0x0000, 0x10, true));
    assert(PR[0] == 0x00000000_00000000_00000000_00000800,
        "EXTNXTP should extract 0x0800 into R0[15:0]");
    assert(nxtp_matched == true, "EXTNXTP should find a match");
    assert(nxtp_result_pc == 0x0064, "EXTNXTP result PC should be 100")
}

// EXTNXTP with RN: lookup happens but dest register is null.
val test_extnxtp_rn : unit -> unit
function test_extnxtp_rn() = {
    parser_init();
    packet_hdr[0] = 0x08;
    packet_hdr[1] = 0x00;
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    let _ = pexecute(PEXTNXTP(PRN, 0x0000, 0x10, true));
    // RN always reads as zero
    assert(read_preg(PRN) == sail_zeros(128),
        "EXTNXTP with RN should not modify any register");
    assert(nxtp_matched == true, "EXTNXTP should still perform lookup")
}

// BRBTSTNXTP: bit set, condition SET, nxtp matched -> branch.
val test_brbtstnxtp_taken : unit -> unit
function test_brbtstnxtp_taken() = {
    parser_init();
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    PR[0] = 0x00000000_00000000_00000000_00000800;
    // Set up NXTP result
    let _ = pexecute(PNXTP(PR0, 0x00, 0x10));
    assert(nxtp_matched == true, "NXTP should match");
    // R1 with bit 0 set
    PR[1] = 0x00000000_00000000_00000000_00000001;
    // PBRBTSTNXTP(condition, src_reg, bit_offset, jump_mode, addr_or_rule)
    let _ = pexecute(PBRBTSTNXTP(PBT_SET, PR1, 0x00, 0x00, 0x0000));
    assert(ppc == 0x0064, "BRBTSTNXTP should branch to NXTP result PC");
    assert(parser_state == 0x01, "BRBTSTNXTP should update parser_state")
}

// BRBTSTNXTP: bit clear, condition SET -> no branch.
val test_brbtstnxtp_not_taken : unit -> unit
function test_brbtstnxtp_not_taken() = {
    parser_init();
    ppc = 0x0010;
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);
    PR[0] = 0x00000000_00000000_00000000_00000800;
    let _ = pexecute(PNXTP(PR0, 0x00, 0x10));
    // R1 with bit 0 clear
    PR[1] = 0x00000000_00000000_00000000_00000000;
    let _ = pexecute(PBRBTSTNXTP(PBT_SET, PR1, 0x00, 0x00, 0x0000));
    assert(ppc == 0x0010, "BRBTSTNXTP should not branch when bit is clear")
}

// BRBTSTNS: bit set, condition SET -> branch to rule's next state.
val test_brbtstns_taken : unit -> unit
function test_brbtstns_taken() = {
    parser_init();
    write_transition_rule(3, 0x00, 0x000800, 0x0050, 0x02);
    // R0 with bit 4 set
    PR[0] = 0x00000000_00000000_00000000_00000010;
    // PBRBTSTNS(condition, src_reg, bit_offset, rule_number)
    let _ = pexecute(PBRBTSTNS(PBT_SET, PR0, 0x04, 0x03));
    assert(ppc == 0x0050, "BRBTSTNS should branch to rule 3's PC");
    assert(parser_state == 0x02, "BRBTSTNS should update parser_state to 2")
}

// Program: EXTNXTP + BRNXTP for streamlined Ethernet -> IPv4.
val test_extnxtp_program : unit -> unit
function test_extnxtp_program() = {
    parser_init();
    packet_hdr[12] = 0x08;
    packet_hdr[13] = 0x00;
    write_transition_rule(0, 0x00, 0x000800, 0x0032, 0x01);

    parser_load_program(
        [|
            // EXTNXTP: extract 16 bits from packet offset 96 (byte 12) + lookup
            PEXTNXTP(PR0, 0x0060, 0x10, true),
            // BRNXTP: branch to NXTP result
            PBRNXTP(PCC_AL, 0x00, 0x0000),
        |],
    );
    write_pimem(50, PHALT(false));

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt at IPv4 handler");
    assert(parser_state == 0x01, "parser_state should be 1 (IPv4)");
    assert(PR[0] == 0x00000000_00000000_00000000_00000800, "R0 should have EtherType")
}

val main : unit -> unit
function main() = {
    test_extnxtp_match();
    test_extnxtp_rn();
    test_brbtstnxtp_taken();
    test_brbtstnxtp_not_taken();
    test_brbtstns_taken();
    test_extnxtp_program()
}
