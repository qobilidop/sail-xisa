use crate::types::Reg;
use serde::Serialize;

mod array_ser {
    use serde::ser::{Serialize, Serializer, SerializeSeq};

    pub fn serialize<S, T, const N: usize>(arr: &[T; N], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
        T: Serialize,
    {
        let mut seq = serializer.serialize_seq(Some(N))?;
        for item in arr {
            seq.serialize_element(item)?;
        }
        seq.end()
    }
}

/// Complete simulator state. Mirrors `model/parser/state.sail`.
#[derive(Debug, Clone, Serialize)]
pub struct SimState {
    pub pc: u16,
    pub regs: [u128; 5],            // PR0-PR3 + PRN slot (PRN writes discarded)
    pub flag_z: bool,
    pub flag_n: bool,
    pub cursor: u8,
    pub parser_state: u8,
    pub packet_header: Vec<u8>,     // 256 bytes
    pub instruction_mem: Vec<u64>,
    #[serde(with = "array_ser")]
    pub hdr_present: [bool; 32],
    #[serde(with = "array_ser")]
    pub hdr_offset: [u8; 32],
    pub struct0: u128,
    pub halted: bool,
    pub dropped: bool,
    pub step_count: u64,
    pub nxtp_result_pc: u16,
    pub nxtp_result_state: u8,
    pub nxtp_matched: bool,
    #[serde(with = "array_ser")]
    pub tt_valid: [bool; 64],
    #[serde(with = "array_ser")]
    pub tt_state: [u8; 64],
    #[serde(with = "array_ser")]
    pub tt_key: [u32; 64],
    #[serde(with = "array_ser")]
    pub tt_next_pc: [u16; 64],
    #[serde(with = "array_ser")]
    pub tt_next_state: [u8; 64],
    #[serde(with = "array_ser")]
    pub pseek_valid: [bool; 32],
    #[serde(with = "array_ser")]
    pub pseek_class_id: [u8; 32],
    #[serde(with = "array_ser")]
    pub pseek_protocol_value: [u16; 32],
    #[serde(with = "array_ser")]
    pub pseek_hdr_length: [u8; 32],
    #[serde(with = "array_ser")]
    pub pseek_next_proto_off: [u8; 32],
    #[serde(with = "array_ser")]
    pub pseek_next_proto_size: [u8; 32],
    pub map_regs: [u128; 16],
}

impl SimState {
    /// Create a new zeroed state with a 256-byte packet header buffer.
    pub fn new() -> Self {
        SimState {
            pc: 0,
            regs: [0u128; 5],
            flag_z: false,
            flag_n: false,
            cursor: 0,
            parser_state: 0,
            packet_header: vec![0u8; 256],
            instruction_mem: Vec::new(),
            hdr_present: [false; 32],
            hdr_offset: [0u8; 32],
            struct0: 0,
            halted: false,
            dropped: false,
            step_count: 0,
            nxtp_result_pc: 0,
            nxtp_result_state: 0,
            nxtp_matched: false,
            tt_valid: [false; 64],
            tt_state: [0u8; 64],
            tt_key: [0u32; 64],
            tt_next_pc: [0u16; 64],
            tt_next_state: [0u8; 64],
            pseek_valid: [false; 32],
            pseek_class_id: [0u8; 32],
            pseek_protocol_value: [0u16; 32],
            pseek_hdr_length: [0u8; 32],
            pseek_next_proto_off: [0u8; 32],
            pseek_next_proto_size: [0u8; 32],
            map_regs: [0u128; 16],
        }
    }

    /// Read a register value. PRN always returns 0.
    pub fn read_reg(&self, reg: Reg) -> u128 {
        if reg == Reg::PRN {
            return 0;
        }
        self.regs[reg as usize]
    }

    /// Write a register value. Writes to PRN are discarded.
    pub fn write_reg(&mut self, reg: Reg, val: u128) {
        if reg == Reg::PRN {
            return;
        }
        self.regs[reg as usize] = val;
    }

    /// Reset execution state while preserving instruction memory and lookup tables.
    ///
    /// Resets: pc, regs, flags, cursor, parser_state, packet_header, struct0,
    /// halted, dropped, step_count, nxtp_result_*, map_regs.
    /// Preserved: instruction_mem, hdr_present, hdr_offset, tt_*, pseek_*.
    pub fn reset_execution(&mut self) {
        self.pc = 0;
        self.regs = [0u128; 5];
        self.flag_z = false;
        self.flag_n = false;
        self.cursor = 0;
        self.parser_state = 0;
        self.packet_header = vec![0u8; 256];
        self.struct0 = 0;
        self.halted = false;
        self.dropped = false;
        self.step_count = 0;
        self.nxtp_result_pc = 0;
        self.nxtp_result_state = 0;
        self.nxtp_matched = false;
        self.map_regs = [0u128; 16];
    }
}

// ---------------------------------------------------------------------------
// Bit manipulation helpers
// ---------------------------------------------------------------------------
//
// Little-endian bit numbering: bit 0 = LSB, bit 127 = MSB.
// This matches the Sail model (see model/parser/state.sail).

/// Extract `size` bits starting at bit position `offset` (0 = LSB).
///
/// Returns the extracted value right-aligned (zero-extended).
///
/// # Panics
///
/// Panics in debug builds if `offset + size > 128`.
pub fn extract_bits(val: u128, offset: u8, size: u8) -> u128 {
    debug_assert!(
        (offset as u16) + (size as u16) <= 128,
        "extract_bits: offset({offset}) + size({size}) > 128"
    );
    if size == 0 {
        return 0;
    }
    let mask = if size == 128 {
        u128::MAX
    } else {
        (1u128 << size) - 1
    };
    (val >> (offset as u32)) & mask
}

/// Insert `size` bits of `data` at bit position `offset` (0 = LSB).
///
/// Returns the modified value with all other bits preserved.
///
/// # Panics
///
/// Panics in debug builds if `offset + size > 128`.
pub fn insert_bits(val: u128, offset: u8, size: u8, data: u128) -> u128 {
    debug_assert!(
        (offset as u16) + (size as u16) <= 128,
        "insert_bits: offset({offset}) + size({size}) > 128"
    );
    if size == 0 {
        return val;
    }
    let mask: u128 = if size == 128 {
        u128::MAX
    } else {
        (1u128 << size) - 1
    };
    (val & !(mask << (offset as u32))) | ((data & mask) << (offset as u32))
}

/// Extract bits from a packet header buffer at a bit offset relative to cursor.
///
/// `cursor` is a byte offset into `packet`. `bit_offset` is an additional
/// bit offset from that cursor position. `size` is the number of bits to
/// extract (up to 128). The result is right-aligned (zero-extended).
pub fn extract_packet_bits(packet: &[u8], cursor: u8, bit_offset: u16, size: u8) -> u128 {
    if size == 0 {
        return 0;
    }
    let total_bit_start = (cursor as u32) * 8 + (bit_offset as u32);
    let mut result: u128 = 0;
    for i in 0..(size as u32) {
        let bit_pos = total_bit_start + i;
        let byte_idx = (bit_pos / 8) as usize;
        let bit_in_byte = 7 - (bit_pos % 8); // big-endian: bit 0 = MSB of byte
        if byte_idx < packet.len() {
            let bit = ((packet[byte_idx] >> bit_in_byte) & 1) as u128;
            // Place bits from MSB to LSB of result
            result = (result << 1) | bit;
        } else {
            result <<= 1; // out-of-range bytes read as 0
        }
    }
    result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_bits_lsb() {
        // Place 0xFF in the low byte (bits 0..8).
        let val: u128 = 0xFF;
        let extracted = extract_bits(val, 0, 8);
        assert_eq!(extracted, 0xFF, "Expected 0xFF from low byte");
    }

    #[test]
    fn test_extract_bits_middle() {
        // Place 0xABCD in bits 8..24.
        let val: u128 = 0xABCDu128 << 8;
        let extracted = extract_bits(val, 8, 16);
        assert_eq!(extracted, 0xABCD, "Expected 0xABCD from bits 8..24");
    }

    #[test]
    fn test_insert_bits() {
        let val: u128 = 0;
        let result = insert_bits(val, 0, 8, 0xBE);
        // 0xBE should appear in the low byte.
        assert_eq!(result, 0xBEu128);
    }

    #[test]
    fn test_insert_preserves_other_bits() {
        // Start with all ones; insert 0 into bits 8..16.
        let val: u128 = u128::MAX;
        let result = insert_bits(val, 8, 8, 0x00);
        // Bit range 8..16 should be 0, rest 1.
        let expected = u128::MAX & !(0xFFu128 << 8);
        assert_eq!(result, expected, "Insert zeros should clear bits 8..16 only");
    }

    #[test]
    fn test_extract_packet_bits() {
        // IPv4 first byte: version=4 (bits 0-3), IHL=5 (bits 4-7).
        let packet: [u8; 4] = [0x45, 0x00, 0x00, 0x3C];
        let version = extract_packet_bits(&packet, 0, 0, 4);
        assert_eq!(version, 4, "IPv4 version should be 4");
        let ihl = extract_packet_bits(&packet, 0, 4, 4);
        assert_eq!(ihl, 5, "IPv4 IHL should be 5");
    }

    #[test]
    fn test_prn_always_zero() {
        let mut state = SimState::new();
        // Writing to PRN should be discarded.
        state.write_reg(Reg::PRN, 0xDEADBEEF);
        let read_back = state.read_reg(Reg::PRN);
        assert_eq!(read_back, 0, "PRN should always read as 0");
        // The PRN slot in the regs array should remain untouched.
        assert_eq!(state.regs[Reg::PRN as usize], 0, "regs[PRN] should be 0");
    }
}
