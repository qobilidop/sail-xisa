// Tests for ST and STI (store to Struct-0) instructions.

// STI: store immediate into struct0 at offset 0.
val test_sti_basic : unit -> unit
function test_sti_basic() = {
    parser_init();
    let _ = execute(PSTI(0x00AB, 0x00, 0x08));
    assert(struct0 == 0x00000000_00000000_00000000_000000AB, "STI should store 0xAB at struct0[7:0]")
}

// STI: store immediate at non-zero offset.
val test_sti_at_offset : unit -> unit
function test_sti_at_offset() = {
    parser_init();
    let _ = execute(PSTI(0x00FF, 0x20, 0x08));
    assert(struct0 == 0x00000000_00000000_000000FF_00000000, "STI should store 0xFF at struct0[39:32]")
}

// ST: basic — copy 8 bits from R0[7:0] to struct0[7:0].
val test_st_basic : unit -> unit
function test_st_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    let _ = execute(PST(PR0, 0x00, 0x00, 0x08, false));
    assert(struct0 == 0x00000000_00000000_00000000_000000AB, "ST should copy R0[7:0] to struct0[7:0]")
}

// ST: with non-zero source and struct offsets.
// R0[15:8] = 0xCD, copy to struct0[39:32].
val test_st_with_offsets : unit -> unit
function test_st_with_offsets() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000CD00;
    let _ = execute(PST(PR0, 0x08, 0x20, 0x08, false));
    assert(struct0 == 0x00000000_00000000_000000CD_00000000, "ST should copy R0[15:8] to struct0[39:32]")
}

// ST: with .H halt modifier.
val test_st_with_halt : unit -> unit
function test_st_with_halt() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    let result = execute(PST(PR0, 0x00, 0x00, 0x08, true));
    assert(result == RETIRE_HALT, "ST.H should return RETIRE_HALT");
    assert(parser_halted == true, "ST.H should set parser_halted");
    assert(struct0 == 0x00000000_00000000_00000000_000000AB, "ST.H should still store the value")
}

// ST: 16-bit copy.
val test_st_16bit : unit -> unit
function test_st_16bit() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00001234;
    let _ = execute(PST(PR0, 0x00, 0x00, 0x10, false));
    assert(struct0 == 0x00000000_00000000_00000000_00001234, "ST should copy 16 bits from R0 to struct0")
}

// Program: Extract packet data, store into struct0.
// Packet: [0x45, 0x00, 0x00, 0x28, ...]  (IPv4 header)
// Step 1: EXT 8 bits at cursor=0 into R0 (version/IHL = 0x45)
// Step 2: ST R0[7:0] into struct0[39:32]  (store version byte at offset 32)
// Step 3: STI 0x0001 into struct0[7:0]    (store a flag)
// Step 4: HALT
val test_st_program : unit -> unit
function test_st_program() = {
    parser_init();
    packet_hdr[0] = 0x45;

    parser_load_program(
        [|
            PEXT(PR0, 0x00, 0x0000, 0x08, true),
            PST(PR0, 0x00, 0x20, 0x08, false),
            PSTI(0x0001, 0x00, 0x08),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(PR[0] == 0x00000000_00000000_00000000_00000045, "R0 should have 0x45");
    // struct0 should have: version byte at [39:32] = 0x45, flag at [7:0] = 0x01
    assert(struct0 == 0x00000000_00000000_00000045_00000001, "struct0 should have version at [39:32] and flag at [7:0]")
}

val main : unit -> unit
function main() = {
    test_sti_basic();
    test_sti_at_offset();
    test_st_basic();
    test_st_with_offsets();
    test_st_with_halt();
    test_st_16bit();
    test_st_program()
}
