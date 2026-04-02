
// MAP fetch-decode-execute loop.

val map_step : unit -> ExecutionResult
function map_step() = {
    let pc_idx : int = unsigned(mpc);
    let encoded : bits(64) = read_map_imem_raw(pc_idx);
    let instr : minstr = decode_minstr(encoded);
    mpc = mpc + 0x0001;
    mexecute(instr)
}

val map_run : unit -> ExecutionResult
function map_run() = {
    var steps : int = 0;
    var result : ExecutionResult = RETIRE_SUCCESS;
    var done : bool = false;
    while not_bool(done) & steps < 10000 do {
        result = map_step();
        match result {
            RETIRE_HALT => done = true,
            RETIRE_DROP => done = true,
            RETIRE_SUCCESS => (),
        };
        steps = steps + 1
    };
    result
}
