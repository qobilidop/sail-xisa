# CI & Formatter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub Actions CI (format check, type-check, tests) and a Sail code formatter script, with a separate workflow to build and cache the dev container image.

**Architecture:** Two GitHub Actions workflows — one builds/pushes the dev container image to GHCR on `.devcontainer/` changes, one runs CI checks using the cached image. A `tools/format.sh` script wraps `sail --fmt` with a `--check` mode for CI.

**Tech Stack:** GitHub Actions, `devcontainers/ci@v0.3`, Docker/GHCR, Sail formatter

---

## File Map

| File | Responsibility |
|------|---------------|
| `tools/format.sh` | Format Sail files or check formatting |
| `.github/workflows/build-devcontainer.yml` | Build and push dev container image to GHCR |
| `.github/workflows/ci.yml` | Run format check, type-check, and tests |

---

### Task 1: Format Script

**Files:**
- Create: `tools/format.sh`

- [ ] **Step 1: Create tools/format.sh**

```bash
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x tools/format.sh`

- [ ] **Step 3: Test the format script locally**

Run inside the dev container:
```bash
devcontainer exec --workspace-folder /Users/qobilidop/i/sail-xisa tools/format.sh
```
Expected: Formats files, prints "Done."

Then check if any files changed:
```bash
git diff --stat
```

If files changed, the formatter found style issues in our existing code. That's expected — commit the formatting fixes separately.

- [ ] **Step 4: Commit the format script (and any formatting fixes)**

```bash
git add tools/format.sh
git commit -m "Add Sail format script (tools/format.sh)"
```

If the formatter changed existing Sail files:
```bash
git add model/ test/
git commit -m "Apply Sail formatter to existing code"
```

---

### Task 2: Build Dev Container Workflow

**Files:**
- Create: `.github/workflows/build-devcontainer.yml`

- [ ] **Step 1: Create the workflow file**

```yaml
name: Build Dev Container

on:
  push:
    branches: [main]
    paths:
      - '.devcontainer/**'

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push dev container
        uses: devcontainers/ci@v0.3
        with:
          imageName: ghcr.io/${{ github.repository }}/dev
          push: always
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/build-devcontainer.yml
git commit -m "Add GitHub Actions workflow to build and publish dev container"
```

---

### Task 3: CI Workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the workflow file**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: read

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Run CI checks
        uses: devcontainers/ci@v0.3
        with:
          cacheFrom: ghcr.io/${{ github.repository }}/dev
          push: never
          runCmd: |
            tools/format.sh --check
            cmake -B build
            cmake --build build --target check
            cmake --build build
            ctest --test-dir build --verbose
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "Add CI workflow with format check, type-check, and tests"
```

---

### Task 4: Verify and Update Docs

**Files:**
- Modify: `docs/dev-commands.md`

- [ ] **Step 1: Add format commands to dev-commands.md**

Add a "Formatting" section after the "Testing" section:

```markdown
## Formatting

```bash
# Format all Sail files
./dev.sh tools/format.sh

# Check formatting (CI mode — fails if files aren't formatted)
./dev.sh tools/format.sh --check
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/dev-commands.md
git commit -m "Add format commands to dev-commands reference"
```
