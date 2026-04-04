use serde::{Deserialize, Serialize};

use crate::state::SimState;

/// Parser-observable state for differential testing.
/// Matches the JSON format produced by the Sail C emulator harness.
#[derive(Debug, Serialize, Deserialize, PartialEq)]
pub struct DiffState {
    pub pc: u16,
    pub regs: [String; 4],
    pub flag_z: bool,
    pub flag_n: bool,
    pub cursor: u8,
    pub halted: bool,
    pub dropped: bool,
    pub struct0: String,
    pub hdr_present: Vec<bool>,
    pub hdr_offset: Vec<u8>,
}

impl DiffState {
    /// Extract the parser-observable state from a SimState.
    pub fn from_sim_state(state: &SimState) -> Self {
        DiffState {
            pc: state.pc,
            regs: [
                format!("0x{:032x}", state.regs[0]),
                format!("0x{:032x}", state.regs[1]),
                format!("0x{:032x}", state.regs[2]),
                format!("0x{:032x}", state.regs[3]),
            ],
            flag_z: state.flag_z,
            flag_n: state.flag_n,
            cursor: state.cursor,
            halted: state.halted,
            dropped: state.dropped,
            struct0: format!("0x{:032x}", state.struct0),
            hdr_present: state.hdr_present.to_vec(),
            hdr_offset: state.hdr_offset.to_vec(),
        }
    }

    /// Parse from JSON string (for parsing Sail harness output).
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}
