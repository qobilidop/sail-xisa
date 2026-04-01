# Code Conventions

Naming and structural conventions for the Sail XISA model.

## Instruction Naming

Instruction union clauses use `P` + spec name for parser ISA:

| Spec | Sail union clause | Pattern |
|------|-------------------|---------|
| NOP | `PNOP` | `P` + name |
| EXT | `PEXT` | `P` + name |
| BRBTSTNXTP | `PBRBTSTNXTP` | `P` + name |

The `P` prefix avoids name collisions when MAP ISA instructions are added (MAP instructions will use a different prefix).

## Register Naming

Parser registers use a `p` prefix or descriptive name:

| Spec Name | Sail Name | Notes |
|-----------|-----------|-------|
| R0-R3 | `PR[0]`-`PR[3]` | Enum `pregidx`: PR0, PR1, PR2, PR3 |
| RN (null) | `PRN` | Reads as zero, writes discarded |
| Cursor | `pcursor` | |
| PC | `ppc` | Parser program counter |
| Z, N flags | `pflag_z`, `pflag_n` | |
| HDR.PRESENT | `hdr_present` | No prefix — unambiguous |
| HDR.OFFSET | `hdr_offset` | No prefix — unambiguous |
| Struct-0 (SMD) | `struct0` | No prefix — unambiguous |
| MAP R0-R13 | `MAP[0]`-`MAP[13]` | In `model/map/state.sail` |

## Table Naming

Hardware lookup tables use descriptive prefixes with parallel arrays:

| Table | Prefix | File |
|-------|--------|------|
| Transition table | `tt_` | `model/parser/transition.sail` |
| PSEEK table | `pseek_` | `model/parser/pseek.sail` |

## File Organization

- `model/prelude.sail` — Type aliases, shared enums
- `model/parser/params.sail` — Implementation-chosen parameters (table sizes, bit widths)
- `model/parser/types.sail` — Instruction union type (`pinstr`) and register enums
- `model/parser/transition.sail` — Transition table state and lookup
- `model/parser/pseek.sail` — PSEEK table state and lookup
- `model/parser/state.sail` — Parser registers, initialization, helpers
- `model/parser/insts.sail` — All execute clauses (scattered function)
- `model/parser/exec.sail` — Fetch-decode-execute loop
- `model/map/state.sail` — MAP register file

## Include Order

`model/main.sail` includes files in dependency order:

```
prelude.sail        → type aliases, enums
map/state.sail      → MAP registers (no dependencies)
parser/params.sail  → documentation only (no code dependencies)
parser/types.sail   → pinstr union, pregidx enum
parser/transition.sail → transition table (depends on types for bits24)
parser/pseek.sail   → PSEEK table (depends on types)
parser/state.sail   → parser registers, init (calls transition_table_init, pseek_table_init)
parser/decode.sail  → placeholder
parser/insts.sail   → execute clauses (depends on everything above)
parser/exec.sail    → fetch-decode-execute loop
```
