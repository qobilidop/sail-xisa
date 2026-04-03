# Spec Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/sail-xisa/spec` page showing ISA spec coverage with Sail formal semantics for implemented instructions.

**Architecture:** Static Astro page reads a pre-generated Sail JSON doc bundle at build time. CI generates the JSON from the Sail model in the dev container, copies it to the web source tree, then builds the Astro site. The page maps spec sections to execute clause pattern IDs in the JSON.

**Tech Stack:** Astro SSG, Sail `--doc` JSON backend, GitHub Actions with dev container

---

### Task 1: Generate Sail doc JSON and make it available to Astro

**Files:**
- Create: `web/src/data/.gitkeep` (placeholder so the data dir exists)
- Create: `scripts/generate-sail-doc.sh`

- [ ] **Step 1: Create the doc generation script**

Create `scripts/generate-sail-doc.sh`:

```bash
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
```

- [ ] **Step 2: Create data directory with .gitkeep**

```bash
mkdir -p web/src/data
touch web/src/data/.gitkeep
```

Add `web/src/data/doc.json` to `web/.gitignore` (it's generated, not checked in).

- [ ] **Step 3: Test locally**

Run: `./dev.sh bash scripts/generate-sail-doc.sh`

Expected: `web/src/data/doc.json` is created, ~318KB, contains `functions.execute` and `functions.mexecute` keys.

- [ ] **Step 4: Commit**

```bash
git add scripts/generate-sail-doc.sh web/src/data/.gitkeep web/.gitignore
git commit -m "Add Sail doc JSON generation script"
```

---

### Task 2: Create spec page with coverage tables

**Files:**
- Create: `web/src/pages/spec.astro`
- Create: `web/public/styles/spec.css`
- Modify: `web/src/layouts/Base.astro` (add nav link)

- [ ] **Step 1: Add spec.css**

Create `web/public/styles/spec.css`:

```css
.spec-page {
  max-width: 960px;
  margin: 0 auto;
  padding: 2rem 1.5rem;
}

.spec-notice {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 1rem 1.25rem;
  margin-bottom: 2rem;
  font-size: 0.9rem;
  color: var(--text-dim);
  line-height: 1.6;
}

.spec-notice a {
  color: var(--accent);
  text-decoration: none;
}

.spec-notice a:hover {
  text-decoration: underline;
}

.spec-page h2 {
  font-size: 1.5rem;
  margin-top: 2.5rem;
  margin-bottom: 1rem;
  color: var(--text);
}

.spec-page h3 {
  font-size: 1.1rem;
  margin-top: 1.5rem;
  margin-bottom: 0.5rem;
  color: var(--text);
}

.spec-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.85rem;
  margin-bottom: 1.5rem;
}

.spec-table th {
  text-align: left;
  padding: 0.5rem 0.75rem;
  background: var(--surface);
  border: 1px solid var(--border);
  color: var(--text-dim);
  font-weight: 600;
}

.spec-table td {
  padding: 0.5rem 0.75rem;
  border: 1px solid var(--border);
}

.spec-table .status-done {
  color: #4ade80;
}

.spec-table .status-not-started {
  color: var(--text-dim);
}

.sail-code {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 1rem;
  overflow-x: auto;
  font-family: var(--font-mono);
  font-size: 0.8rem;
  line-height: 1.5;
  color: var(--text);
  margin: 0.5rem 0 1.5rem 0;
  white-space: pre;
}
```

- [ ] **Step 2: Add "Spec" link to Base.astro nav**

In `web/src/layouts/Base.astro`, add the Spec link after Playground:

```html
<div class="nav-links">
  <a href={`${import.meta.env.BASE_URL}/`}>Home</a>
  <a href={`${import.meta.env.BASE_URL}/playground`}>Playground</a>
  <a href={`${import.meta.env.BASE_URL}/spec`}>Spec</a>
</div>
```

- [ ] **Step 3: Create spec.astro**

Create `web/src/pages/spec.astro`. This file reads the doc JSON and renders the coverage tables with Sail code blocks.

The frontmatter loads the JSON and defines a helper to find execute clauses by pattern ID:

```astro
---
import Base from '../layouts/Base.astro';

let doc: any = null;
try {
  const docModule = await import('../data/doc.json');
  doc = docModule.default;
} catch (e) {
  // doc.json may not exist in local dev without running generate script
}

function getExecuteClause(patternId: string): string | null {
  if (!doc) return null;
  const clauses = doc.functions?.execute?.function;
  if (!Array.isArray(clauses)) return null;
  const clause = clauses.find((c: any) => c.pattern?.id === patternId);
  return clause?.source ?? null;
}

function getMexecuteClause(patternId: string): string | null {
  if (!doc) return null;
  const clauses = doc.functions?.mexecute?.function;
  if (!Array.isArray(clauses)) return null;
  const clause = clauses.find((c: any) => c.pattern?.id === patternId);
  return clause?.source ?? null;
}
---
```

The body contains the MPLv2 notice, then parser and MAP sections with coverage tables and Sail code for implemented instructions. Full page content:

```astro
<Base title="Spec">
  <link slot="head" rel="stylesheet" href={`${import.meta.env.BASE_URL}/styles/spec.css`} />
  <div class="spec-page">
    <h1>XISA Spec Coverage</h1>

    <div class="spec-notice">
      ISA specification content on this page is derived from the
      <a href="https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf">
        Xsight Labs XISA specification
      </a>, licensed under the
      <a href="https://www.mozilla.org/en-US/MPL/2.0/">Mozilla Public License 2.0</a>.
      Section numbers refer to the official white paper.
    </div>

    <h2>Parser ISA (Section 3)</h2>

    <table class="spec-table">
      <thead>
        <tr><th>Section</th><th>Instruction(s)</th><th>Status</th><th>Notes</th></tr>
      </thead>
      <tbody>
        <tr><td>3.12.1</td><td>NXTP</td><td class="status-done">Done</td><td></td></tr>
        <tr><td>3.12.2</td><td>PSEEK, PSEEKNXTP</td><td class="status-done">Done</td><td>No PSEEK_ERROR/trap, no .CD. Fixed hdr length per entry</td></tr>
        <tr><td>3.12.3</td><td>EXT, EXTNXTP</td><td class="status-done">Done</td><td>.CD supported. No .PR, .SCSM, .ECSM yet</td></tr>
        <tr><td>3.12.4</td><td>EXTMAP</td><td class="status-done">Done</td><td>No .PR, .SCSM, .ECSM yet</td></tr>
        <tr><td>3.12.5</td><td>MOVMAP</td><td class="status-done">Done</td><td>No .HDR modifier yet</td></tr>
        <tr><td>3.12.6</td><td>CNCTBY, CNCTBI</td><td class="status-done">Done</td><td>.CD supported</td></tr>
        <tr><td>3.12.7</td><td>STH</td><td class="status-done">Done</td><td>.H supported. No JumpMode, .SCSM, .ECSM yet</td></tr>
        <tr><td>3.12.8</td><td>STC, STCI</td><td class="status-done">Done</td><td>No JumpMode, .SCSM, .ECSM yet</td></tr>
        <tr><td>3.12.9</td><td>STCH, STHC</td><td class="status-done">Done</td><td>.H supported (STCH). No JumpMode, .SCSM, .ECSM yet</td></tr>
        <tr><td>3.12.10</td><td>ST, STI</td><td class="status-done">Done</td><td>.H supported (ST). HW bits 6-31 restriction not enforced</td></tr>
        <tr><td>3.12.11</td><td>MOV, MOVI</td><td class="status-done">Done</td><td>.CD supported</td></tr>
        <tr><td>3.12.12</td><td>MOVL, MOVLI, MOVLII, MOVR, MOVRI, MOVRII</td><td class="status-done">Done</td><td>.CD supported</td></tr>
        <tr><td>3.12.13</td><td>ADD, ADDI</td><td class="status-done">Done</td><td>.CD supported</td></tr>
        <tr><td>3.12.14</td><td>SUB, SUBI, SUBII</td><td class="status-done">Done</td><td>.CD supported</td></tr>
        <tr><td>3.12.15</td><td>AND, ANDI</td><td class="status-done">Done</td><td>.CD supported</td></tr>
        <tr><td>3.12.16</td><td>OR, ORI</td><td class="status-done">Done</td><td>.CD supported</td></tr>
        <tr><td>3.12.17</td><td>CMP, CMPIBY, CMPIBI</td><td class="status-done">Done</td><td></td></tr>
        <tr><td>3.12.18</td><td>BR, BRBTST, BRNS, BRNXTP, BRBTSTNXTP, BRBTSTNS</td><td class="status-done">Done</td><td>JumpMode 100 (trap) deferred</td></tr>
        <tr><td>3.12.19</td><td>HALT, HALTDROP</td><td class="status-done">Done</td><td>No .RP or MAP-PC support yet</td></tr>
        <tr><td>3.12.20</td><td>NOP</td><td class="status-done">Done</td><td></td></tr>
      </tbody>
    </table>

    {/* Parser Sail semantics */}
    <h3>Parser Instruction Semantics</h3>

    {[
      ['PNOP'], ['PHALT'],
      ['PMOV', 'PMOVI'],
      ['PEXT', 'PEXTNXTP'],
      ['PEXTMAP'], ['PMOVMAP'],
      ['PCNCTBY', 'PCNCTBI'],
      ['PSTH'], ['PSTC', 'PSTCI'], ['PSTCH', 'PSTHC'], ['PST', 'PSTI'],
      ['PMOVL', 'PMOVLI', 'PMOVLII', 'PMOVR', 'PMOVRI', 'PMOVRII'],
      ['PADD', 'PADDI'], ['PSUB', 'PSUBI', 'PSUBII'],
      ['PAND', 'PANDI'], ['POR', 'PORI'],
      ['PCMP', 'PCMPIBY', 'PCMPIBI'],
      ['PBR', 'PBRBTST', 'PBRNS', 'PBRNXTP', 'PBRBTSTNXTP', 'PBRBTSTNS'],
      ['PNXTP'],
      ['PPSEEK', 'PPSEEKNXTP'],
    ].map((group) => (
      group.map((id) => {
        const src = getExecuteClause(id);
        return src ? <div class="sail-code" set:text={src} /> : null;
      })
    ))}

    <h2>MAP ISA (Section 4)</h2>

    <table class="spec-table">
      <thead>
        <tr><th>Section</th><th>Instruction(s)</th><th>Status</th><th>Notes</th></tr>
      </thead>
      <tbody>
        <tr><td>4.13.1</td><td>ADD, ADDI</td><td class="status-done">Done</td><td>.F, .SX, .SH supported</td></tr>
        <tr><td>4.13.2</td><td>SUB, SUBI</td><td class="status-done">Done</td><td>.F, .SX, .SH supported</td></tr>
        <tr><td>4.13.3</td><td>MOD, MODI</td><td class="status-not-started">Not started</td><td>Async, needs LFLAG</td></tr>
        <tr><td>4.13.4</td><td>CMP, CMPI</td><td class="status-done">Done</td><td>Always sets Z, C</td></tr>
        <tr><td>4.13.5</td><td>AND, ANDI</td><td class="status-done">Done</td><td>.F supported</td></tr>
        <tr><td>4.13.6</td><td>OR, ORI</td><td class="status-done">Done</td><td>.F supported</td></tr>
        <tr><td>4.13.7</td><td>XOR, XORI</td><td class="status-done">Done</td><td>.F supported</td></tr>
        <tr><td>4.13.8</td><td>NOT</td><td class="status-done">Done</td><td>.F supported</td></tr>
        <tr><td>4.13.9</td><td>SHL, SHLI, SHR, SHRI</td><td class="status-done">Done</td><td>4B mode. .F, .CD supported</td></tr>
        <tr><td>4.13.10</td><td>CONCAT</td><td class="status-done">Done</td><td>.CD supported</td></tr>
        <tr><td>4.13.11</td><td>MOV, MOVI</td><td class="status-done">Done</td><td>.CD supported</td></tr>
        <tr><td>4.13.12</td><td>FFI</td><td class="status-done">Done</td><td>.F supported</td></tr>
        <tr><td>4.13.13</td><td>LD, LDD, LDDI, LDH, LDS, LDSP, LDSPI</td><td class="status-not-started">Not started</td><td>Needs RAM/PMEM model</td></tr>
        <tr><td>4.13.14</td><td>ST, STD, STDI, STH, STS, STSP, STSPI</td><td class="status-not-started">Not started</td><td>Needs RAM/PMEM model</td></tr>
        <tr><td>4.13.15</td><td>JTL</td><td class="status-not-started">Not started</td><td></td></tr>
        <tr><td>4.13.16</td><td>CALL</td><td class="status-not-started">Not started</td><td></td></tr>
        <tr><td>4.13.17</td><td>RET</td><td class="status-not-started">Not started</td><td></td></tr>
        <tr><td>4.13.18</td><td>BR, BRI, BRBTST</td><td class="status-done">Done</td><td>All 11 condition codes</td></tr>
        <tr><td>4.13.19</td><td>HASH</td><td class="status-not-started">Not started</td><td>Needs LFLAG</td></tr>
        <tr><td>4.13.20</td><td>LKP, LKPLPM, LKPT, LKPTI</td><td class="status-not-started">Not started</td><td>Needs LFLAG, TCAM model</td></tr>
        <tr><td>4.13.21</td><td>SYNC, SYNCALL</td><td class="status-not-started">Not started</td><td>Needs LFLAG</td></tr>
        <tr><td>4.13.22</td><td>HALT</td><td class="status-done">Done</td><td></td></tr>
        <tr><td>4.13.23–25</td><td>CP/CHKSUM/SEND</td><td class="status-not-started">Not started</td><td>Needs frame memory model</td></tr>
        <tr><td>4.13.26–30</td><td>COUNTER/METER/CAS/BW/DLB</td><td class="status-not-started">Not started</td><td>Atomic operations</td></tr>
        <tr><td>4.13.31–54</td><td>Misc (LDRTC..MCDONE)</td><td class="status-not-started">Not started</td><td></td></tr>
        <tr><td>4.13.51</td><td>NOP</td><td class="status-done">Done</td><td></td></tr>
      </tbody>
    </table>

    {/* MAP Sail semantics */}
    <h3>MAP Instruction Semantics</h3>

    {[
      ['MNOP'], ['MHALT'],
      ['MADD', 'MADDI'], ['MSUB', 'MSUBI'],
      ['MCMP', 'MCMPI'],
      ['MAND', 'MANDI'], ['MOR', 'MORI'], ['MXOR', 'MXORI'], ['MNOT'],
      ['MSHL', 'MSHLI', 'MSHR', 'MSHRI'],
      ['MCONCAT'],
      ['MMOV', 'MMOVI'],
      ['MFFI'],
      ['MBR', 'MBRI', 'MBRBTST'],
    ].map((group) => (
      group.map((id) => {
        const src = getMexecuteClause(id);
        return src ? <div class="sail-code" set:text={src} /> : null;
      })
    ))}

    <p style="margin-top: 2rem; color: var(--text-dim); font-size: 0.85rem;">
      Sail semantics are auto-generated from the formal model. See the
      <a href="https://github.com/qobilidop/sail-xisa" style="color: var(--accent);">source repository</a>
      for the full model.
    </p>
  </div>
</Base>
```

- [ ] **Step 4: Test locally**

Generate the doc JSON first, then run the Astro dev server:

```bash
./dev.sh bash scripts/generate-sail-doc.sh
cd web && npx astro dev --port 4322
```

Visit `http://localhost:4322/sail-xisa/spec`. Verify:
- MPLv2 notice at top with links
- Parser and MAP coverage tables render correctly
- Sail code blocks appear for implemented instructions
- Nav bar shows Spec link

- [ ] **Step 5: Build test**

```bash
./dev.sh bash -c "bash scripts/generate-sail-doc.sh && cd web && npm ci && npx astro build"
```

Expected: Build succeeds, `web/dist/spec/index.html` is generated.

- [ ] **Step 6: Commit**

```bash
git add web/src/pages/spec.astro web/public/styles/spec.css web/src/layouts/Base.astro
git commit -m "Add /spec page with coverage tables and Sail semantics"
```

---

### Task 3: Update CI workflow to generate Sail docs before web build

**Files:**
- Modify: `.github/workflows/web.yml`

- [ ] **Step 1: Update web.yml**

The web workflow currently runs on bare `ubuntu-latest` with only Rust and Node. Generating the Sail doc JSON requires the Sail compiler, which is in the dev container. The simplest approach: add Sail doc generation via the dev container in the deploy job.

However, the web workflow doesn't use the dev container at all currently. A simpler approach: generate `doc.json` in the CI workflow (which already uses the dev container), upload it as an artifact, and download it in the web workflow.

Actually, the simplest approach is to restructure the deploy job to use the dev container. But that would be a large change. Instead, we can install Sail via opam in the web workflow, or we can add `model/**` as a trigger path and generate docs in a pre-step.

The most pragmatic approach: install `sail` via opam in the web workflow's deploy job, generate the JSON, then build the site.

Update `.github/workflows/web.yml`:

Add `model/**` to the push paths trigger:

```yaml
on:
  push:
    paths:
      - 'web/**'
      - 'model/**'
      - 'examples/**'
      - 'scripts/**'
      - '.github/workflows/web.yml'
  pull_request:
    paths:
      - 'web/**'
      - 'model/**'
      - 'examples/**'
      - 'scripts/**'
```

In both the `test` and `deploy` jobs, add Sail installation and doc generation steps before the Astro build:

```yaml
      - name: Install OCaml and Sail
        run: |
          sudo apt-get update && sudo apt-get install -y opam libgmp-dev zlib1g-dev z3
          opam init --disable-sandboxing --yes --bare
          opam switch create 5.1.0 --yes
          eval $(opam env --switch=5.1.0)
          opam install sail --yes

      - name: Generate Sail docs
        run: |
          eval $(opam env --switch=5.1.0)
          bash scripts/generate-sail-doc.sh
```

These steps go after checkout and before the Node/Astro build steps.

- [ ] **Step 2: Test the workflow locally (sanity check)**

Verify the script works in the dev container:

```bash
./dev.sh bash -c "bash scripts/generate-sail-doc.sh && ls -la web/src/data/doc.json"
```

Expected: `doc.json` exists.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/web.yml
git commit -m "Add Sail doc generation to web workflow"
```

---

### Task 4: Delete spec-coverage.md and update references

**Files:**
- Delete: `docs/spec-coverage.md`
- Modify: `README.md` (update reference)

- [ ] **Step 1: Update README.md**

Replace the spec-coverage reference. Change:

```markdown
See [docs/spec-coverage.md](docs/spec-coverage.md) for spec coverage
```

to:

```markdown
See the [spec coverage page](https://qobilidop.github.io/sail-xisa/spec) for spec coverage
```

- [ ] **Step 2: Delete spec-coverage.md**

```bash
git rm docs/spec-coverage.md
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Replace spec-coverage.md with /spec web page"
```
