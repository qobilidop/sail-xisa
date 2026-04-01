// Tests for STH, STCH, and STHC (header metadata) instructions.

// STH: basic — sets present and offset at current cursor.
val test_sth_basic : unit -> unit
function test_sth_basic() = {
    parser_init();
    pcursor = 0x0E;
    let _ = execute(PSTH(0x00, 0x00, false));
    assert(hdr_present[0] == true, "STH should set hdr_present[0]");
    assert(hdr_offset[0] == 0x0E, "STH should set hdr_offset[0] to cursor position")
}

// STH: with halt modifier.
val test_sth_with_halt : unit -> unit
function test_sth_with_halt() = {
    parser_init();
    pcursor = 0x0E;
    let result = execute(PSTH(0x00, 0x00, true));
    assert(result == RETIRE_HALT, "STH.H should return RETIRE_HALT");
    assert(parser_halted == true, "STH.H should set parser_halted");
    assert(hdr_present[0] == true, "STH.H should still set header present");
    assert(hdr_offset[0] == 0x0E, "STH.H should still set header offset")
}

// STH: different present and offset IDs.
val test_sth_different_ids : unit -> unit
function test_sth_different_ids() = {
    parser_init();
    pcursor = 0x0A;
    let _ = execute(PSTH(0x01, 0x02, false));
    assert(hdr_present[0] == false, "hdr_present[0] should be unchanged");
    assert(hdr_present[1] == true, "STH should set hdr_present[1]");
    assert(hdr_offset[0] == 0x00, "hdr_offset[0] should be unchanged");
    assert(hdr_offset[2] == 0x0A, "STH should set hdr_offset[2] to cursor position")
}

// STCH: increment cursor then set header (offset = new cursor).
val test_stch_basic : unit -> unit
function test_stch_basic() = {
    parser_init();
    pcursor = 0x00;
    let _ = execute(PSTCH(0x000E, 0x00, 0x00, false));
    assert(pcursor == 0x0E, "STCH should increment cursor to 14");
    assert(hdr_present[0] == true, "STCH should set hdr_present[0]");
    assert(hdr_offset[0] == 0x0E, "STCH should set hdr_offset[0] to NEW cursor position")
}

// STCH: with halt modifier.
val test_stch_with_halt : unit -> unit
function test_stch_with_halt() = {
    parser_init();
    pcursor = 0x00;
    let result = execute(PSTCH(0x000E, 0x00, 0x00, true));
    assert(result == RETIRE_HALT, "STCH.H should return RETIRE_HALT");
    assert(parser_halted == true, "STCH.H should set parser_halted");
    assert(pcursor == 0x0E, "STCH.H should still increment cursor");
    assert(hdr_offset[0] == 0x0E, "STCH.H should still set header offset")
}

// STHC: set header at current cursor then increment (offset = old cursor).
val test_sthc_basic : unit -> unit
function test_sthc_basic() = {
    parser_init();
    pcursor = 0x00;
    let _ = execute(PSTHC(0x000E, 0x00, 0x00));
    assert(pcursor == 0x0E, "STHC should increment cursor to 14");
    assert(hdr_present[0] == true, "STHC should set hdr_present[0]");
    assert(hdr_offset[0] == 0x00, "STHC should set hdr_offset[0] to OLD cursor position")
}

// STCH vs STHC: same parameters, different offset recorded.
val test_stch_vs_sthc_ordering : unit -> unit
function test_stch_vs_sthc_ordering() = {
    // STCH: cursor advances first, header records NEW position
    parser_init();
    pcursor = 0x04;
    let _ = execute(PSTCH(0x000A, 0x00, 0x00, false));
    let stch_offset = hdr_offset[0];
    assert(stch_offset == 0x0E, "STCH should record offset=14 (4+10, new cursor)");

    // STHC: header records CURRENT position, then cursor advances
    parser_init();
    pcursor = 0x04;
    let _ = execute(PSTHC(0x000A, 0x01, 0x01));
    let sthc_offset = hdr_offset[1];
    assert(sthc_offset == 0x04, "STHC should record offset=4 (old cursor)")
}

// Program: Parse two protocol headers from a packet.
// Packet: [Eth header 14 bytes] [IPv4 header 20 bytes] [payload...]
//
// Step 1: STHC(14, 0, 0) — record Ethernet at offset 0, advance cursor to 14
// Step 2: EXT 8 bits at cursor=14 into R0 (first byte of IPv4)
// Step 3: STHC(20, 1, 1) — record IPv4 at offset 14, advance cursor to 34
// Step 4: HALT
val test_parse_two_headers : unit -> unit
function test_parse_two_headers() = {
    parser_init();

    // Fill packet: Ethernet (14 bytes) + IPv4 (starts with version/IHL = 0x45)
    packet_hdr[14] = 0x45;

    parser_load_program(
        [|
            PSTHC(0x000E, 0x00, 0x00),
            PEXT(PR0, 0x00, 0x0000, 0x08, true),
            PSTHC(0x0014, 0x01, 0x01),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    // Ethernet header recorded at offset 0
    assert(hdr_present[0] == true, "Ethernet header should be present");
    assert(hdr_offset[0] == 0x00, "Ethernet header offset should be 0");
    // IPv4 header recorded at offset 14
    assert(hdr_present[1] == true, "IPv4 header should be present");
    assert(hdr_offset[1] == 0x0E, "IPv4 header offset should be 14");
    // Cursor should be at 34 (14 + 20)
    assert(pcursor == 0x22, "cursor should be at 34 after both headers");
    // R0 should have first byte of IPv4 header
    assert(PR[0] == 0x00000000_00000000_00000000_00000045, "R0 should have IPv4 version/IHL byte")
}

val main : unit -> unit
function main() = {
    test_sth_basic();
    test_sth_with_halt();
    test_sth_different_ids();
    test_stch_basic();
    test_stch_with_halt();
    test_sthc_basic();
    test_stch_vs_sthc_ordering();
    test_parse_two_headers()
}
