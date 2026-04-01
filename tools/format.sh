#!/usr/bin/env bash
set -euo pipefail

# Format all Sail source files, or check that they are formatted.
#
# Usage:
#   tools/format.sh          # format in place
#   tools/format.sh --check  # check formatting (exit 1 if unformatted)

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
    # Check mode: format in place, then check for diffs
    echo "Checking Sail formatting..."
    for f in $SAIL_FILES; do
        sail --fmt "$f"
    done
    if git diff --quiet -- '*.sail'; then
        echo "All Sail files are formatted."
        exit 0
    else
        echo ""
        echo "ERROR: The following Sail files are not formatted:"
        git diff --name-only -- '*.sail'
        echo ""
        echo "Run 'tools/format.sh' to fix."
        # Restore original files so working tree is not modified
        git checkout -- '*.sail'
        exit 1
    fi
else
    echo "Usage: tools/format.sh [--check]"
    exit 1
fi
