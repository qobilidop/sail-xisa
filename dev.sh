#!/usr/bin/env bash
set -euo pipefail

# Run a command inside the sail-xisa dev container.
#
# Usage:
#   ./dev.sh <command> [args...]
#
# Examples:
#   ./dev.sh sail --version
#   ./dev.sh cmake -B build
#   ./dev.sh cmake --build build
#   ./dev.sh ctest --test-dir build
#   ./dev.sh bash              # interactive shell

devcontainer exec --workspace-folder . "$@"
