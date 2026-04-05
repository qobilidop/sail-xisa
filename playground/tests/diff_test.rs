use std::io::Write;
use std::process::Command;

use proptest::prelude::*;

use xisa::assembler::assemble;
use xisa::diff::DiffState;
use xisa::encode::encode;
use xisa::execute;
use xisa::state::SimState;
use xisa::types::*;

/// Path to the Sail C emulator harness binary (relative to repo root).
const HARNESS_PATH: &str = "build/test/sail-c-emu-harness";

/// Get the repo root (parent of the playground/ crate directory).
fn repo_root() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf()
}

/// Check if the harness binary exists.
fn harness_available() -> bool {
    repo_root().join(HARNESS_PATH).exists()
}

fn harness_path() -> std::path::PathBuf {
    repo_root().join(HARNESS_PATH)
}

/// Run a program on the Rust simulator and return the DiffState.
fn run_rust(program_bytes: &[u8], packet: &[u8]) -> DiffState {
    let mut state = SimState::new();

    for chunk in program_bytes.chunks_exact(8) {
        let word = u64::from_be_bytes([
            chunk[0], chunk[1], chunk[2], chunk[3],
            chunk[4], chunk[5], chunk[6], chunk[7],
        ]);
        state.instruction_mem.push(word);
    }

    let len = packet.len().min(256);
    state.packet_header[..len].copy_from_slice(&packet[..len]);

    loop {
        match execute::step(&mut state) {
            Ok(result) => {
                if result.halted || result.dropped {
                    break;
                }
            }
            Err(e) => panic!("Rust simulator error: {}", e),
        }
    }

    DiffState::from_sim_state(&state)
}

/// Run a program on the Sail C emulator harness and return the DiffState.
fn run_sail(program_bytes: &[u8], packet: &[u8]) -> DiffState {
    let mut prog_file = tempfile::NamedTempFile::new().unwrap();
    prog_file.write_all(program_bytes).unwrap();
    prog_file.flush().unwrap();

    let mut pkt_file = tempfile::NamedTempFile::new().unwrap();
    pkt_file.write_all(packet).unwrap();
    pkt_file.flush().unwrap();

    let output = Command::new(harness_path())
        .arg(prog_file.path())
        .arg(pkt_file.path())
        .output()
        .expect("Failed to run sail-c-emu-harness");

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        panic!("sail-c-emu-harness failed: {}", stderr);
    }

    let stdout = String::from_utf8(output.stdout).unwrap();
    DiffState::from_json(&stdout)
        .unwrap_or_else(|e| panic!("Failed to parse Sail JSON: {}\nOutput: {}", e, stdout))
}

/// Assemble source, run on both simulators, compare.
fn diff_test(source: &str, packet: &[u8]) {
    if !harness_available() {
        eprintln!("Skipping diff test: sail-c-emu-harness not found at {}", HARNESS_PATH);
        return;
    }

    let result = assemble(source).expect("Assembly failed");
    let mut bytes = Vec::new();
    for word in &result.words {
        bytes.extend_from_slice(&word.to_be_bytes());
    }

    let rust_state = run_rust(&bytes, packet);
    let sail_state = run_sail(&bytes, packet);

    assert_eq!(
        rust_state, sail_state,
        "Rust and Sail states differ!\nRust: {}\nSail: {}",
        serde_json::to_string_pretty(&rust_state).unwrap(),
        serde_json::to_string_pretty(&sail_state).unwrap(),
    );
}

// ---------------------------------------------------------------------------
// Deterministic tests (no packet data)
// ---------------------------------------------------------------------------

#[test]
fn diff_simple_halt() {
    diff_test("HALT", &[0u8; 256]);
}

#[test]
fn diff_movi_halt() {
    diff_test("MOVI PR0, 42, 8\nHALT", &[0u8; 256]);
}

#[test]
fn diff_add_program() {
    diff_test(
        "MOVI PR0, 10, 8\nMOVI PR1, 20, 8\nADD PR2, PR0, PR1\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_branch_taken() {
    diff_test(
        "MOVI PR0, 5, 8\nMOVI PR1, 5, 8\nCMP PR0, PR1\nBR.EQ 6\nMOVI PR2, 255, 8\nHALT\nMOVI PR2, 170, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_branch_not_taken() {
    diff_test(
        "MOVI PR0, 3, 8\nMOVI PR1, 5, 8\nCMP PR0, PR1\nBR.EQ 6\nMOVI PR2, 187, 8\nHALT\nMOVI PR2, 204, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_counting_loop() {
    diff_test(
        "MOVI PR0, 3, 8\nSUBI PR0, PR0, 1\nCMP PR0, PR1\nBR.NEQ 1\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_haltdrop() {
    diff_test("MOVI PR0, 1, 8\nHALTDROP", &[0u8; 256]);
}

// ---------------------------------------------------------------------------
// Packet-dependent tests (fixed packet)
// ---------------------------------------------------------------------------

#[test]
fn diff_ext_fixed_packet() {
    let mut packet = [0u8; 256];
    packet[0] = 0x45;
    packet[1] = 0x00;
    packet[2] = 0x00;
    packet[3] = 0x3C;
    diff_test("EXT PR0, 0, 4\nHALT", &packet);
}

// ---------------------------------------------------------------------------
// Example program tests
// ---------------------------------------------------------------------------

#[test]
fn diff_example_simple_branch() {
    let source = include_str!("../examples/simple-branch.xisa");
    diff_test(source, &[0u8; 256]);
}

#[test]
fn diff_example_extract_ipv4() {
    let source = include_str!("../examples/extract-ipv4.xisa");
    let mut packet = [0u8; 256];
    packet[0] = 0x45; // version=4, IHL=5
    packet[1] = 0x00;
    packet[2] = 0x00;
    packet[3] = 0x3C; // total length = 60
    packet[9] = 0x06; // protocol = TCP
    packet[12] = 192; // src IP
    packet[13] = 168;
    packet[14] = 1;
    packet[15] = 1;
    packet[16] = 10; // dst IP
    packet[17] = 0;
    packet[18] = 0;
    packet[19] = 1;
    diff_test(source, &packet);
}

// ---------------------------------------------------------------------------
// Binary-level diff test helper (for instructions the assembler doesn't support)
// ---------------------------------------------------------------------------

/// Encode a list of instructions, run on both simulators, compare.
fn diff_test_instrs(instrs: &[Instruction], packet: &[u8]) {
    if !harness_available() {
        eprintln!("Skipping diff test: sail-c-emu-harness not found at {}", HARNESS_PATH);
        return;
    }

    let mut bytes = Vec::new();
    for inst in instrs {
        bytes.extend_from_slice(&encode(inst).to_be_bytes());
    }

    let rust_state = run_rust(&bytes, packet);
    let sail_state = run_sail(&bytes, packet);

    assert_eq!(
        rust_state, sail_state,
        "Rust and Sail states differ!\nRust: {}\nSail: {}",
        serde_json::to_string_pretty(&rust_state).unwrap(),
        serde_json::to_string_pretty(&sail_state).unwrap(),
    );
}

// ---------------------------------------------------------------------------
// Data movement tests
// ---------------------------------------------------------------------------

#[test]
fn diff_mov_register_copy() {
    diff_test(
        "MOVI PR0, 0xABCD, 16\nMOV PR1, PR0\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_movi_nonzero_offset() {
    // MOVI with byte offset 2 → bit offset 16
    diff_test(
        "MOVI PR0.2, 0xFF, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_movi_clear_dest() {
    // Set PR0, then overwrite with .CD
    diff_test(
        "MOVI PR0, 0xFFFF, 16\nMOVI.CD PR0, 42, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_ext_clear_dest() {
    let mut packet = [0u8; 256];
    packet[0] = 0xAB;
    diff_test(
        "MOVI PR0, 0xFFFF, 16\nEXT.CD PR0, 0, 8\nHALT",
        &packet,
    );
}

#[test]
fn diff_ext_with_nonzero_cursor() {
    let mut packet = [0u8; 256];
    packet[10] = 0xDE;
    packet[11] = 0xAD;
    diff_test(
        "STCI 10\nEXT PR0, 0, 16\nHALT",
        &packet,
    );
}

// ---------------------------------------------------------------------------
// Arithmetic tests
// ---------------------------------------------------------------------------

#[test]
fn diff_addi() {
    diff_test(
        "MOVI PR0, 100, 8\nADDI PR1, PR0, 55\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_addi_overflow() {
    // 200 + 200 = 400, but in 8-bit → 144 (wraps), should set neither Z nor N
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 200, size: 8, cd: false },
        Instruction::AddI { rd: Reg::PR1, rs: Reg::PR0, imm: 200, size: 8, cd: false },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_subi_to_zero() {
    diff_test(
        "MOVI PR0, 42, 8\nSUBI PR1, PR0, 42\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_subi_negative() {
    diff_test(
        "MOVI PR0, 5, 8\nSUBI PR1, PR0, 10\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_sub_registers() {
    diff_test(
        "MOVI PR0, 100, 8\nMOVI PR1, 30, 8\nSUB PR2, PR0, PR1\nHALT",
        &[0u8; 256],
    );
}

// ---------------------------------------------------------------------------
// Logic tests
// ---------------------------------------------------------------------------

#[test]
fn diff_and() {
    diff_test(
        "MOVI PR0, 0xFF, 8\nMOVI PR1, 0x0F, 8\nAND PR2, PR0, PR1\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_and_zero_flag() {
    diff_test(
        "MOVI PR0, 0xF0, 8\nMOVI PR1, 0x0F, 8\nAND PR2, PR0, PR1\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_or() {
    diff_test(
        "MOVI PR0, 0xA0, 8\nMOVI PR1, 0x05, 8\nOR PR2, PR0, PR1\nHALT",
        &[0u8; 256],
    );
}

// ---------------------------------------------------------------------------
// Branch tests
// ---------------------------------------------------------------------------

#[test]
fn diff_brbtst_set() {
    // Set bit 0 of PR0 (value 1), then branch if bit 0 is set
    diff_test(
        "MOVI PR0, 1, 8\nBRBTST SET, PR0.0, 3\nHALT\nMOVI PR1, 99, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_brbtst_clear() {
    // PR0 = 0, branch if bit 0 is clear
    diff_test(
        "BRBTST CLR, PR0.0, 2\nHALT\nMOVI PR1, 77, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_branch_lt() {
    diff_test(
        "MOVI PR0, 3, 8\nMOVI PR1, 5, 8\nCMP PR0, PR1\nBR.LT 6\nMOVI PR2, 0, 8\nHALT\nMOVI PR2, 1, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_branch_gt() {
    diff_test(
        "MOVI PR0, 10, 8\nMOVI PR1, 3, 8\nCMP PR0, PR1\nBR.GT 6\nMOVI PR2, 0, 8\nHALT\nMOVI PR2, 1, 8\nHALT",
        &[0u8; 256],
    );
}

// ---------------------------------------------------------------------------
// Header / cursor tests
// ---------------------------------------------------------------------------

#[test]
fn diff_sth() {
    diff_test(
        "STCI 20\nSTH 5, 5\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_sth_different_pid_oid() {
    diff_test(
        "STCI 14\nSTH 3, 7\nHALT",
        &[0u8; 256],
    );
}

#[test]
fn diff_stch() {
    // STCH: cursor += incr, then set header at new cursor position
    diff_test_instrs(&[
        Instruction::Stch { incr: 20, pid: 2, oid: 2, halt: false },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_sthc() {
    // STHC: set header at current cursor, then cursor += incr
    diff_test_instrs(&[
        Instruction::Stci { incr: 10 },
        Instruction::Sthc { incr: 5, pid: 1, oid: 1 },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_sth_with_halt() {
    diff_test_instrs(&[
        Instruction::Stci { incr: 14 },
        Instruction::Sth { pid: 0, oid: 0, halt: true },
    ], &[0u8; 256]);
}

#[test]
fn diff_stc() {
    // STC: cursor += (reg_slice + incr) << shift
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 5, size: 8, cd: false },
        Instruction::Stc { rs: Reg::PR0, soff: 0, ssz: 8, shift: 1, incr: 2 },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

// ---------------------------------------------------------------------------
// Store to struct-0 tests
// ---------------------------------------------------------------------------

#[test]
fn diff_st() {
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 0xBEEF, size: 16, cd: false },
        Instruction::St { rs: Reg::PR0, soff: 0, doff: 0, size: 16, halt: false },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_st_with_offset() {
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 0xFF, size: 8, cd: false },
        Instruction::St { rs: Reg::PR0, soff: 0, doff: 16, size: 8, halt: false },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_st_with_halt() {
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 42, size: 8, cd: false },
        Instruction::St { rs: Reg::PR0, soff: 0, doff: 0, size: 8, halt: true },
    ], &[0u8; 256]);
}

#[test]
fn diff_sti() {
    diff_test_instrs(&[
        Instruction::StI { imm: 0xCAFE, doff: 0, size: 16 },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_sti_with_offset() {
    diff_test_instrs(&[
        Instruction::StI { imm: 0xAB, doff: 32, size: 8 },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

// ---------------------------------------------------------------------------
// Compare instruction variants
// ---------------------------------------------------------------------------

#[test]
fn diff_cmpiby() {
    // CmpIBy: byte-offset compare
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 42, size: 8, cd: false },
        Instruction::CmpIBy { rs: Reg::PR0, soff: 0, imm: 42, size: 8 },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_cmpibi() {
    // CmpIBi: bit-offset compare
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 100, size: 8, cd: false },
        Instruction::CmpIBi { rs: Reg::PR0, soff: 0, imm: 50, size: 8 },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

// ---------------------------------------------------------------------------
// Concatenation tests
// ---------------------------------------------------------------------------

#[test]
fn diff_cnct_by() {
    // CnctBy: concatenate two byte-aligned register slices
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 0xAB, size: 8, cd: false },
        Instruction::Movi { rd: Reg::PR1, doff: 0, imm: 0xCD, size: 8, cd: false },
        Instruction::CnctBy {
            rd: Reg::PR2, doff: 0,
            rs1: Reg::PR0, s1off: 0, s1sz: 1,  // 1 byte
            rs2: Reg::PR1, s2off: 0, s2sz: 1,  // 1 byte
            cd: true,
        },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_cnct_bi() {
    // CnctBi: concatenate two bit-level register slices
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 0x0F, size: 8, cd: false },
        Instruction::Movi { rd: Reg::PR1, doff: 0, imm: 0x03, size: 8, cd: false },
        Instruction::CnctBi {
            rd: Reg::PR2, doff: 0,
            rs1: Reg::PR0, s1off: 0, s1sz: 4,  // 4 bits
            rs2: Reg::PR1, s2off: 0, s2sz: 2,  // 2 bits
            cd: true,
        },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

// ---------------------------------------------------------------------------
// SubII test (imm - reg)
// ---------------------------------------------------------------------------

#[test]
fn diff_subii() {
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 30, size: 8, cd: false },
        Instruction::SubII { rd: Reg::PR1, imm: 100, rs: Reg::PR0, size: 8, cd: true },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

// ---------------------------------------------------------------------------
// AndI / OrI tests
// ---------------------------------------------------------------------------

#[test]
fn diff_andi() {
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 0xFF, size: 8, cd: false },
        Instruction::AndI { rd: Reg::PR1, rs: Reg::PR0, imm: 0x0F, size: 8, cd: true },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_ori() {
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 0xA0, size: 8, cd: false },
        Instruction::OrI { rd: Reg::PR1, rs: Reg::PR0, imm: 0x05, size: 8, cd: true },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

// ---------------------------------------------------------------------------
// Multi-instruction integration tests
// ---------------------------------------------------------------------------

#[test]
fn diff_extract_and_store() {
    // Extract from packet, store to struct0
    let mut packet = [0u8; 256];
    packet[0] = 0x45;
    packet[1] = 0x00;
    packet[9] = 0x06;
    diff_test_instrs(&[
        Instruction::Ext { rd: Reg::PR0, doff: 0, soff: 0, size: 8, cd: true },
        Instruction::St { rs: Reg::PR0, soff: 0, doff: 0, size: 8, halt: false },
        Instruction::Ext { rd: Reg::PR1, doff: 0, soff: 72, size: 8, cd: true },
        Instruction::St { rs: Reg::PR1, soff: 0, doff: 8, size: 8, halt: false },
        Instruction::Stci { incr: 20 },
        Instruction::Sth { pid: 0, oid: 0, halt: true },
    ], &packet);
}

#[test]
fn diff_multi_header_layers() {
    // Simulate two protocol headers: set header, advance cursor, set header again
    diff_test_instrs(&[
        Instruction::Sth { pid: 0, oid: 0, halt: false },
        Instruction::Stci { incr: 14 },
        Instruction::Sth { pid: 1, oid: 1, halt: false },
        Instruction::Stci { incr: 20 },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

// ---------------------------------------------------------------------------
// MOV variant tests
// ---------------------------------------------------------------------------

#[test]
fn diff_movl() {
    // MOVL: dest_off = extract_bits(rs2, o2, sz2) + o1
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 0xAB, size: 8, cd: true },
        Instruction::Movi { rd: Reg::PR1, doff: 0, imm: 4, size: 8, cd: true },  // dynamic offset = 4
        Instruction::MovL {
            rd: Reg::PR2, rs1: Reg::PR0, o1: 0, sz1: 8,
            rs2: Reg::PR1, o2: 0, sz2: 8, cd: true,
        },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_movli() {
    // MOVLI: dest_off = imm + off
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 0xFF, size: 8, cd: true },
        Instruction::MovLI {
            rd: Reg::PR1, rs: Reg::PR0, off: 0, size: 8, imm: 8, cd: true,
        },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_movlii() {
    // MOVLII: dest_off = extract_bits(rs, off, size), insert imm at that offset
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 16, size: 8, cd: true },  // offset value = 16
        Instruction::MovLII {
            rd: Reg::PR1, rs: Reg::PR0, off: 0, size: 8, imm: 0xCD, isz: 8, cd: true,
        },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_movr() {
    // MOVR: dest_off = o1 - extract_bits(rs2, o2, sz2)
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 0xAB, size: 8, cd: true },
        Instruction::Movi { rd: Reg::PR1, doff: 0, imm: 4, size: 8, cd: true },
        Instruction::MovR {
            rd: Reg::PR2, rs1: Reg::PR0, o1: 16, sz1: 8,
            rs2: Reg::PR1, o2: 0, sz2: 8, cd: true,
        },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_movri() {
    // MOVRI: dest_off = off - imm
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 0xFF, size: 8, cd: true },
        Instruction::MovRI {
            rd: Reg::PR1, rs: Reg::PR0, off: 24, size: 8, imm: 8, cd: true,
        },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

#[test]
fn diff_movrii() {
    // MOVRII: extract offset from register, index into imm, insert at offset 0
    diff_test_instrs(&[
        Instruction::Movi { rd: Reg::PR0, doff: 0, imm: 2, size: 8, cd: true },  // reg_offset = 2
        Instruction::MovRII {
            rd: Reg::PR1, rs: Reg::PR0, off: 0, size: 8, imm: 0xFF, isz: 8, cd: true,
        },
        Instruction::Halt { drop: false },
    ], &[0u8; 256]);
}

// ---------------------------------------------------------------------------
// Proptest packet fuzzing
// ---------------------------------------------------------------------------

fn arb_packet() -> impl Strategy<Value = Vec<u8>> {
    proptest::collection::vec(any::<u8>(), 256)
}

proptest! {
    #[test]
    fn diff_ext_fuzz_packet(packet in arb_packet()) {
        if !harness_available() {
            return Ok(());
        }
        diff_test("EXT PR0, 0, 4\nHALT", &packet);
    }

    #[test]
    fn diff_ext_with_cursor_fuzz(packet in arb_packet()) {
        if !harness_available() {
            return Ok(());
        }
        diff_test("STCI 14\nEXT PR0, 0, 2\nHALT", &packet);
    }
}
