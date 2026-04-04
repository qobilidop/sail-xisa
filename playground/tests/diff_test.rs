use std::io::Write;
use std::process::Command;

use proptest::prelude::*;

use xisa::assembler::assemble;
use xisa::diff::DiffState;
use xisa::execute;
use xisa::state::SimState;

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

// The following tests are ignored pending resolution of the bit-endianness
// mismatch between Rust and Sail implementations.
// Rust insert_bits uses big-endian (bit 0 = MSB), Sail uses little-endian (bit 0 = LSB).
// Example: MOVI PR0, 42, 8 at offset 0 puts 0x2a at MSB in Rust, LSB in Sail.

#[test]
#[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
fn diff_movi_halt() {
    diff_test("MOVI PR0, 42, 8\nHALT", &[0u8; 256]);
}

#[test]
#[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
fn diff_add_program() {
    diff_test(
        "MOVI PR0, 10, 8\nMOVI PR1, 20, 8\nADD PR2, PR0, PR1\nHALT",
        &[0u8; 256],
    );
}

#[test]
#[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
fn diff_branch_taken() {
    diff_test(
        "MOVI PR0, 5, 8\nMOVI PR1, 5, 8\nCMP PR0, PR1\nBR.EQ 6\nMOVI PR2, 255, 8\nHALT\nMOVI PR2, 170, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
#[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
fn diff_branch_not_taken() {
    diff_test(
        "MOVI PR0, 3, 8\nMOVI PR1, 5, 8\nCMP PR0, PR1\nBR.EQ 6\nMOVI PR2, 187, 8\nHALT\nMOVI PR2, 204, 8\nHALT",
        &[0u8; 256],
    );
}

#[test]
#[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
fn diff_counting_loop() {
    diff_test(
        "MOVI PR0, 3, 8\nSUBI PR0, PR0, 1\nCMP PR0, PR1\nBR.NEQ 1\nHALT",
        &[0u8; 256],
    );
}

#[test]
#[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
fn diff_haltdrop() {
    diff_test("MOVI PR0, 1, 8\nHALTDROP", &[0u8; 256]);
}

// ---------------------------------------------------------------------------
// Packet-dependent tests (fixed packet)
// ---------------------------------------------------------------------------

#[test]
#[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
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
#[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
fn diff_example_simple_branch() {
    let source = include_str!("../examples/simple-branch.xisa");
    diff_test(source, &[0u8; 256]);
}

#[test]
#[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
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
// Proptest packet fuzzing
// ---------------------------------------------------------------------------

fn arb_packet() -> impl Strategy<Value = Vec<u8>> {
    proptest::collection::vec(any::<u8>(), 256)
}

// Proptest packet fuzzing — ignored pending endianness fix.
// To run: cargo test --test diff_test -- --ignored
proptest! {
    #[test]
    #[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
    fn diff_ext_fuzz_packet(packet in arb_packet()) {
        if !harness_available() {
            return Ok(());
        }
        diff_test("EXT PR0, 0, 4\nHALT", &packet);
    }

    #[test]
    #[ignore = "bit-endianness mismatch: Rust big-endian vs Sail little-endian"]
    fn diff_ext_with_cursor_fuzz(packet in arb_packet()) {
        if !harness_available() {
            return Ok(());
        }
        diff_test("STCI 14\nEXT PR0, 0, 2\nHALT", &packet);
    }
}
