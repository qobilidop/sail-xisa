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

val main : unit -> unit
function main() = {
    test_sth_basic();
    test_sth_with_halt();
    test_sth_different_ids()
}
