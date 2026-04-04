use std::env;
use std::fs;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: xisa-asm <input.xisa> [output.bin]");
        process::exit(1);
    }

    let input_path = &args[1];
    let source = match fs::read_to_string(input_path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Error reading {}: {}", input_path, e);
            process::exit(1);
        }
    };

    match xisa::assembler::assemble(&source) {
        Ok(result) => {
            let output_path = if args.len() >= 3 {
                args[2].clone()
            } else {
                input_path.replace(".xisa", ".bin")
            };

            let mut bytes = Vec::new();
            for word in &result.words {
                bytes.extend_from_slice(&word.to_be_bytes());
            }

            match fs::write(&output_path, &bytes) {
                Ok(()) => println!("Assembled {} instructions to {}", result.words.len(), output_path),
                Err(e) => {
                    eprintln!("Error writing {}: {}", output_path, e);
                    process::exit(1);
                }
            }
        }
        Err(errors) => {
            for e in &errors {
                eprintln!("{}:{}: {}", input_path, e.line, e.message);
            }
            process::exit(1);
        }
    }
}
