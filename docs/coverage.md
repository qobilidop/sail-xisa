# XISA Spec Coverage

Tracks which XISA instructions are formally specified in Sail.

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
| 11 | EXTMAP | 3.12.4 | Not started | Requires MAP register model |
| 12 | MOVMAP | 3.12.5 | Not started | Requires MAP register model |
| 13 | CNCTBY | 3.12.6 | Done | |
| 14 | CNCTBI | 3.12.6 | Done | |
| 15 | STH | 3.12.7 | Not started | Requires HDR model |
| 16 | STC | 3.12.8 | Not started | |
| 17 | STCI | 3.12.8 | Not started | |
| 18 | STCH | 3.12.9 | Not started | |
| 19 | STHC | 3.12.9 | Not started | |
| 20 | ST | 3.12.10 | Not started | Requires Struct model |
| 21 | STI | 3.12.10 | Not started | |
| 22 | MOVL/MOVR variants | 3.12.12 | Not started | 6 sub-variants |
| 23 | ADD/ADDI | 3.12.13 | Done | No .CD modifier |
| 24 | SUB/SUBI/SUBII | 3.12.14 | Done | No .CD modifier |
| 25 | AND/ANDI | 3.12.15 | Done | No .CD modifier |
| 26 | OR/ORI | 3.12.16 | Done | No .CD modifier |
| 27 | CMP/CMPIBY/CMPIBI | 3.12.17 | Done | |
| 28 | BR variants | 3.12.18 | Not started | 6 sub-variants |

## MAP ISA (Section 4 of XISA spec)

Not yet started. See Section 4.12 of the XISA white paper for the full instruction list (~54 instructions).
