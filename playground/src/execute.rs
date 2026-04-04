use crate::decode;
use crate::state::{extract_bits, extract_packet_bits, insert_bits, SimState};
use crate::types::*;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Evaluate a condition code against the current flags.
fn eval_condition(state: &SimState, cc: Condition) -> bool {
    match cc {
        Condition::Eq => state.flag_z,
        Condition::Neq => !state.flag_z,
        Condition::Lt => state.flag_n,
        Condition::Gt => !state.flag_n && !state.flag_z,
        Condition::Ge => !state.flag_n,
        Condition::Le => state.flag_n || state.flag_z,
        Condition::Al => true,
    }
}

/// Search the transition table for a matching (parser_state, key) entry.
/// If found, populate nxtp_result_pc, nxtp_result_state, nxtp_matched.
fn nxtp_lookup(state: &mut SimState, protocol_key: u32) {
    state.nxtp_matched = false;
    for i in 0..64 {
        if state.tt_valid[i]
            && state.tt_state[i] == state.parser_state
            && state.tt_key[i] == protocol_key
        {
            state.nxtp_result_pc = state.tt_next_pc[i];
            state.nxtp_result_state = state.tt_next_state[i];
            state.nxtp_matched = true;
            return;
        }
    }
}

/// Apply the NXTP branch logic based on jump mode and match result.
fn apply_nxtp_branch(state: &mut SimState, jm: u8, addr_or_rule: u16) {
    if state.nxtp_matched {
        state.pc = state.nxtp_result_pc;
        state.parser_state = state.nxtp_result_state;
    } else {
        match jm {
            0 | 1 => { /* no jump */ }
            2 => {
                state.pc = addr_or_rule;
            }
            3 => {
                // Look up rule index in transition table
                let rule_idx = addr_or_rule as usize;
                if rule_idx < 64 && state.tt_valid[rule_idx] {
                    state.pc = state.tt_next_pc[rule_idx];
                    state.parser_state = state.tt_next_state[rule_idx];
                }
            }
            _ => {}
        }
    }
}

/// If `cd` is true, zero the register.
fn maybe_clear(state: &mut SimState, reg: Reg, cd: bool) {
    if cd {
        state.write_reg(reg, 0);
    }
}

/// Create a size-bit mask.
fn size_mask(size: u8) -> u128 {
    if size == 0 {
        return 0;
    }
    if size >= 128 {
        return u128::MAX;
    }
    (1u128 << size) - 1
}

// ---------------------------------------------------------------------------
// Main execute function
// ---------------------------------------------------------------------------

/// Execute a single instruction, mutating state. Returns the execution outcome.
pub fn execute(state: &mut SimState, inst: &Instruction) -> ExecResult {
    match inst {
        // -- Control --
        Instruction::Nop => ExecResult::Success,

        Instruction::Halt { drop } => {
            state.halted = true;
            if *drop {
                state.dropped = true;
                ExecResult::Drop
            } else {
                ExecResult::Halt
            }
        }

        // -- Data movement --
        Instruction::Mov { rd, doff, rs, soff, size, cd } => {
            maybe_clear(state, *rd, *cd);
            let data = extract_bits(state.read_reg(*rs), *soff, *size);
            let val = insert_bits(state.read_reg(*rd), *doff, *size, data);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::Movi { rd, doff, imm, size, cd } => {
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), *doff, *size, *imm as u128);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::Ext { rd, doff, soff, size, cd } => {
            maybe_clear(state, *rd, *cd);
            let data = extract_packet_bits(&state.packet_header, state.cursor, *soff, *size);
            let val = insert_bits(state.read_reg(*rd), *doff, *size, data);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::ExtNxtp { rd, soff, size, cd } => {
            maybe_clear(state, *rd, *cd);
            let data = extract_packet_bits(&state.packet_header, state.cursor, *soff, *size);
            let val = insert_bits(state.read_reg(*rd), 0, *size, data);
            state.write_reg(*rd, val);
            nxtp_lookup(state, data as u32);
            ExecResult::Success
        }

        Instruction::MovL { rd, rs1, o1, sz1, rs2, o2, sz2, cd } => {
            maybe_clear(state, *rd, *cd);
            let data = extract_bits(state.read_reg(*rs1), *o1, *sz1);
            let offset_val = extract_bits(state.read_reg(*rs2), *o2, *sz2) as u8;
            let dest_off = o1.wrapping_add(offset_val);
            let val = insert_bits(state.read_reg(*rd), dest_off, *sz1, data);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::MovLI { rd, rs, off, size, imm, cd } => {
            maybe_clear(state, *rd, *cd);
            let data = extract_bits(state.read_reg(*rs), *off, *size);
            let dest_off = off.wrapping_add(*imm);
            let val = insert_bits(state.read_reg(*rd), dest_off, *size, data);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::MovLII { rd, rs, off, size, imm, isz, cd } => {
            maybe_clear(state, *rd, *cd);
            let data = extract_bits(state.read_reg(*rs), *off, *size);
            let dest_off = off.wrapping_add(*imm);
            let val = insert_bits(state.read_reg(*rd), dest_off, *isz, data);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::MovR { rd, rs1, o1, sz1, rs2, o2, sz2, cd } => {
            maybe_clear(state, *rd, *cd);
            let data = extract_bits(state.read_reg(*rs1), *o1, *sz1);
            let offset_val = extract_bits(state.read_reg(*rs2), *o2, *sz2) as u8;
            let dest_off = o1.saturating_sub(offset_val);
            let val = insert_bits(state.read_reg(*rd), dest_off, *sz1, data);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::MovRI { rd, rs, off, size, imm, cd } => {
            maybe_clear(state, *rd, *cd);
            let data = extract_bits(state.read_reg(*rs), *off, *size);
            let dest_off = off.saturating_sub(*imm);
            let val = insert_bits(state.read_reg(*rd), dest_off, *size, data);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::MovRII { rd, rs, off, size, imm, isz, cd } => {
            maybe_clear(state, *rd, *cd);
            let data = extract_bits(state.read_reg(*rs), *off, *size);
            let dest_off = off.saturating_sub(*imm);
            let val = insert_bits(state.read_reg(*rd), dest_off, *isz, data);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        // -- Arithmetic --
        Instruction::Add { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            let a = extract_bits(state.read_reg(*rs1), *s1off, *size);
            let b = extract_bits(state.read_reg(*rs2), *s2off, *size);
            let result = (a.wrapping_add(b)) & size_mask(*size);
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), *doff, *size, result);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::AddI { rd, rs, imm, size, cd } => {
            let a = extract_bits(state.read_reg(*rs), 0, *size);
            let result = (a.wrapping_add(*imm as u128)) & size_mask(*size);
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), 0, *size, result);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::Sub { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            let a = extract_bits(state.read_reg(*rs1), *s1off, *size);
            let b = extract_bits(state.read_reg(*rs2), *s2off, *size);
            let result = (a.wrapping_sub(b)) & size_mask(*size);
            state.flag_z = result == 0;
            state.flag_n = if *size > 0 { (result >> (*size - 1)) & 1 == 1 } else { false };
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), *doff, *size, result);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::SubI { rd, rs, imm, size, cd } => {
            let a = extract_bits(state.read_reg(*rs), 0, *size);
            let result = (a.wrapping_sub(*imm as u128)) & size_mask(*size);
            state.flag_z = result == 0;
            state.flag_n = if *size > 0 { (result >> (*size - 1)) & 1 == 1 } else { false };
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), 0, *size, result);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::SubII { rd, imm, rs, size, cd } => {
            let b = extract_bits(state.read_reg(*rs), 0, *size);
            let result = ((*imm as u128).wrapping_sub(b)) & size_mask(*size);
            state.flag_z = result == 0;
            state.flag_n = if *size > 0 { (result >> (*size - 1)) & 1 == 1 } else { false };
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), 0, *size, result);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        // -- Logic --
        Instruction::And { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            let a = extract_bits(state.read_reg(*rs1), *s1off, *size);
            let b = extract_bits(state.read_reg(*rs2), *s2off, *size);
            let result = a & b;
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), *doff, *size, result);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::AndI { rd, rs, imm, size, cd } => {
            let a = extract_bits(state.read_reg(*rs), 0, *size);
            let result = a & (*imm as u128);
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), 0, *size, result);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::Or { rd, doff, rs1, s1off, rs2, s2off, size, cd } => {
            let a = extract_bits(state.read_reg(*rs1), *s1off, *size);
            let b = extract_bits(state.read_reg(*rs2), *s2off, *size);
            let result = a | b;
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), *doff, *size, result);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::OrI { rd, rs, imm, size, cd } => {
            let a = extract_bits(state.read_reg(*rs), 0, *size);
            let result = a | (*imm as u128);
            state.flag_z = result == 0;
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), 0, *size, result);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        // -- Compare --
        Instruction::Cmp { rs1, s1off, rs2, s2off, size } => {
            let a = extract_bits(state.read_reg(*rs1), *s1off, *size);
            let b = extract_bits(state.read_reg(*rs2), *s2off, *size);
            let result = (a.wrapping_sub(b)) & size_mask(*size);
            state.flag_z = result == 0;
            state.flag_n = if *size > 0 { (result >> (*size - 1)) & 1 == 1 } else { false };
            ExecResult::Success
        }

        Instruction::CmpIBy { rs, soff, imm, size } => {
            let bit_off = (*soff as u8).wrapping_mul(8);
            let a = extract_bits(state.read_reg(*rs), bit_off, *size);
            let result = (a.wrapping_sub(*imm as u128)) & size_mask(*size);
            state.flag_z = result == 0;
            state.flag_n = if *size > 0 { (result >> (*size - 1)) & 1 == 1 } else { false };
            ExecResult::Success
        }

        Instruction::CmpIBi { rs, soff, imm, size } => {
            let a = extract_bits(state.read_reg(*rs), *soff, *size);
            let result = (a.wrapping_sub(*imm as u128)) & size_mask(*size);
            state.flag_z = result == 0;
            state.flag_n = if *size > 0 { (result >> (*size - 1)) & 1 == 1 } else { false };
            ExecResult::Success
        }

        // -- Concatenation --
        Instruction::CnctBy { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd } => {
            let v1 = extract_bits(state.read_reg(*rs1), (*s1off).wrapping_mul(8), (*s1sz).wrapping_mul(8));
            let v2 = extract_bits(state.read_reg(*rs2), (*s2off).wrapping_mul(8), (*s2sz).wrapping_mul(8));
            let s2_bits = (*s2sz as u32) * 8;
            let combined = (v1 << s2_bits) | v2;
            let total_sz = ((*s1sz as u8).wrapping_mul(8)).wrapping_add((*s2sz as u8).wrapping_mul(8));
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), (*doff).wrapping_mul(8), total_sz, combined);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::CnctBi { rd, doff, rs1, s1off, s1sz, rs2, s2off, s2sz, cd } => {
            let v1 = extract_bits(state.read_reg(*rs1), *s1off, *s1sz);
            let v2 = extract_bits(state.read_reg(*rs2), *s2off, *s2sz);
            let combined = (v1 << (*s2sz as u32)) | v2;
            let total_sz = s1sz.wrapping_add(*s2sz);
            maybe_clear(state, *rd, *cd);
            let val = insert_bits(state.read_reg(*rd), *doff, total_sz, combined);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        // -- Branch --
        Instruction::Br { cc, target } => {
            if eval_condition(state, *cc) {
                state.pc = *target;
            }
            ExecResult::Success
        }

        Instruction::BrBtst { btcc, rs, boff, target } => {
            let bit = extract_bits(state.read_reg(*rs), *boff, 1);
            let take = match btcc {
                BitTestCond::Clear => bit == 0,
                BitTestCond::Set => bit == 1,
            };
            if take {
                state.pc = *target;
            }
            ExecResult::Success
        }

        Instruction::BrNs { cc, rule } => {
            if eval_condition(state, *cc) {
                let rule_idx = *rule as usize;
                if rule_idx < 64 && state.tt_valid[rule_idx] {
                    state.pc = state.tt_next_pc[rule_idx];
                    state.parser_state = state.tt_next_state[rule_idx];
                }
            }
            ExecResult::Success
        }

        Instruction::BrNxtp { cc, jm, addr_or_rule } => {
            if eval_condition(state, *cc) {
                apply_nxtp_branch(state, *jm, *addr_or_rule);
            }
            ExecResult::Success
        }

        Instruction::BrBtstNxtp { btcc, rs, boff, jm, addr_or_rule } => {
            let bit = extract_bits(state.read_reg(*rs), *boff, 1);
            let take = match btcc {
                BitTestCond::Clear => bit == 0,
                BitTestCond::Set => bit == 1,
            };
            if take {
                apply_nxtp_branch(state, *jm, *addr_or_rule);
            }
            ExecResult::Success
        }

        Instruction::BrBtstNs { btcc, rs, boff, rule } => {
            let bit = extract_bits(state.read_reg(*rs), *boff, 1);
            let take = match btcc {
                BitTestCond::Clear => bit == 0,
                BitTestCond::Set => bit == 1,
            };
            if take {
                let rule_idx = *rule as usize;
                if rule_idx < 64 && state.tt_valid[rule_idx] {
                    state.pc = state.tt_next_pc[rule_idx];
                    state.parser_state = state.tt_next_state[rule_idx];
                }
            }
            ExecResult::Success
        }

        // -- Header / Cursor --
        Instruction::Sth { pid, oid, halt } => {
            let idx = *pid as usize;
            if idx < 32 {
                state.hdr_present[idx] = true;
                state.hdr_offset[idx] = *oid;
            }
            if *halt {
                state.halted = true;
                return ExecResult::Halt;
            }
            ExecResult::Success
        }

        Instruction::Stc { rs, soff, ssz, shift, incr } => {
            let val = extract_bits(state.read_reg(*rs), *soff, *ssz) as u8;
            let new_cursor = val.wrapping_add(*incr) << shift;
            state.cursor = state.cursor.wrapping_add(new_cursor);
            ExecResult::Success
        }

        Instruction::Stci { incr } => {
            state.cursor = state.cursor.wrapping_add(*incr as u8);
            ExecResult::Success
        }

        Instruction::Stch { incr, pid, oid, halt } => {
            state.cursor = state.cursor.wrapping_add(*incr as u8);
            let idx = *pid as usize;
            if idx < 32 {
                state.hdr_present[idx] = true;
                state.hdr_offset[idx] = *oid;
            }
            if *halt {
                state.halted = true;
                return ExecResult::Halt;
            }
            ExecResult::Success
        }

        Instruction::Sthc { incr, pid, oid } => {
            let idx = *pid as usize;
            if idx < 32 {
                state.hdr_present[idx] = true;
                state.hdr_offset[idx] = *oid;
            }
            state.cursor = state.cursor.wrapping_add(*incr as u8);
            ExecResult::Success
        }

        // -- Store to Struct-0 --
        Instruction::St { rs, soff, doff, size, halt } => {
            let data = extract_bits(state.read_reg(*rs), *soff, *size);
            state.struct0 = insert_bits(state.struct0, *doff, *size, data);
            if *halt {
                state.halted = true;
                return ExecResult::Halt;
            }
            ExecResult::Success
        }

        Instruction::StI { imm, doff, size } => {
            state.struct0 = insert_bits(state.struct0, *doff, *size, *imm as u128);
            ExecResult::Success
        }

        // -- MAP interface --
        Instruction::ExtMap { midx, doff, poff, size } => {
            let idx = *midx as usize;
            let data = extract_packet_bits(&state.packet_header, state.cursor, *poff, *size);
            if idx < 16 {
                state.map_regs[idx] = insert_bits(state.map_regs[idx], *doff, *size, data);
            }
            ExecResult::Success
        }

        Instruction::MovMap { midx, doff, rs, soff, size } => {
            let idx = *midx as usize;
            let data = extract_bits(state.read_reg(*rs), *soff, *size);
            if idx < 16 {
                state.map_regs[idx] = insert_bits(state.map_regs[idx], *doff, *size, data);
            }
            ExecResult::Success
        }

        // -- Transition / NXTP --
        Instruction::Nxtp { rs, soff, size } => {
            let key = extract_bits(state.read_reg(*rs), *soff, *size) as u32;
            nxtp_lookup(state, key);
            ExecResult::Success
        }

        // -- PSEEK --
        Instruction::Pseek { rd, doff, rs, soff, size, cid } => {
            let protocol = extract_bits(state.read_reg(*rs), *soff, *size) as u16;
            let result = pseek_scan(state, *cid, protocol);
            let val = insert_bits(state.read_reg(*rd), *doff, 16, result as u128);
            state.write_reg(*rd, val);
            ExecResult::Success
        }

        Instruction::PseekNxtp { rd, doff, rs, soff, size, cid } => {
            let protocol = extract_bits(state.read_reg(*rs), *soff, *size) as u16;
            let result = pseek_scan(state, *cid, protocol);
            let val = insert_bits(state.read_reg(*rd), *doff, 16, result as u128);
            state.write_reg(*rd, val);
            nxtp_lookup(state, result as u32);
            ExecResult::Success
        }
    }
}

// ---------------------------------------------------------------------------
// PSEEK scan
// ---------------------------------------------------------------------------

/// Walk the PSEEK table starting from `start_cid`, following protocol chains.
/// Returns the final protocol value after all matching entries are consumed.
fn pseek_scan(state: &mut SimState, start_cid: u8, initial_protocol: u16) -> u16 {
    let mut protocol = initial_protocol;
    let mut cid = start_cid;

    loop {
        let mut found = false;
        for i in 0..32 {
            if state.pseek_valid[i]
                && state.pseek_class_id[i] == cid
                && state.pseek_protocol_value[i] == protocol
            {
                // Advance cursor by header length
                state.cursor = state.cursor.wrapping_add(state.pseek_hdr_length[i]);
                // Read next protocol from packet
                let next_off = state.pseek_next_proto_off[i];
                let next_size = state.pseek_next_proto_size[i];
                protocol = extract_packet_bits(
                    &state.packet_header,
                    state.cursor,
                    next_off as u16,
                    next_size,
                ) as u16;
                cid = cid.wrapping_add(1);
                found = true;
                break;
            }
        }
        if !found {
            break;
        }
    }

    protocol
}

// ---------------------------------------------------------------------------
// Step function
// ---------------------------------------------------------------------------

/// Execute one simulation step: fetch, decode, execute the instruction at PC.
pub fn step(state: &mut SimState) -> Result<StepResult, String> {
    if state.halted {
        return Err("Parser is halted".to_string());
    }

    let pc = state.pc as usize;
    if pc >= state.instruction_mem.len() {
        return Err(format!(
            "PC {} out of bounds (instruction memory size: {})",
            pc,
            state.instruction_mem.len()
        ));
    }

    let word = state.instruction_mem[pc];
    let inst = decode::decode(word).map_err(|e| e.message)?;

    // Snapshot registers and flags for change detection
    let old_regs = state.regs;
    let old_flag_z = state.flag_z;
    let old_flag_n = state.flag_n;

    // Advance PC before execution (branches will overwrite)
    state.pc += 1;

    let _result = execute(state, &inst);

    state.step_count += 1;

    // Detect register changes
    let reg_names = ["PR0", "PR1", "PR2", "PR3"];
    let mut reg_changes = Vec::new();
    for i in 0..4 {
        if state.regs[i] != old_regs[i] {
            reg_changes.push((
                reg_names[i].to_string(),
                format!("0x{:032x}", state.regs[i]),
            ));
        }
    }

    let flags_changed = state.flag_z != old_flag_z || state.flag_n != old_flag_n;

    Ok(StepResult {
        instruction: format!("{:?}", inst),
        halted: state.halted,
        dropped: state.dropped,
        reg_changes,
        flags_changed,
    })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::encode::encode;
    use crate::state::SimState;

    #[test]
    fn test_nop() {
        let mut state = SimState::new();
        let result = execute(&mut state, &Instruction::Nop);
        assert_eq!(result, ExecResult::Success);
    }

    #[test]
    fn test_halt() {
        let mut state = SimState::new();
        let result = execute(&mut state, &Instruction::Halt { drop: false });
        assert_eq!(result, ExecResult::Halt);
        assert!(state.halted);
        assert!(!state.dropped);
    }

    #[test]
    fn test_halt_drop() {
        let mut state = SimState::new();
        let result = execute(&mut state, &Instruction::Halt { drop: true });
        assert_eq!(result, ExecResult::Drop);
        assert!(state.halted);
        assert!(state.dropped);
    }

    #[test]
    fn test_movi_and_mov() {
        let mut state = SimState::new();
        // MOVI: put 0xABCD into PR0 at offset 0, size 16
        execute(
            &mut state,
            &Instruction::Movi {
                rd: Reg::PR0,
                doff: 0,
                imm: 0xABCD,
                size: 16,
                cd: false,
            },
        );
        let val = extract_bits(state.read_reg(Reg::PR0), 0, 16);
        assert_eq!(val, 0xABCD);

        // MOV: copy PR0[0..16] to PR1[0..16]
        execute(
            &mut state,
            &Instruction::Mov {
                rd: Reg::PR1,
                doff: 0,
                rs: Reg::PR0,
                soff: 0,
                size: 16,
                cd: false,
            },
        );
        let val = extract_bits(state.read_reg(Reg::PR1), 0, 16);
        assert_eq!(val, 0xABCD);
    }

    #[test]
    fn test_add_sets_zero_flag() {
        let mut state = SimState::new();
        // PR0 = 0, PR1 = 0. Add them (8 bits) -> result = 0, flag_z = true
        let result = execute(
            &mut state,
            &Instruction::Add {
                rd: Reg::PR2,
                doff: 0,
                rs1: Reg::PR0,
                s1off: 0,
                rs2: Reg::PR1,
                s2off: 0,
                size: 8,
                cd: false,
            },
        );
        assert_eq!(result, ExecResult::Success);
        assert!(state.flag_z, "0 + 0 should set zero flag");
    }

    #[test]
    fn test_sub_sets_negative_flag() {
        let mut state = SimState::new();
        // PR0 = 1 (8-bit at offset 0)
        execute(
            &mut state,
            &Instruction::Movi {
                rd: Reg::PR0,
                doff: 0,
                imm: 1,
                size: 8,
                cd: false,
            },
        );
        // PR1 = 2
        execute(
            &mut state,
            &Instruction::Movi {
                rd: Reg::PR1,
                doff: 0,
                imm: 2,
                size: 8,
                cd: false,
            },
        );
        // Sub: PR0 - PR1 = 1 - 2 = -1 (0xFF in 8-bit), MSB set
        execute(
            &mut state,
            &Instruction::Sub {
                rd: Reg::PR2,
                doff: 0,
                rs1: Reg::PR0,
                s1off: 0,
                rs2: Reg::PR1,
                s2off: 0,
                size: 8,
                cd: false,
            },
        );
        assert!(state.flag_n, "1 - 2 should set negative flag");
        assert!(!state.flag_z, "result 0xFF is not zero");
    }

    #[test]
    fn test_branch_taken() {
        let mut state = SimState::new();
        state.pc = 5;
        // Al (always) branch to address 42
        execute(
            &mut state,
            &Instruction::Br {
                cc: Condition::Al,
                target: 42,
            },
        );
        assert_eq!(state.pc, 42);
    }

    #[test]
    fn test_branch_not_taken() {
        let mut state = SimState::new();
        state.pc = 5;
        state.flag_z = false;
        // Eq branch should not be taken when flag_z is false
        execute(
            &mut state,
            &Instruction::Br {
                cc: Condition::Eq,
                target: 42,
            },
        );
        assert_eq!(state.pc, 5, "PC should not change when branch not taken");
    }

    #[test]
    fn test_ext_from_packet() {
        let mut state = SimState::new();
        state.packet_header[0] = 0x45;
        state.cursor = 0;
        execute(
            &mut state,
            &Instruction::Ext {
                rd: Reg::PR0,
                doff: 0,
                soff: 0,
                size: 8,
                cd: true,
            },
        );
        let val = extract_bits(state.read_reg(Reg::PR0), 0, 8);
        assert_eq!(val, 0x45, "Expected 0x45 from packet byte 0");
    }

    #[test]
    fn test_sth_sets_header() {
        let mut state = SimState::new();
        execute(
            &mut state,
            &Instruction::Sth {
                pid: 3,
                oid: 10,
                halt: false,
            },
        );
        assert!(state.hdr_present[3]);
        assert_eq!(state.hdr_offset[3], 10);
        assert!(!state.halted);
    }

    #[test]
    fn test_stci_advances_cursor() {
        let mut state = SimState::new();
        state.cursor = 5;
        execute(&mut state, &Instruction::Stci { incr: 14 });
        assert_eq!(state.cursor, 19);
    }

    #[test]
    fn test_step_function() {
        let mut state = SimState::new();
        // Program: MOVI PR0, 0, 0x1234, 16; HALT
        let movi_inst = Instruction::Movi {
            rd: Reg::PR0,
            doff: 0,
            imm: 0x1234,
            size: 16,
            cd: false,
        };
        let halt_inst = Instruction::Halt { drop: false };
        state.instruction_mem.push(encode(&movi_inst));
        state.instruction_mem.push(encode(&halt_inst));

        // Step 1: MOVI
        let r = step(&mut state).unwrap();
        assert!(!r.halted);
        assert_eq!(state.pc, 1);
        let val = extract_bits(state.read_reg(Reg::PR0), 0, 16);
        assert_eq!(val, 0x1234);

        // Step 2: HALT
        let r = step(&mut state).unwrap();
        assert!(r.halted);
        assert!(!r.dropped);
    }
}
