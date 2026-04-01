# CI & Formatter Design Spec

## Overview

Add GitHub Actions CI and a Sail code formatter to the project. Two workflows: one to build and cache the dev container image, one to run format checks, type-checking, and tests.

## Workflow 1: Build Dev Container

**File:** `.github/workflows/build-devcontainer.yml`

- **Triggers:** push to `main` that changes `.devcontainer/**`
- **What it does:** Builds the dev container image and pushes it to `ghcr.io/qobilidop/sail-xisa/dev`
- **Uses:** `devcontainers/ci@v0.3` with `push: always`
- **Auth:** `docker/login-action` with GHCR + `GITHUB_TOKEN`

## Workflow 2: CI

**File:** `.github/workflows/ci.yml`

- **Triggers:** all pushes and pull requests
- **What it does:** Pulls the pre-built dev container (or rebuilds from cache if stale), then runs:
  1. **Format check** — `tools/format.sh --check` (fails if Sail files aren't formatted)
  2. **Type-check** — `cmake -B build && cmake --build build --target check`
  3. **Tests** — `cmake --build build && ctest --test-dir build --verbose`
- **Uses:** `devcontainers/ci@v0.3` with `cacheFrom` pointing to the pre-built image, `push: never`
- **Auth:** `docker/login-action` with GHCR + `GITHUB_TOKEN` (needed to pull cached image)

## Format Script

**File:** `tools/format.sh`

- **Without args:** Formats all `.sail` files under `model/` and `test/` in place using `sail --fmt`
- **With `--check`:** Formats in place, then uses `git diff --exit-code` to fail if anything changed. Restores original files on failure so the working tree is not modified.
- Sail's `--fmt` flag does not have a built-in check mode, so the check approach is: format, diff, restore if needed.

## File Map

| File | Purpose |
|------|---------|
| `.github/workflows/build-devcontainer.yml` | Build and push dev container image to GHCR |
| `.github/workflows/ci.yml` | Run format check, type-check, and tests |
| `tools/format.sh` | Format Sail code (or check formatting) |
