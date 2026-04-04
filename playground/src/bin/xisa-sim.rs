use std::env;
use std::fs;
use std::process;

use xisa::execute;
use xisa::state::SimState;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: xisa-sim <input.bin>");
        process::exit(1);
    }

    let input_path = &args[1];
    let bytes = match fs::read(input_path) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("Error reading {}: {}", input_path, e);
            process::exit(1);
        }
    };

    let mut state = SimState::new();

    // Load 64-bit big-endian words into instruction memory.
    for chunk in bytes.chunks_exact(8) {
        let word = u64::from_be_bytes([
            chunk[0], chunk[1], chunk[2], chunk[3],
            chunk[4], chunk[5], chunk[6], chunk[7],
        ]);
        state.instruction_mem.push(word);
    }

    // Run until halt or drop.
    loop {
        match execute::step(&mut state) {
            Ok(result) => {
                if result.halted || result.dropped {
                    break;
                }
            }
            Err(e) => {
                eprintln!("Execution error: {}", e);
                process::exit(1);
            }
        }
    }

    // Dump final state as JSON.
    println!("{}", serde_json::to_string_pretty(&state).unwrap());
}
