# XISA Spec Coverage

Tracks which XISA instructions are formally specified in Sail. Section numbers refer to the [XISA white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf).

## Parser ISA (Section 3 of XISA spec)

| # | Instruction | Spec Section | Status | Notes |
|---|-------------|-------------|--------|-------|
| 1 | NOP | 3.12.20 | Done | |
| 2 | HALT | 3.12.19 | Done | Simplified: no .RP or MAP-PC support yet |
| 3 | HALTDROP | 3.12.19 | Done | Simplified: no .RP support yet |
| 4 | MOV | 3.12.11 | Done | No .CD modifier yet |
| 5 | MOVI | 3.12.11 | Done | No .CD modifier yet |
| 6 | EXT | 3.12.3 | Done | .CD supported. No .PR, .SCSM, .ECSM yet. |
| 7 | EXTNXTP | 3.12.3 | Not started | |
| 8 | NXTP | 3.12.1 | Not started | Requires transition table model |
| 9 | PSEEK | 3.12.2 | Not started | Requires PSEEK table model |
| 10 | PSEEKNXTP | 3.12.2 | Not started | |
| 11 | EXTMAP | 3.12.4 | Done | No .PR, .SCSM, .ECSM yet |
| 12 | MOVMAP | 3.12.5 | Done | No .HDR modifier yet |
| 13 | CNCTBY | 3.12.6 | Done | |
| 14 | CNCTBI | 3.12.6 | Done | |
| 15 | STH | 3.12.7 | Done | .H supported. No JumpMode, .SCSM, .ECSM yet |
| 16 | STC | 3.12.8 | Done | No JumpMode, .SCSM, .ECSM yet |
| 17 | STCI | 3.12.8 | Done | No JumpMode, .SCSM, .ECSM yet |
| 18 | STCH | 3.12.9 | Done | .H supported. No JumpMode, .SCSM, .ECSM yet |
| 19 | STHC | 3.12.9 | Done | No JumpMode, .SCSM, .ECSM yet |
| 20 | ST | 3.12.10 | Done | .H supported. HW bits 6-31 restriction not enforced |
| 21 | STI | 3.12.10 | Done | |
| 22 | MOVL/MOVR variants | 3.12.12 | Done | .CD supported. 6 sub-variants: MOVL, MOVLI, MOVLII, MOVR, MOVRI, MOVRII |
| 23 | ADD/ADDI | 3.12.13 | Done | No .CD modifier |
| 24 | SUB/SUBI/SUBII | 3.12.14 | Done | No .CD modifier |
| 25 | AND/ANDI | 3.12.15 | Done | No .CD modifier |
| 26 | OR/ORI | 3.12.16 | Done | No .CD modifier |
| 27 | CMP/CMPIBY/CMPIBI | 3.12.17 | Done | |
| 28 | BR/BRBTST | 3.12.18 | Done | BRNS, BRNXTP, BRBTSTNXTP deferred (need transition table) |

## MAP ISA (Section 4 of XISA spec)

Not yet started. See Section 4.12 of the XISA white paper for the full instruction list (~54 instructions).
