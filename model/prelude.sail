default Order dec

$include <prelude.sail>
$include <string.sail>

// Bitvector type aliases
type bits8   = bits(8)
type bits16  = bits(16)
type bits128 = bits(128)

// Execution result for instructions
enum ExecutionResult = {
    RETIRE_SUCCESS,
    RETIRE_HALT,
    RETIRE_DROP
}
