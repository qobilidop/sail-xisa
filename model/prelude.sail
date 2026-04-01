default Order dec

$include <prelude.sail>
$include <string.sail>

// Bitvector type aliases
type bits4   = bits(4)
type bits8   = bits(8)
type bits16  = bits(16)
type bits128 = bits(128)

// Execution result for instructions
enum ExecutionResult = { RETIRE_SUCCESS, RETIRE_HALT, RETIRE_DROP }

// Equality for ExecutionResult (needed for assertions in tests).
val eq_ExecutionResult : (ExecutionResult, ExecutionResult) -> bool
function eq_ExecutionResult(a, b) = match (a, b) {
    (RETIRE_SUCCESS, RETIRE_SUCCESS) => true,
    (RETIRE_HALT, RETIRE_HALT) => true,
    (RETIRE_DROP, RETIRE_DROP) => true,
    (_, _) => false,
}

overload operator == = {eq_ExecutionResult}
