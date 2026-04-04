use wasm_bindgen::prelude::*;
use serde::Serialize;
use xisa::state::SimState;

#[wasm_bindgen]
pub struct Simulator {
    state: SimState,
}

#[derive(Serialize)]
struct StateSnapshot {
    pc: u16,
    regs: [String; 4],
    flag_z: bool,
    flag_n: bool,
    cursor: u8,
    halted: bool,
    dropped: bool,
    step_count: u64,
    packet_header: Vec<u8>,
    struct0: String,
    hdr_present: Vec<bool>,
    hdr_offset: Vec<u8>,
}

#[wasm_bindgen]
impl Simulator {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Simulator {
        Simulator {
            state: SimState::new(),
        }
    }

    pub fn load_program(&mut self, bytes: &[u8]) {
        self.state.instruction_mem.clear();
        let chunks = bytes.chunks_exact(8);
        for chunk in chunks {
            let word = u64::from_be_bytes([
                chunk[0], chunk[1], chunk[2], chunk[3],
                chunk[4], chunk[5], chunk[6], chunk[7],
            ]);
            self.state.instruction_mem.push(word);
        }
        self.state.reset_execution();
    }

    pub fn load_packet(&mut self, packet: &[u8]) {
        let len = packet.len().min(256);
        self.state.packet_header[..len].copy_from_slice(&packet[..len]);
        for b in &mut self.state.packet_header[len..] {
            *b = 0;
        }
    }

    pub fn step(&mut self) -> Result<JsValue, JsValue> {
        xisa::execute::step(&mut self.state)
            .map_err(|e| JsValue::from_str(&e))
            .and_then(|r| {
                serde_wasm_bindgen::to_value(&r)
                    .map_err(|e| JsValue::from_str(&e.to_string()))
            })
    }

    pub fn get_state(&self) -> Result<JsValue, JsValue> {
        let regs = [
            format!("0x{:032x}", self.state.regs[0]),
            format!("0x{:032x}", self.state.regs[1]),
            format!("0x{:032x}", self.state.regs[2]),
            format!("0x{:032x}", self.state.regs[3]),
        ];
        let snapshot = StateSnapshot {
            pc: self.state.pc,
            regs,
            flag_z: self.state.flag_z,
            flag_n: self.state.flag_n,
            cursor: self.state.cursor,
            halted: self.state.halted,
            dropped: self.state.dropped,
            step_count: self.state.step_count,
            packet_header: self.state.packet_header[..256].to_vec(),
            struct0: format!("0x{:032x}", self.state.struct0),
            hdr_present: self.state.hdr_present.to_vec(),
            hdr_offset: self.state.hdr_offset.to_vec(),
        };
        serde_wasm_bindgen::to_value(&snapshot)
            .map_err(|e| JsValue::from_str(&e.to_string()))
    }

    pub fn reset(&mut self) {
        self.state.reset_execution();
    }

    pub fn assemble(&self, source: &str) -> Result<Vec<u8>, JsValue> {
        xisa::assembler::assemble(source)
            .map(|result| {
                let mut bytes = Vec::with_capacity(result.words.len() * 8);
                for word in result.words {
                    bytes.extend_from_slice(&word.to_be_bytes());
                }
                bytes
            })
            .map_err(|errors| {
                let msg = errors
                    .iter()
                    .map(|e| e.to_string())
                    .collect::<Vec<_>>()
                    .join("\n");
                JsValue::from_str(&msg)
            })
    }

    pub fn assemble_and_load(&mut self, source: &str) -> Result<JsValue, JsValue> {
        let result = xisa::assembler::assemble(source).map_err(|errors| {
            let msg = errors
                .iter()
                .map(|e| e.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            JsValue::from_str(&msg)
        })?;

        self.state.instruction_mem = result.words;
        self.state.reset_execution();

        serde_wasm_bindgen::to_value(&result.line_map)
            .map_err(|e| JsValue::from_str(&e.to_string()))
    }
}
