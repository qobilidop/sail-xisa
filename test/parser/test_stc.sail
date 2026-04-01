// Tests for STC and STCI (cursor manipulation) instructions.

// STCI: increment cursor from 0.
val test_stci_basic : unit -> unit
function test_stci_basic() = {
    parser_init();
    pcursor = 0x00;
    let _ = execute(PSTCI(0x000E));
    assert(pcursor == 0x0E, "STCI should set cursor to 14")
}

// STCI: increment cursor from non-zero position.
val test_stci_from_nonzero : unit -> unit
function test_stci_from_nonzero() = {
    parser_init();
    pcursor = 0x0A;
    let _ = execute(PSTCI(0x0004));
    assert(pcursor == 0x0E, "STCI should increment cursor from 10 to 14")
}

val main : unit -> unit
function main() = {
    test_stci_basic();
    test_stci_from_nonzero()
}
