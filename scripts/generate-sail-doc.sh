#!/usr/bin/env bash
set -euo pipefail

# Generate Sail JSON documentation bundle from the model.
# Must be run inside the dev container (via ./dev.sh).
# Output: web/src/data/doc.json

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$PROJECT_DIR/web/src/data/doc.json"

mkdir -p "$(dirname "$OUT")"

cd "$PROJECT_DIR"
sail --doc --doc-format identity --doc-embed plain --doc-compact --doc-bundle doc.json model/main.sail

mv sail_doc/doc.json "$OUT"
rm -rf sail_doc

echo "Generated $OUT"
