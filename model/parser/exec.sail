// Parser fetch-decode-execute loop.

// Execute one step: fetch instruction at ppc, advance ppc, execute.
val parser_step : unit -> ExecutionResult
function parser_step() = {
    let pc_idx : int = unsigned(ppc);
    assert(0 <= pc_idx & pc_idx < 256, "ppc out of instruction memory bounds");
    let instr = pimem[pc_idx];

    // Advance PC before execute (branch instructions may overwrite it)
    ppc = ppc + 0x0001;
    execute(instr)
}

// Run the parser until HALT or DROP.
// Safety limit prevents infinite loops.
val parser_run : unit -> ExecutionResult
function parser_run() = {
    var steps : int = 0;
    var result : ExecutionResult = RETIRE_SUCCESS;
    var done : bool = false;
    while not_bool(done) & steps < 10000 do {
        result = parser_step();
        match result {
            RETIRE_HALT => done = true,
            RETIRE_DROP => done = true,
            RETIRE_SUCCESS => (),
        };
        steps = steps + 1
    };
    result
}
