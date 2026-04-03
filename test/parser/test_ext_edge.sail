// Edge-case tests for EXT instruction.
// Focus on non-byte-aligned extractions and multi-byte spanning.
//
// IMPORTANT: Source offset is big-endian (MSB-first).
// Offset 0 = MSbit of the first byte from cursor.
// For byte 0xAB (1010_1011): offset 0 size 4 = 0xA (high nibble),
// offset 4 size 4 = 0xB (low nibble).

// Extract high nibble (offset 0, size 4).
val test_ext_nibble_high : unit -> unit
function test_ext_nibble_high() = {
    parser_init();
    packet_hdr[0] = 0xAB;
    pcursor = 0x00;

    let _ = pexecute(PEXT(PR0, 0x00, 0x0000, 0x04, true));

    assert(PR[0] == 0x00000000_00000000_00000000_0000000A, "EXT: high nibble of 0xAB = 0xA")
}

// Extract low nibble (offset 4, size 4).
val test_ext_nibble_low : unit -> unit
function test_ext_nibble_low() = {
    parser_init();
    packet_hdr[0] = 0xAB;
    pcursor = 0x00;

    let _ = pexecute(PEXT(PR0, 0x00, 0x0004, 0x04, true));

    assert(PR[0] == 0x00000000_00000000_00000000_0000000B, "EXT: low nibble of 0xAB = 0xB")
}

// Extract bits spanning two bytes.
val test_ext_cross_byte_boundary : unit -> unit
function test_ext_cross_byte_boundary() = {
    parser_init();

    // Packet: [0xAB, 0xCD]
    // 16-bit big-endian: 0xABCD = 1010_1011_1100_1101
    packet_hdr[0] = 0xAB;
    packet_hdr[1] = 0xCD;
    pcursor = 0x00;

    // Extract 8 bits at offset 4 (spans bytes 0 and 1)
    // Bits from MSB: skip 4, take 8 = 1011_1100 = 0xBC
    let _ = pexecute(PEXT(PR0, 0x00, 0x0004, 0x08, true));

    assert(PR[0] == 0x00000000_00000000_00000000_000000BC, "EXT: cross-byte extraction at offset 4 = 0xBC")
}

// Extract 12 bits spanning two bytes.
val test_ext_12bit_cross_byte : unit -> unit
function test_ext_12bit_cross_byte() = {
    parser_init();

    // Packet: [0xFF, 0xF0]
    // 16 bits: 0xFFF0 = 1111_1111_1111_0000
    packet_hdr[0] = 0xFF;
    packet_hdr[1] = 0xF0;
    pcursor = 0x00;

    // Extract 12 bits at offset 0: top 12 bits = 0xFFF
    let _ = pexecute(PEXT(PR0, 0x00, 0x0000, 0x0C, true));

    assert(PR[0] == 0x00000000_00000000_00000000_00000FFF, "EXT: 12 bits at offset 0 from 0xFFF0 = 0xFFF")
}

// Extract with non-zero cursor and non-zero source offset.
val test_ext_cursor_plus_offset : unit -> unit
function test_ext_cursor_plus_offset() = {
    parser_init();
    packet_hdr[0] = 0x00;
    packet_hdr[1] = 0x00;
    packet_hdr[2] = 0x00;
    packet_hdr[3] = 0xAB;
    packet_hdr[4] = 0xCD;
    pcursor = 0x02;

    // Cursor at byte 2. Source offset 8 bits (1 byte) from cursor = byte 3.
    // Extract 16 bits starting at byte 3: 0xABCD
    let _ = pexecute(PEXT(PR0, 0x00, 0x0008, 0x10, true));

    assert(PR[0] == 0x00000000_00000000_00000000_0000ABCD, "EXT: cursor=2, offset=8bits, extract 16 bits = 0xABCD")
}

// Extract single bit (MSB of byte).
val test_ext_single_bit_msb : unit -> unit
function test_ext_single_bit_msb() = {
    parser_init();
    packet_hdr[0] = 0x80;
    pcursor = 0x00;

    // Offset 0, size 1: MSB of 0x80 = 1
    let _ = pexecute(PEXT(PR0, 0x00, 0x0000, 0x01, true));

    assert(PR[0] == 0x00000000_00000000_00000000_00000001, "EXT: single bit, MSB of 0x80 = 1")
}

// Extract single bit (LSB of byte).
val test_ext_single_bit_lsb : unit -> unit
function test_ext_single_bit_lsb() = {
    parser_init();
    packet_hdr[0] = 0x80;
    pcursor = 0x00;

    // Offset 7, size 1: LSB of 0x80 = 0
    let _ = pexecute(PEXT(PR1, 0x00, 0x0007, 0x01, true));

    assert(PR[1] == 0x00000000_00000000_00000000_00000000, "EXT: single bit, LSB of 0x80 = 0")
}

// Extract to high destination offset.
val test_ext_high_dest_offset : unit -> unit
function test_ext_high_dest_offset() = {
    parser_init();
    packet_hdr[0] = 0xAB;
    pcursor = 0x00;

    // Extract 8 bits, place at dest offset 120 (bits [127:120])
    let _ = pexecute(PEXT(PR0, 0x78, 0x0000, 0x08, true));

    assert(PR[0] == 0xAB000000_00000000_00000000_00000000, "EXT: place data at dest offset 120 (top byte)")
}

val main : unit -> unit
function main() = {
    test_ext_nibble_high();
    test_ext_nibble_low();
    test_ext_cross_byte_boundary();
    test_ext_12bit_cross_byte();
    test_ext_cursor_plus_offset();
    test_ext_single_bit_msb();
    test_ext_single_bit_lsb();
    test_ext_high_dest_offset()
}
