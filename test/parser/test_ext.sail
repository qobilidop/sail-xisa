// Tests for the EXT (Extract) instruction.

val test_ext_basic : unit -> unit
function test_ext_basic() = {
    parser_init();

    // Load packet bytes
    packet_hdr[0] = 0x01;
    packet_hdr[1] = 0x02;
    packet_hdr[2] = 0x03;
    packet_hdr[3] = 0x04;

    // Cursor at 0, extract 16 bits (2 bytes) from packet offset 0 into R0 at offset 0
    pcursor = 0x00;
    let _ = execute(PEXT(PR0, 0x00, 0x0000, 0x10, false));

    // Bytes 0x01, 0x02 extracted big-endian: 0x0102 placed at R0[15:0]
    assert(PR[0] == 0x00000000_00000000_00000000_00000102, "EXT should extract 2 bytes from packet into register")
}

val test_ext_with_cursor_offset : unit -> unit
function test_ext_with_cursor_offset() = {
    parser_init();

    packet_hdr[0] = 0xAA;
    packet_hdr[1] = 0xBB;
    packet_hdr[2] = 0xCC;
    packet_hdr[3] = 0xDD;

    // Cursor at byte 2, extract 8 bits from packet offset 0 (relative to cursor)
    pcursor = 0x02;
    let _ = execute(PEXT(PR0, 0x00, 0x0000, 0x08, false));

    assert(PR[0] == 0x00000000_00000000_00000000_000000CC, "EXT should extract relative to cursor position")
}

val test_ext_with_source_offset : unit -> unit
function test_ext_with_source_offset() = {
    parser_init();

    packet_hdr[0] = 0xAA;
    packet_hdr[1] = 0xBB;
    packet_hdr[2] = 0xCC;
    packet_hdr[3] = 0xDD;

    // Cursor at 0, extract 8 bits from source offset 16 bits (= 2 bytes from cursor)
    pcursor = 0x00;
    let _ = execute(PEXT(PR0, 0x00, 0x0010, 0x08, false));

    assert(PR[0] == 0x00000000_00000000_00000000_000000CC, "EXT should respect source offset from cursor")
}

val test_ext_with_dest_offset : unit -> unit
function test_ext_with_dest_offset() = {
    parser_init();

    packet_hdr[0] = 0xFF;

    // Extract 8 bits from packet offset 0, place at dest offset 112 (near MSB)
    pcursor = 0x00;
    let _ = execute(PEXT(PR0, 0x70, 0x0000, 0x08, false));

    // R0[119:112] = 0xFF
    assert(PR[0] == 0x00FF0000_00000000_00000000_00000000, "EXT should place data at correct destination offset")
}

val test_ext_with_clear_dest : unit -> unit
function test_ext_with_clear_dest() = {
    parser_init();
    PR[0] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;

    packet_hdr[0] = 0xAB;

    // EXT.CD: clear destination register before extraction
    pcursor = 0x00;
    let _ = execute(PEXT(PR0, 0x00, 0x0000, 0x08, true));

    assert(PR[0] == 0x00000000_00000000_00000000_000000AB, "EXT.CD should clear register then place extracted data")
}

val test_ext_preserves_other_bits_without_cd : unit -> unit
function test_ext_preserves_other_bits_without_cd() = {
    parser_init();
    PR[0] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFF00;

    packet_hdr[0] = 0xAB;

    // EXT without .CD: other bits in R0 should be preserved
    pcursor = 0x00;
    let _ = execute(PEXT(PR0, 0x00, 0x0000, 0x08, false));

    assert(PR[0] == 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFAB, "EXT without .CD should preserve other bits")
}

val main : unit -> unit
function main() = {
    test_ext_basic();
    test_ext_with_cursor_offset();
    test_ext_with_source_offset();
    test_ext_with_dest_offset();
    test_ext_with_clear_dest();
    test_ext_preserves_other_bits_without_cd()
}
