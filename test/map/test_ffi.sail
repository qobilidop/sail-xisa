// Tests for MAP FFI (Find First non-zero field) instruction.

val test_ffi_found_lsb : unit -> unit
function test_ffi_found_lsb() = {
    map_init();
    // Value: 0x00000030 — nibble at offset 4 is 0x3 (first non-zero scanning LSb to MSb)
    // Offset reg: start at 0
    // Field size: 3 (nibble = 4 bits, imm = 0b11)
    // Scan direction: LSb to MSb (true)
    write_mapword(0, 3, 0x00000030);  // value
    write_mapword(1, 3, 0x00000000);  // start offset = 0
    let _ = mexecute(MFFI(MR2, MW3, MR0, MW3, MR1, MW3, 0b11, true));
    // First non-zero nibble at offset 4, content = 0x3
    // Result: DestReg[11:8] = 0x3, DestReg[4:0] = 4
    // = (0x3 << 8) | 4 = 0x304
    assert(read_mapword(2, 3) == 0x00000304, "FFI LSb: found nibble 0x3 at offset 4");
    assert(mflag_z == false, "FFI: Z cleared when found")
}

val test_ffi_found_msb : unit -> unit
function test_ffi_found_msb() = {
    map_init();
    // Value: 0x0F000030 — scanning MSb to LSb from offset 31
    // First non-zero nibble from top is at offset 24 (nibble 0xF)
    // Field size: nibble (4 bits, imm = 0b11)
    // Scan direction: MSb to LSb (false)
    write_mapword(0, 3, 0x0F000030);  // value
    write_mapword(1, 3, 0x0000001F);  // start offset = 31
    let _ = mexecute(MFFI(MR2, MW3, MR0, MW3, MR1, MW3, 0b11, false));
    // First non-zero nibble from MSb: offset 24, content = 0xF
    // Result: (0xF << 8) | 24 = 0xF18
    assert(read_mapword(2, 3) == 0x00000F18, "FFI MSb: found nibble 0xF at offset 24");
    assert(mflag_z == false, "FFI: Z cleared when found")
}

val test_ffi_not_found : unit -> unit
function test_ffi_not_found() = {
    map_init();
    // Value: 0x00000000 — no non-zero field
    write_mapword(0, 3, 0x00000000);
    write_mapword(1, 3, 0x00000000);
    let _ = mexecute(MFFI(MR2, MW3, MR0, MW3, MR1, MW3, 0b11, true));
    assert(mflag_z == true, "FFI: Z set when not found")
}

val main : unit -> unit
function main() = {
    test_ffi_found_lsb();
    test_ffi_found_msb();
    test_ffi_not_found()
}
