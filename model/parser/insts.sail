// Parser instruction execution.
// Each instruction adds a clause to this scattered function.
val execute : pinstr -> ExecutionResult

scattered function execute

// NOP: No operation. Does nothing, returns success.
function clause execute(PNOP()) = RETIRE_SUCCESS

// HALT: Terminate parsing.
// PHALT(false) = HALT -- stop parsing, hand off to MAP.
// PHALT(true)  = HALTDROP -- stop parsing, drop the packet.
function clause execute(PHALT(drop)) = {
    parser_halted = true;
    if drop then {
        parser_drop = true;
        RETIRE_DROP
    } else {
        RETIRE_HALT
    }
}

end execute
