// Tests for EXTMAP and MOVMAP (write to MAP registers) instructions.

// EXTMAP: extract 8 bits from packet byte 0 into MAP0[7:0].
val test_extmap_basic : unit -> unit
function test_extmap_basic() = {
    parser_init();
    packet_hdr[0] = 0xAB;
    let _ = execute(PEXTMAP(0x0, 0x00, 0x0000, 0x08));
    assert(read_mapreg(0) == 0x00000000_00000000_00000000_000000AB,
        "EXTMAP should extract 0xAB into MAP0[7:0]")
}

// EXTMAP: extract into MAP register at non-zero dest offset.
val test_extmap_dest_offset : unit -> unit
function test_extmap_dest_offset() = {
    parser_init();
    packet_hdr[0] = 0xAB;
    let _ = execute(PEXTMAP(0x0, 0x20, 0x0000, 0x08));
    assert(read_mapreg(0) == 0x00000000_00000000_000000AB_00000000,
        "EXTMAP should extract 0xAB into MAP0[39:32]")
}

// EXTMAP: extract from non-zero packet bit offset.
val test_extmap_packet_offset : unit -> unit
function test_extmap_packet_offset() = {
    parser_init();
    packet_hdr[0] = 0x00;
    packet_hdr[1] = 0x00;
    packet_hdr[2] = 0xCD;
    let _ = execute(PEXTMAP(0x0, 0x00, 0x0010, 0x08));
    assert(read_mapreg(0) == 0x00000000_00000000_00000000_000000CD,
        "EXTMAP should extract byte at packet bit offset 16")
}

// EXTMAP: extract 16 bits across two bytes into MAP1.
val test_extmap_16bit : unit -> unit
function test_extmap_16bit() = {
    parser_init();
    packet_hdr[0] = 0x12;
    packet_hdr[1] = 0x34;
    let _ = execute(PEXTMAP(0x1, 0x00, 0x0000, 0x10));
    assert(read_mapreg(1) == 0x00000000_00000000_00000000_00001234,
        "EXTMAP should extract 16 bits into MAP1[15:0]")
}

// MOVMAP: move 8 bits from R0[7:0] to MAP0[7:0].
val test_movmap_basic : unit -> unit
function test_movmap_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000CD;
    let _ = execute(PMOVMAP(0x0, 0x00, PR0, 0x00, 0x08));
    assert(read_mapreg(0) == 0x00000000_00000000_00000000_000000CD,
        "MOVMAP should copy R0[7:0] to MAP0[7:0]")
}

// MOVMAP: move with non-zero source and dest offsets.
val test_movmap_offsets : unit -> unit
function test_movmap_offsets() = {
    parser_init();
    PR[1] = 0x00000000_00000000_00000000_0000EF00;
    let _ = execute(PMOVMAP(0x2, 0x10, PR1, 0x08, 0x08));
    assert(read_mapreg(2) == 0x00000000_00000000_00000000_00EF0000,
        "MOVMAP should copy R1[15:8] to MAP2[23:16]")
}

// MOVMAP: write to MAP register 13 (highest index).
val test_movmap_high_reg : unit -> unit
function test_movmap_high_reg() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000FF;
    let _ = execute(PMOVMAP(0xD, 0x00, PR0, 0x00, 0x08));
    assert(read_mapreg(13) == 0x00000000_00000000_00000000_000000FF,
        "MOVMAP should write to MAP register 13")
}

// Program: EXT packet data into R0, MOVMAP from R0 into MAP0,
// EXTMAP packet data directly into MAP1, verify both.
// Packet: [0x45, 0x00, 0x00, 0x28]
val test_extmap_movmap_program : unit -> unit
function test_extmap_movmap_program() = {
    parser_init();
    packet_hdr[0] = 0x45;
    packet_hdr[1] = 0x00;
    packet_hdr[2] = 0x00;
    packet_hdr[3] = 0x28;

    parser_load_program(
        [|
            PEXT(PR0, 0x00, 0x0000, 0x08, true),
            PMOVMAP(0x0, 0x00, PR0, 0x00, 0x08),
            PEXTMAP(0x1, 0x00, 0x0018, 0x08),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[0] == 0x00000000_00000000_00000000_00000045, "R0 should have 0x45");
    assert(read_mapreg(0) == 0x00000000_00000000_00000000_00000045,
        "MAP0 should have 0x45 from MOVMAP");
    assert(read_mapreg(1) == 0x00000000_00000000_00000000_00000028,
        "MAP1 should have 0x28 from EXTMAP")
}

val main : unit -> unit
function main() = {
    test_extmap_basic();
    test_extmap_dest_offset();
    test_extmap_packet_offset();
    test_extmap_16bit();
    test_movmap_basic();
    test_movmap_offsets();
    test_movmap_high_reg();
    test_extmap_movmap_program()
}
