// Parser instruction execution.
// Each instruction adds a clause to this scattered function.
val execute : pinstr -> ExecutionResult

scattered function execute

// NOP: No operation. Does nothing, returns success.
function clause execute(PNOP()) = RETIRE_SUCCESS

end execute
