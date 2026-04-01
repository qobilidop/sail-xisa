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

val main : unit -> unit
function main() = {
    test_sti_basic();
    test_sti_at_offset()
}
