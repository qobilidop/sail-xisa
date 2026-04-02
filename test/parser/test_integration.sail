// Integration tests that chain multiple instructions together.
// These verify that instructions interact correctly: flag propagation,
// register state, and control flow.

// Scenario: Load two values, add them, compare result, branch based on outcome.
val test_movi_add_cmp_br : unit -> unit
function test_movi_add_cmp_br() = {
    parser_init();

    // Load 0x0A into R0[7:0]
    let _ = execute(PMOVI(PR0, 0x00, 0x000A, 0x08, false));
    assert(PR[0] == 0x00000000_00000000_00000000_0000000A, "MOVI loaded 0x0A");

    // Load 0x14 into R1[7:0]
    let _ = execute(PMOVI(PR1, 0x00, 0x0014, 0x08, false));
    assert(PR[1] == 0x00000000_00000000_00000000_00000014, "MOVI loaded 0x14");

    // ADD R2 = R0 + R1 = 0x0A + 0x14 = 0x1E
    let _ = execute(PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));
    assert(PR[2] == 0x00000000_00000000_00000000_0000001E, "ADD: 0x0A + 0x14 = 0x1E");
    assert(pflag_z == false, "ADD result not zero");

    // CMP R2 vs immediate 0x1E — should be equal
    let _ = execute(PCMPIBI(PR2, 0x00, 0x001E, 0x08));
    assert(pflag_z == true, "CMP: R2 == 0x1E");
    assert(pflag_n == false, "CMP: not negative");

    // BREQ should branch (Z=1)
    let _ = execute(PBR(PCC_EQ, 0x0042));
    assert(ppc == 0x0042, "BREQ taken after equal compare")
}

// Scenario: Subtract to get negative, branch on less-than.
val test_sub_negative_branch : unit -> unit
function test_sub_negative_branch() = {
    parser_init();

    // R0 = 3, R1 = 10
    let _ = execute(PMOVI(PR0, 0x00, 0x0003, 0x08, false));
    let _ = execute(PMOVI(PR1, 0x00, 0x000A, 0x08, false));

    // SUB R2 = R0 - R1 = 3 - 10 = -7 (0xF9 in 8 bits)
    let _ = execute(PSUB(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));
    assert(PR[2] == 0x00000000_00000000_00000000_000000F9, "SUB: 3 - 10 = 0xF9");
    assert(pflag_n == true, "N flag set after negative result");
    assert(pflag_z == false, "Z flag not set");

    // BRLT should branch (N=1)
    let _ = execute(PBR(PCC_LT, 0x0100));
    assert(ppc == 0x0100, "BRLT taken after negative subtraction");

    // BRGT should NOT branch (N=1)
    ppc = sail_zeros(16);
    let _ = execute(PBR(PCC_GT, 0x0200));
    assert(ppc == 0x0000, "BRGT not taken when N=1")
}

// Scenario: Bitwise mask + compare pattern (common in packet parsing).
val test_and_mask_cmp : unit -> unit
function test_and_mask_cmp() = {
    parser_init();

    // R0 = 0x45 (e.g., IPv4 version+IHL byte)
    let _ = execute(PMOVI(PR0, 0x00, 0x0045, 0x08, false));

    // AND with 0xF0 to extract high nibble (version)
    let _ = execute(PANDI(PR1, PR0, 0x00F0, 0x08, false));
    assert(PR[1] == 0x00000000_00000000_00000000_00000040, "ANDI: 0x45 & 0xF0 = 0x40");

    // Compare version nibble with 0x40 (IPv4)
    let _ = execute(PCMPIBI(PR1, 0x00, 0x0040, 0x08));
    assert(pflag_z == true, "CMP: version nibble matches IPv4");

    // Branch if equal
    let _ = execute(PBR(PCC_EQ, 0x0300));
    assert(ppc == 0x0300, "Branch to IPv4 handler")
}

// Scenario: Extract from packet, move, concatenate (realistic parser pattern).
val test_ext_mov_cnct : unit -> unit
function test_ext_mov_cnct() = {
    parser_init();

    // Packet: [0x08, 0x00, 0xAB, 0xCD] (EtherType 0x0800 at bytes 0-1, payload at 2-3)
    packet_hdr[0] = 0x08;
    packet_hdr[1] = 0x00;
    packet_hdr[2] = 0xAB;
    packet_hdr[3] = 0xCD;
    pcursor = 0x00;

    // Extract EtherType (16 bits at offset 0) into R0[15:0]
    let _ = execute(PEXT(PR0, 0x00, 0x0000, 0x10, true));
    assert(PR[0] == 0x00000000_00000000_00000000_00000800, "EXT: EtherType = 0x0800");

    // Extract payload (16 bits at offset 16) into R1[15:0]
    let _ = execute(PEXT(PR1, 0x00, 0x0010, 0x10, true));
    assert(PR[1] == 0x00000000_00000000_00000000_0000ABCD, "EXT: payload = 0xABCD");

    // Concatenate EtherType (R0, 2 bytes) and payload (R1, 2 bytes) into R2
    let _ = execute(PCNCTBY(PR2, 0x00, PR0, 0x00, 0x02, PR1, 0x00, 0x02, false));
    assert(PR[2] == 0x00000000_00000000_00000000_0800ABCD, "CNCTBY: 0x0800 || 0xABCD")
}

// Scenario: BRBTST on a flag bit extracted from packet.
val test_ext_brbtst : unit -> unit
function test_ext_brbtst() = {
    parser_init();

    // Packet byte 0 = 0x80 (bit 7 set — e.g., a flag bit)
    packet_hdr[0] = 0x80;
    pcursor = 0x00;

    // Extract 8 bits into R0
    let _ = execute(PEXT(PR0, 0x00, 0x0000, 0x08, true));
    assert(PR[0] == 0x00000000_00000000_00000000_00000080, "EXT: 0x80");

    // Test bit 7 — should be set
    let _ = execute(PBRBTST(PBT_SET, PR0, 0x07, 0x0500));
    assert(ppc == 0x0500, "BRBTST: bit 7 is set, branch taken");

    // Test bit 0 — should be clear
    ppc = sail_zeros(16);
    let _ = execute(PBRBTST(PBT_CLR, PR0, 0x00, 0x0600));
    assert(ppc == 0x0600, "BRBTST: bit 0 is clear, branch taken")
}

// Scenario: Flags are overwritten correctly between instructions.
val test_flag_propagation : unit -> unit
function test_flag_propagation() = {
    parser_init();

    // ADD 0 + 0 -> Z=1
    let _ = execute(PADD(PR0, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));
    assert(pflag_z == true, "Z set after 0+0");

    // ADD 1 + 0 -> Z=0 (Z flag should be cleared)
    let _ = execute(PMOVI(PR0, 0x00, 0x0001, 0x08, false));
    let _ = execute(PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));
    assert(pflag_z == false, "Z cleared after non-zero ADD");

    // SUB 5 - 10 -> N=1
    let _ = execute(PMOVI(PR0, 0x00, 0x0005, 0x08, false));
    let _ = execute(PMOVI(PR1, 0x00, 0x000A, 0x08, false));
    let _ = execute(PSUB(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));
    assert(pflag_n == true, "N set after negative SUB");

    // SUB 10 - 5 -> N=0 (N flag should be cleared)
    let _ = execute(PSUB(PR2, 0x00, PR1, 0x00, PR0, 0x00, 0x08, false));
    assert(pflag_n == false, "N cleared after positive SUB")
}

val main : unit -> unit
function main() = {
    test_movi_add_cmp_br();
    test_sub_negative_branch();
    test_and_mask_cmp();
    test_ext_mov_cnct();
    test_ext_brbtst();
    test_flag_propagation()
}
