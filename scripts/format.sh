#!/usr/bin/env bash
set -euo pipefail

# Format all Sail source files, or check that they are formatted.
#
# Usage:
#   scripts/format.sh          # format in place
#   scripts/format.sh --check  # check formatting (exit 1 if unformatted)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Collect all .sail files under model/ and test/
SAIL_FILES=$(find "$REPO_ROOT/model" "$REPO_ROOT/test" -name '*.sail' | sort)

if [ $# -eq 0 ]; then
    # Format mode: format files in place
    echo "Formatting Sail files..."
    for f in $SAIL_FILES; do
        sail --fmt "$f"
    done
    echo "Done."
elif [ "$1" = "--check" ]; then
    # Check mode: save copies, format, compare, restore if needed.
    # Uses temp files instead of git so it works inside containers.
    echo "Checking Sail formatting..."
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
    UNFORMATTED=()

    for f in $SAIL_FILES; do
        cp "$f" "$TMPDIR/$(basename "$f").bak"
        sail --fmt "$f"
        if ! diff -q "$f" "$TMPDIR/$(basename "$f").bak" > /dev/null 2>&1; then
            UNFORMATTED+=("$f")
            # Restore original
            cp "$TMPDIR/$(basename "$f").bak" "$f"
        fi
    done

    if [ ${#UNFORMATTED[@]} -eq 0 ]; then
        echo "All Sail files are formatted."
        exit 0
    else
        echo ""
        echo "ERROR: The following Sail files are not formatted:"
        for f in "${UNFORMATTED[@]}"; do
            echo "  $f"
        done
        echo ""
        echo "Run 'scripts/format.sh' to fix."
        exit 1
    fi
else
    echo "Usage: scripts/format.sh [--check]"
    exit 1
fi
