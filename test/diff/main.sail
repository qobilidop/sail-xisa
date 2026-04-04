// Dummy main for the differential testing harness.
// The real entry point is in harness.c.
// We must reference the functions we need so Sail doesn't dead-code-eliminate them.
val main : unit -> unit
function main() = {
    parser_init();
    write_pimem_raw(0, sail_zeros(64));
    let _ = parser_run();
    ()
}
