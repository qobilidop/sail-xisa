// Tests for PSEEK and PSEEKNXTP (protocol seek accelerator) instructions.

// PSEEK: no match — protocol not in table, cursor unchanged.
val test_pseek_no_skip : unit -> unit
function test_pseek_no_skip() = {
    parser_init();
    // R0 has protocol value 0x0800 (IPv4)
    PR[0] = 0x00000000_00000000_00000000_00000800;
    // No PSEEK entries configured — 0x0800 not in table
    // PPSEEK(dest_reg, dest_offset_bits, src_reg, src_offset_bits, size_bits, class_id)
    let _ = execute(PPSEEK(PR1, 0x00, PR0, 0x00, 0x10, 0x00));
    assert(PR[1] == 0x00000000_00000000_00000000_00000800,
        "PSEEK should store original protocol in R1");
    assert(pcursor == 0x00, "cursor should not advance when no match")
}

// PSEEK: skip one VLAN tag.
// Packet layout at cursor (byte 12):
//   bytes 12-13: EtherType 0x8100 (VLAN)
//   bytes 14-15: VLAN TCI
//   bytes 16-17: inner EtherType 0x0800
// PSEEK entry: VLAN hdr_length=4, next_proto at offset 2 (relative to header start), 16 bits
// After skip: cursor at 16, next proto read from bytes 16-17 = 0x0800
val test_pseek_skip_one : unit -> unit
function test_pseek_skip_one() = {
    parser_init();
    pcursor = 0x0C;
    packet_hdr[12] = 0x81; packet_hdr[13] = 0x00;
    packet_hdr[14] = 0x00; packet_hdr[15] = 0x01;
    packet_hdr[16] = 0x08; packet_hdr[17] = 0x00;

    // PSEEK entry: class 0, proto 0x8100, hdr_length=4, next_proto at offset 2, 16 bits
    write_pseek_entry(0, 0x00, 0x8100, 0x04, 0x00, 0x10);

    PR[0] = 0x00000000_00000000_00000000_00008100;
    let _ = execute(PPSEEK(PR1, 0x00, PR0, 0x00, 0x10, 0x00));

    assert(pcursor == 0x10, "cursor should advance by 4 (from 12 to 16)");
    assert(PR[1] == 0x00000000_00000000_00000000_00000800,
        "PSEEK should store inner EtherType 0x0800 in R1")
}

// PSEEK: skip two stacked VLAN tags (QinQ).
val test_pseek_skip_two : unit -> unit
function test_pseek_skip_two() = {
    parser_init();
    pcursor = 0x0C;
    // Outer VLAN at byte 12
    packet_hdr[12] = 0x81; packet_hdr[13] = 0x00;
    packet_hdr[14] = 0x00; packet_hdr[15] = 0x01;
    // Inner VLAN at byte 16
    packet_hdr[16] = 0x81; packet_hdr[17] = 0x00;
    packet_hdr[18] = 0x00; packet_hdr[19] = 0x02;
    // Final EtherType at byte 20
    packet_hdr[20] = 0x08; packet_hdr[21] = 0x00;

    write_pseek_entry(0, 0x00, 0x8100, 0x04, 0x00, 0x10);

    PR[0] = 0x00000000_00000000_00000000_00008100;
    let _ = execute(PPSEEK(PR1, 0x00, PR0, 0x00, 0x10, 0x00));

    assert(pcursor == 0x14, "cursor should advance by 8 (from 12 to 20)");
    assert(PR[1] == 0x00000000_00000000_00000000_00000800,
        "PSEEK should store final EtherType 0x0800 after skipping two VLANs")
}

// PSEEKNXTP: skip VLAN + NXTP lookup.
val test_pseeknxtp : unit -> unit
function test_pseeknxtp() = {
    parser_init();
    pcursor = 0x0C;
    packet_hdr[12] = 0x81; packet_hdr[13] = 0x00;
    packet_hdr[14] = 0x00; packet_hdr[15] = 0x01;
    packet_hdr[16] = 0x08; packet_hdr[17] = 0x00;

    write_pseek_entry(0, 0x00, 0x8100, 0x04, 0x00, 0x10);
    write_transition_rule(0, 0x00, 0x000800, 0x0064, 0x01);

    PR[0] = 0x00000000_00000000_00000000_00008100;
    let _ = execute(PPSEEKNXTP(PR1, 0x00, PR0, 0x00, 0x10, 0x00));

    assert(pcursor == 0x10, "cursor should advance past VLAN");
    assert(PR[1] == 0x00000000_00000000_00000000_00000800,
        "R1 should have inner EtherType");
    assert(nxtp_matched == true, "PSEEKNXTP should find transition match");
    assert(nxtp_result_pc == 0x0064, "result PC should be 100")
}

// PSEEK with RN dest: cursor advances but no register written.
val test_pseek_rn_dest : unit -> unit
function test_pseek_rn_dest() = {
    parser_init();
    pcursor = 0x0C;
    packet_hdr[12] = 0x81; packet_hdr[13] = 0x00;
    packet_hdr[14] = 0x00; packet_hdr[15] = 0x01;
    packet_hdr[16] = 0x08; packet_hdr[17] = 0x00;

    write_pseek_entry(0, 0x00, 0x8100, 0x04, 0x00, 0x10);

    PR[0] = 0x00000000_00000000_00000000_00008100;
    let _ = execute(PPSEEK(PRN, 0x00, PR0, 0x00, 0x10, 0x00));

    assert(pcursor == 0x10, "cursor should still advance");
    assert(read_preg(PRN) == sail_zeros(128), "RN should read as zero")
}

// Program: Ethernet with VLAN -> skip VLAN -> NXTP -> BRNXTP to IPv4.
val test_pseek_program : unit -> unit
function test_pseek_program() = {
    parser_init();
    // Ethernet: EtherType 0x8100 at bytes 12-13, VLAN at 14-17, inner 0x0800 at 16-17
    packet_hdr[12] = 0x81; packet_hdr[13] = 0x00;
    packet_hdr[14] = 0x00; packet_hdr[15] = 0x01;
    packet_hdr[16] = 0x08; packet_hdr[17] = 0x00;

    write_pseek_entry(0, 0x00, 0x8100, 0x04, 0x00, 0x10);
    write_transition_rule(0, 0x00, 0x000800, 0x0032, 0x01);

    parser_load_program(
        [|
            // Set cursor to byte 12 (EtherType position)
            PSTCI(0x000C),
            // EXT EtherType into R0[15:0]
            PEXT(PR0, 0x00, 0x0000, 0x10, true),
            // PSEEKNXTP: skip VLANs, lookup final protocol
            PPSEEKNXTP(PR1, 0x00, PR0, 0x00, 0x10, 0x00),
            // BRNXTP to IPv4 handler
            PBRNXTP(PCC_AL, 0x00, 0x0000),
        |],
    );
    write_pimem(50, PHALT(false));

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt at IPv4 handler");
    assert(parser_state == 0x01, "parser_state should be 1 (IPv4)");
    assert(pcursor == 0x10, "cursor should be past VLAN tag at byte 16");
    assert(PR[1] == 0x00000000_00000000_00000000_00000800,
        "R1 should have inner EtherType 0x0800")
}

val main : unit -> unit
function main() = {
    test_pseek_no_skip();
    test_pseek_skip_one();
    test_pseek_skip_two();
    test_pseeknxtp();
    test_pseek_rn_dest();
    test_pseek_program()
}
