# Sail XISA

A formal specification of [XISA](https://xsightlabs.com/switches/xisa) (Xsight Labs' X-Switch Instruction Set Architecture) written in [Sail](https://github.com/rems-project/sail). See the public [white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf) for the XISA reference.

XISA defines packet processing for the X-Switch family of programmable network switches. This project provides a machine-readable, executable formal model of the ISA, inspired by the [Sail RISC-V model](https://github.com/riscv/sail-riscv).

## Quick Start

Requires the [devcontainer CLI](https://github.com/devcontainers/cli).

```bash
# Build the dev container
devcontainer build --workspace-folder .

# Configure and build
./dev.sh cmake -B build
./dev.sh cmake --build build

# Run tests
./dev.sh ctest --test-dir build --verbose
```

See [docs/dev-commands.md](docs/dev-commands.md) for the full commands reference.

## Status

See [docs/coverage.md](docs/coverage.md) for spec coverage and [docs/todo.md](docs/todo.md) for known issues.

## License

[Apache License 2.0](LICENSE)
