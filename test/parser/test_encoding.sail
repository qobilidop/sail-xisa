// Tests for binary instruction encoding/decoding round-trips.

// Verify encode-then-decode is identity for representative instructions.
val test_roundtrip_nop : unit -> unit
function test_roundtrip_nop() = {
    let instr = PNOP();
    let encoded = encode_pinstr(instr);
    assert(encoded == 0x0000000000000000, "NOP should encode to all zeros");
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "NOP round-trip should be identity")
}

val test_roundtrip_halt : unit -> unit
function test_roundtrip_halt() = {
    let instr = PHALT(true);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "HALT(true) round-trip should be identity")
}

val test_roundtrip_ext : unit -> unit
function test_roundtrip_ext() = {
    let instr = PEXT(PR0, 0x00, 0x0060, 0x10, true);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "EXT round-trip should be identity")
}

val test_roundtrip_br : unit -> unit
function test_roundtrip_br() = {
    let instr = PBR(PCC_AL, 0x0032);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "BR round-trip should be identity")
}

val test_roundtrip_movl : unit -> unit
function test_roundtrip_movl() = {
    let instr = PMOVL(PR2, PR0, 0x00, 0x08, PR1, 0x00, 0x03, true);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "MOVL round-trip should be identity")
}

val test_roundtrip_cnctby : unit -> unit
function test_roundtrip_cnctby() = {
    // Widest instruction (49 field bits)
    let instr = PCNCTBY(PR0, 0x00, PR1, 0x00, 0x04, PR2, 0x04, 0x04);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "CNCTBY round-trip should be identity")
}

val test_roundtrip_pseek : unit -> unit
function test_roundtrip_pseek() = {
    let instr = PPSEEK(PR1, 0x00, PR0, 0x00, 0x10, 0x00);
    let encoded = encode_pinstr(instr);
    let decoded = decode_pinstr(encoded);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == encoded, "PSEEK round-trip should be identity")
}

val test_nop_is_zero : unit -> unit
function test_nop_is_zero() = {
    // Any zeroed memory should decode to NOP and re-encode to zero
    let decoded = decode_pinstr(0x0000000000000000);
    let re_encoded = encode_pinstr(decoded);
    assert(re_encoded == 0x0000000000000000, "zero should decode to NOP and re-encode to zero")
}

val main : unit -> unit
function main() = {
    test_roundtrip_nop();
    test_roundtrip_halt();
    test_roundtrip_ext();
    test_roundtrip_br();
    test_roundtrip_movl();
    test_roundtrip_cnctby();
    test_roundtrip_pseek();
    test_nop_is_zero()
}
