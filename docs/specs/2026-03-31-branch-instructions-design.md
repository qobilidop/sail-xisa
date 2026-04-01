# Branch Instructions + PC Model Design Spec

## Overview

Add a program counter (PC) register, condition code evaluation, and two branch instruction groups (BR<cc> and BRBTST<cc>) to the Parser ISA model. Defer BRNS, BRNXTP, BRBTSTNXTP (need transition table) and the fetch-decode-execute loop.

## New State

- `register ppc : bits16` — Parser program counter. 16 bits is sufficient for instruction addresses. Updated by branch instructions when the condition is met.
- Added to `parser_init()` as `ppc = sail_zeros(16)`.

## Condition Code Evaluation

**Enum `pcond`** — condition codes for BR instructions:
- `PCC_EQ` — branch if Z=1 (equal)
- `PCC_NEQ` — branch if Z=0 (not equal)
- `PCC_LT` — branch if N=1 (less than)
- `PCC_GT` — branch if N=0 and Z=0 (greater than)
- `PCC_GE` — branch if N=0 (greater or equal)
- `PCC_LE` — branch if N=1 or Z=1 (less or equal)
- `PCC_AL` — branch unconditionally (always)

**Function `eval_pcond(cc) -> bool`** — evaluates the condition against current `pflag_z` and `pflag_n`.

## Bit-Test Condition

**Enum `pbtcond`** — condition codes for BRBTST instructions:
- `PBT_CLR` — branch if tested bit is 0
- `PBT_SET` — branch if tested bit is 1

## Instructions

### PBR (Section 3.12.18 - BR<cc>)

Branch to target address if condition is met.

- **Union clause:** `PBR : (pcond, bits16)` — (condition, target_address)
- **Semantics:** If `eval_pcond(cc)` is true, set `ppc = target`. Otherwise, no change.
- **Returns:** `RETIRE_SUCCESS` always.

### PBRBTST (Section 3.12.18 - BRBTST<cc>)

Test a single bit in a register and branch if condition is met.

- **Union clause:** `PBRBTST : (pbtcond, pregidx, bits8, bits16)` — (condition, src_reg, bit_offset, target_address)
- **Semantics:** Extract bit at `src_reg[bit_offset]`. If condition matches (CLR and bit=0, or SET and bit=1), set `ppc = target`. Otherwise, no change.
- **Returns:** `RETIRE_SUCCESS` always.

## Simplifications

- No BRNS (branch to next state via transition rule) — needs transition table model.
- No BRNXTP (branch to next protocol with JumpMode) — needs transition table model.
- No BRBTSTNXTP — combination of above.
- No fetch-decode-execute loop — tests call `execute()` directly. The PC is updated but not used to fetch the next instruction. This will be addressed in a future iteration.

## Code Changes

- **`model/parser/types.sail`**: Add `pcond` enum, `pbtcond` enum, `PBR` and `PBRBTST` union clauses.
- **`model/parser/state.sail`**: Add `ppc` register, `eval_pcond` function, update `parser_init`.
- **`model/parser/insts.sail`**: Add execute clauses for PBR and PBRBTST.
- **`test/parser/test_br.sail`**: Tests for all 7 condition codes + unconditional, branch taken/not taken, PC update verification.
- **`test/parser/test_brbtst.sail`**: Tests for bit-test clear/set, branch taken/not taken.
- **`docs/coverage.md`**: Update BR variants status.
- **`docs/todo.md`**: Note deferred BR variants.
