
// Tests for MAP binary instruction encoding/decoding round-trips.

val test_roundtrip_nop : unit -> unit
function test_roundtrip_nop() = {
    let instr = MNOP();
    let encoded = encode_minstr(instr);
    assert(encoded == 0x0000000000000000, "NOP should encode to all zeros");
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "NOP round-trip should be identity")
}

val test_roundtrip_halt : unit -> unit
function test_roundtrip_halt() = {
    let instr = MHALT();
    let encoded = encode_minstr(instr);
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "HALT round-trip should be identity")
}

val test_roundtrip_mov : unit -> unit
function test_roundtrip_mov() = {
    let instr = MMOV(MR1, MW3, MR0, MW3, true);
    let encoded = encode_minstr(instr);
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "MOV round-trip should be identity")
}

val test_roundtrip_add : unit -> unit
function test_roundtrip_add() = {
    let instr = MADD(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                     MR1, MW3, 0b00000, 0b01000, true, false, false);
    let encoded = encode_minstr(instr);
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "ADD round-trip should be identity")
}

val test_roundtrip_br : unit -> unit
function test_roundtrip_br() = {
    let instr = MBR(MCC_AL, MR0, MW3);
    let encoded = encode_minstr(instr);
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "BR round-trip should be identity")
}

val test_roundtrip_brbtst : unit -> unit
function test_roundtrip_brbtst() = {
    let instr = MBRBTST(MBT_SET, MR5, MW1, 0b10101, 0x1234);
    let encoded = encode_minstr(instr);
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "BRBTST round-trip should be identity")
}

val test_nop_is_zero : unit -> unit
function test_nop_is_zero() = {
    let decoded = decode_minstr(0x0000000000000000);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == 0x0000000000000000, "zero should decode to NOP and re-encode to zero")
}

val main : unit -> unit
function main() = {
    test_roundtrip_nop();
    test_roundtrip_halt();
    test_roundtrip_mov();
    test_roundtrip_add();
    test_roundtrip_br();
    test_roundtrip_brbtst();
    test_nop_is_zero()
}
