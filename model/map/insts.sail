
// MAP instruction execution.

val mexecute : minstr -> ExecutionResult
scattered function mexecute

// NOP: No operation.
function clause mexecute(MNOP()) = RETIRE_SUCCESS

// HALT: End MAP execution.
function clause mexecute(MHALT()) = {
    map_halted = true;
    RETIRE_HALT
}

// MOV: Copy 4B word from source to destination.
// If clear_dest, clear the entire 16B destination register first.
function clause mexecute(MMOV(rd, rw, rs, sw, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let rs_idx = mregidx_to_nat(rs);
    let sw_idx = mwordsel_to_nat(sw);
    if clear_dest then write_mapreg(rd_idx, sail_zeros(128));
    let val32 = read_mapword(rs_idx, sw_idx);
    write_mapword(rd_idx, rw_idx, val32);
    RETIRE_SUCCESS
}

// MOVI: Load immediate (up to 32b) into a 4B word.
// If clear_dest, clear the entire 16B destination register first.
function clause mexecute(MMOVI(rd, rw, imm32, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    if clear_dest then write_mapreg(rd_idx, sail_zeros(128));
    write_mapword(rd_idx, rw_idx, imm32);
    RETIRE_SUCCESS
}
