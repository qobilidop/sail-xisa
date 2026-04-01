# Development Commands Reference

All commands are run through `dev.sh`, which executes them inside the dev container.

## First-Time Setup

```bash
# Build the dev container (one-time, or after Dockerfile changes)
devcontainer build --workspace-folder .

# Verify Sail is installed
./dev.sh sail --version
```

## Building

```bash
# Configure the build (one-time, or after CMakeLists.txt changes)
./dev.sh cmake -B build

# Type-check the Sail model (fast, no C compilation)
./dev.sh cmake --build build --target check

# Full build (type-check + compile tests)
./dev.sh cmake --build build
```

## Testing

```bash
# Run all tests
./dev.sh ctest --test-dir build

# Run all tests with verbose output (shows pass/fail per test)
./dev.sh ctest --test-dir build --verbose

# Run a specific test by name
./dev.sh ctest --test-dir build -R test_nop --verbose
```

## Formatting

```bash
# Format all Sail files
./dev.sh tools/format.sh

# Check formatting (CI mode — fails if files aren't formatted)
./dev.sh tools/format.sh --check
```

## Interactive

```bash
# Open a shell inside the dev container
./dev.sh bash

# Run the Sail interactive interpreter on the model
./dev.sh sail -i model/main.sail
```

## Common Workflows

### Adding a new instruction

1. Add the union clause to `model/parser/types.sail`
2. Add the execute clause to `model/parser/insts.sail`
3. Create a test file in `test/parser/test_<name>.sail`
4. Register the test in `test/CMakeLists.txt`
5. Build and test: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --verbose`

### Debugging a test failure

```bash
# Run just the failing test with verbose output
./dev.sh ctest --test-dir build -R test_name --verbose

# Or run the test executable directly for more detail
./dev.sh ./build/test/test_name
```
