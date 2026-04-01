// Tests for AND and ANDI instructions.

val test_and_basic : unit -> unit
function test_and_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000FF;
    PR[1] = 0x00000000_00000000_00000000_0000000F;

    let _ = execute(PAND(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(PR[2] == 0x00000000_00000000_00000000_0000000F, "AND: 0xFF & 0x0F = 0x0F");
    assert(pflag_z == false, "AND: result not zero")
}

val test_and_zero_result : unit -> unit
function test_and_zero_result() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000F0;
    PR[1] = 0x00000000_00000000_00000000_0000000F;

    let _ = execute(PAND(PR2, 0x00, PR0, 0x00, PR1, 0x00, 0x08));

    assert(PR[2] == 0x00000000_00000000_00000000_00000000, "AND: 0xF0 & 0x0F = 0x00");
    assert(pflag_z == true, "AND: zero result sets Z flag")
}

val test_andi_basic : unit -> unit
function test_andi_basic() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000AB;

    let _ = execute(PANDI(PR1, PR0, 0x000F, 0x08));

    assert(PR[1] == 0x00000000_00000000_00000000_0000000B, "ANDI: 0xAB & 0x0F = 0x0B");
    assert(pflag_z == false, "ANDI: result not zero")
}

val test_andi_zero_result : unit -> unit
function test_andi_zero_result() = {
    parser_init();
    PR[0] = 0x00000000_00000000_00000000_000000F0;

    let _ = execute(PANDI(PR1, PR0, 0x000F, 0x08));

    assert(pflag_z == true, "ANDI: 0xF0 & 0x0F sets Z flag")
}

val main : unit -> unit
function main() = {
    test_and_basic();
    test_and_zero_result();
    test_andi_basic();
    test_andi_zero_result()
}
