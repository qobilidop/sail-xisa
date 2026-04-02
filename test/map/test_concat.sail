// Tests for MAP CONCAT instruction.

val test_concat_basic : unit -> unit
function test_concat_basic() = {
    map_init();
    // Src1: R0.W3 = 0xA (4 bits at offset 0, size 4)
    // Src2: R1.W3 = 0xB (4 bits at offset 0, size 4)
    // Result: (0xB << 4) | 0xA = 0xBA at dest offset 0
    write_mapword(0, 3, 0x0000000A);
    write_mapword(1, 3, 0x0000000B);
    let _ = mexecute(MCONCAT(MR2, MW3, 0b00000,
                             MR0, MW3, 0b00000, 0b00100,
                             MR1, MW3, 0b00000, 0b00100, false));
    assert(read_mapword(2, 3) == 0x000000BA, "CONCAT: (0xB << 4) | 0xA = 0xBA")
}

val test_concat_cd : unit -> unit
function test_concat_cd() = {
    map_init();
    // Pre-fill dest, then CONCAT.CD should clear first
    write_mapword(2, 3, 0xFFFFFFFF);
    write_mapword(0, 3, 0x0000000A);
    write_mapword(1, 3, 0x0000000B);
    let _ = mexecute(MCONCAT(MR2, MW3, 0b00000,
                             MR0, MW3, 0b00000, 0b00100,
                             MR1, MW3, 0b00000, 0b00100, true));
    assert(read_mapword(2, 3) == 0x000000BA, "CONCAT.CD: clears dest before write")
}

val main : unit -> unit
function main() = {
    test_concat_basic();
    test_concat_cd()
}
