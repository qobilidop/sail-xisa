// Tests for ADD and ADDI instructions.

val test_add_basic : unit -> unit
function test_add_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000003;
    PR[1] = 0x00000000_00000000_00000000_00000005;

    let _ = execute(PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));

    assert(PR[2] == 0x00000000_00000000_00000000_00000008, "ADD: 3 + 5 = 8");
    assert(pflag_z == false, "ADD: result is not zero")
}

val test_add_with_offsets : unit -> unit
function test_add_with_offsets() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_00000A00;
    PR[1] = 0x00000000_00000000_00000000_00000014;

    let _ = execute(PADD(PR2, 0x00, PR0, 0x08, PR1, 0x00, 0x08, false));

    assert(PR[2] == 0x00000000_00000000_00000000_0000001E, "ADD with offsets: 0x0A + 0x14 = 0x1E")
}

val test_add_zero_flag : unit -> unit
function test_add_zero_flag() = {
    parser_init();
    PR[0] = sail_zeros(128);
    PR[1] = sail_zeros(128);

    let _ = execute(PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, false));

    assert(pflag_z == true, "ADD: 0 + 0 should set Z flag")
}

val test_add_16bit_overflow : unit -> unit
function test_add_16bit_overflow() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000FFFF;
    PR[1] = 0x00000000_00000000_00000000_00000001;

    let _ = execute(PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x10, false));

    assert(PR[2] == 0x00000000_00000000_00000000_00000000, "ADD: 16-bit overflow wraps to 0");
    assert(pflag_z == true, "ADD: overflow to zero sets Z flag")
}

val test_addi_basic : unit -> unit
function test_addi_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;

    let _ = execute(PADDI(PR1, PR0, 0x0005, 0x08, false));

    assert(PR[1] == 0x00000000_00000000_00000000_0000000F, "ADDI: 0x0A + 5 = 0x0F");
    assert(pflag_z == false, "ADDI: result is not zero")
}

val test_addi_zero_flag : unit -> unit
function test_addi_zero_flag() = {
    parser_init();
    PR[0] = sail_zeros(128);

    let _ = execute(PADDI(PR1, PR0, 0x0000, 0x08, false));

    assert(pflag_z == true, "ADDI: 0 + 0 sets Z flag")
}

val test_add_with_clear_dest : unit -> unit
function test_add_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0x00000000_00000000_00000000_00000014;
    PR[2] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PADD(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08, true));
    assert(PR[2] == 0x00000000_00000000_00000000_0000001E,
        "ADD.CD should clear dest then place sum")
}

val test_addi_with_clear_dest : unit -> unit
function test_addi_with_clear_dest() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_0000000A;
    PR[1] = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF;
    let _ = execute(PADDI(PR1, PR0, 0x0005, 0x08, true));
    assert(PR[1] == 0x00000000_00000000_00000000_0000000F,
        "ADDI.CD should clear dest then place sum")
}

val main : unit -> unit
function main() = {
    test_add_basic();
    test_add_with_offsets();
    test_add_zero_flag();
    test_add_16bit_overflow();
    test_addi_basic();
    test_addi_zero_flag();
    test_add_with_clear_dest();
    test_addi_with_clear_dest()
}
