# Spec Page Design

## Overview

Add a `/sail-xisa/spec` page to the website that serves as the project's ISA reference and spec coverage tracker. It replaces `docs/spec-coverage.md` with a richer, publicly accessible page that includes Sail formal semantics for implemented instructions.

## Page Structure

### Header

- MPLv2 notice: "ISA specification content derived from the [Xsight Labs XISA specification](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf), licensed under [MPLv2](https://www.mozilla.org/en-US/MPL/2.0/)."
- Link to the official white paper PDF

### Body

Two major sections matching the official spec:

1. **Parser ISA (Section 3)** — section numbers and titles from the XISA white paper
2. **MAP ISA (Section 4)** — same structure

Each section contains:

- **Coverage table**: spec section number, instruction name(s), status (Done / Not started), notes on limitations. Content migrated from `docs/spec-coverage.md`.
- **Sail semantics**: for each implemented instruction, render the `execute` clause from the Sail JSON doc bundle as a code block. Function names are manually mapped in the page template.

## Build Pipeline

1. CI generates `doc.json` from the Sail model: `sail --doc --doc-format identity --doc-embed plain --doc-compact --doc-bundle doc.json model/main.sail`
2. The JSON file is placed at `web/src/data/doc.json` so Astro can import it at build time
3. The Astro page reads the JSON and renders selected function entries as code blocks
4. The web workflow (`web.yml`) adds the Sail doc generation step before the Astro build

## Implementation Details

- **Page file**: `web/src/pages/spec.astro`
- **Layout**: reuses `Base.astro` layout and `global.css`
- **Additional CSS**: table styles and code block styles, added to `public/styles/spec.css`
- **No Svelte components**: pure static Astro/HTML, no client-side JS needed
- **Navigation**: add "Spec" link to `Base.astro` nav bar

## Data Flow

```
model/*.sail
    │
    ▼  sail --doc
doc.json (in CI / local build)
    │
    ▼  copied to web/src/data/
spec.astro reads JSON at build time
    │
    ▼  Astro SSG
/sail-xisa/spec/index.html
```

## Function Mapping

The page template maintains a manual list mapping spec sections to JSON doc entries. For example:

- Section 3.12.13 ADD, ADDI → JSON functions key containing the `pexecute` clause for PADD
- Section 4.13.1 ADD, ADDI → JSON functions key containing the `mexecute` clause for MADD

This mapping needs updating when new instructions are implemented, which is the same cadence as the current spec-coverage updates.

## Cleanup

- Delete `docs/spec-coverage.md` after the page is live

## Dev Container

- The web workflow already has Sail available in the dev container
- Local development: run `sail --doc ...` via `./dev.sh` to generate the JSON, then copy to `web/src/data/`
