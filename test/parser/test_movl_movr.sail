// Tests for MOVL/MOVR (dynamic offset move) instruction variants.

// MOVL: R0[7:0]=0xAB, R1[2:0]=4, MOVL to R2 at dynamic offset 4+0=4.
// R2[11:4] should be 0xAB.
val test_movl_basic : unit -> unit
function test_movl_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0x00000000_00000000_00000000_00000004;
    // PMOVL(rd, rs1, offs1, size1, rs2, offs2, size2, clear_dest)
    // Extract R0[7:0] (offs1=0, size1=8), offset = R1[2:0] + 0 = 4
    let _ = pexecute(PMOVL(PR2, PR0, 0x00, 0x08, PR1, 0x00, 0x03, false));
    assert(read_preg(PR2) == 0x00000000_00000000_00000000_00000AB0,
        "MOVL should place 0xAB at R2[11:4]")
}

// MOVL with .CD: same as above but destination cleared first.
val test_movl_cd : unit -> unit
function test_movl_cd() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;
    PR[1] = 0x00000000_00000000_00000000_00000004;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = pexecute(PMOVL(PR2, PR0, 0x00, 0x08, PR1, 0x00, 0x03, true));
    assert(read_preg(PR2) == 0x00000000_00000000_00000000_00000AB0,
        "MOVL.CD should clear dest then place 0xAB at R2[11:4]")
}

// MOVLI: R0[7:0]=0xCD, MOVLI with imm_value=16 and offs=0.
// k = 16 + 0 = 16, R1[23:16] = 0xCD.
val test_movli_basic : unit -> unit
function test_movli_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000CD;
    // PMOVLI(rd, rs, offs, size, imm_value, clear_dest)
    let _ = pexecute(PMOVLI(PR1, PR0, 0x00, 0x08, 0x10, false));
    assert(read_preg(PR1) == 0x00000000_00000000_00000000_00CD0000,
        "MOVLI should place 0xCD at R1[23:16]")
}

// MOVLII: R0[3:0]=8, place imm 0x1F (5 bits) at offset 8.
// k = R0[3:0] = 8, R1[12:8] = 0x1F.
val test_movlii_basic : unit -> unit
function test_movlii_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000008;
    // PMOVLII(rd, rs, offs, size, imm_value, imm_value_size, clear_dest)
    let _ = pexecute(PMOVLII(PR1, PR0, 0x00, 0x04, 0x1F, 0x05, false));
    assert(read_preg(PR1) == 0x00000000_00000000_00000000_00001F00,
        "MOVLII should place 0x1F at R1[12:8]")
}

// MOVR: R0[39:32]=0xAB, R1[2:0]=4, offs1=32.
// Source: R0[39:32], k = 32 - 4 = 28, R2[35:28] = 0xAB.
val test_movr_basic : unit -> unit
function test_movr_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_000000AB_00000000;
    PR[1] = 0x00000000_00000000_00000000_00000004;
    // PMOVR(rd, rs1, offs1, size1, rs2, offs2, size2, clear_dest)
    let _ = pexecute(PMOVR(PR2, PR0, 0x20, 0x08, PR1, 0x00, 0x03, false));
    assert(read_preg(PR2) == 0x00000000_00000000_0000000A_B0000000,
        "MOVR should place 0xAB at R2[35:28]")
}

// MOVRI: R0[39:32]=0xEF, offs=32, imm=16.
// Source: R0[39:32], k = 32 - 16 = 16, R1[23:16] = 0xEF.
val test_movri_basic : unit -> unit
function test_movri_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_000000EF_00000000;
    // PMOVRI(rd, rs, offs, size, imm_value, clear_dest)
    let _ = pexecute(PMOVRI(PR1, PR0, 0x20, 0x08, 0x10, false));
    assert(read_preg(PR1) == 0x00000000_00000000_00000000_00EF0000,
        "MOVRI should place 0xEF at R1[23:16]")
}

// MOVRII: R0[2:0]=2, imm=0x1F (5 bits), imm_size=5.
// k = R0[2:0] = 2, m = 5 - 2 = 3, DestReg[2:0] = ImmValue[4:2] = 0b111 = 7.
val test_movrii_basic : unit -> unit
function test_movrii_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000002;
    // PMOVRII(rd, rs, offs, size, imm_value, imm_value_size, clear_dest)
    let _ = pexecute(PMOVRII(PR1, PR0, 0x00, 0x03, 0x1F, 0x05, false));
    assert(read_preg(PR1) == 0x00000000_00000000_00000000_00000007,
        "MOVRII should place ImmValue[4:2]=7 at R1[2:0]")
}

// Program: EXT a 3-bit offset value from packet, use MOVL to dynamically
// place 8 bits of data at that offset.
// Packet: [0x04, 0xAB]  (byte 0 has offset=4, byte 1 has data=0xAB)
val test_movl_program : unit -> unit
function test_movl_program() = {
    parser_init();
    packet_hdr[0] = 0x04;
    packet_hdr[1] = 0xAB;

    parser_load_program(
        [|
            // EXT 3 bits from packet[7:5] into R0[2:0] (the offset value = 0, top 3 bits of 0x04=0b00000100)
            // Actually packet byte 0 = 0x04 = 0b00000100.
            // Bits [7:5] = 0b000 = 0. Bits [2:0] = 0b100 = 4.
            // EXT at bit offset 5, size 3: extracts bits [7:5] = 0. Not what we want.
            // EXT at bit offset 0, size 3: extracts bits [2:0] = 4. Yes.
            // But packet is big-endian: byte 0 bit 7 is MSB.
            // In our model: packet byte 0 = 0x04. EXT offset 0, size 8 gives 0x04.
            // Let's just EXT 8 bits into R0, then use low 3 bits as offset.
            PEXT(PR0, 0x00, 0x0000, 0x08, true),
            // EXT 8 bits from packet byte 1 into R1[7:0] (the data = 0xAB)
            PEXT(PR1, 0x00, 0x0008, 0x08, true),
            // MOVL: place R1[7:0] at dynamic offset R0[2:0] + 0 = 4 into R2
            PMOVL(PR2, PR1, 0x00, 0x08, PR0, 0x00, 0x03, true),
            PHALT(false),
        |],
    );

    let result = parser_run();

    assert(result == RETIRE_HALT, "program should halt");
    assert(read_preg(PR2) == 0x00000000_00000000_00000000_00000AB0,
        "R2 should have 0xAB at bits [11:4]")
}

val main : unit -> unit
function main() = {
    test_movl_basic();
    test_movl_cd();
    test_movli_basic();
    test_movlii_basic();
    test_movr_basic();
    test_movri_basic();
    test_movrii_basic();
    test_movl_program()
}
