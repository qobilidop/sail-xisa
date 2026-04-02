# XISA Spec Coverage

Tracks which XISA instructions are formally specified in Sail. Section numbers refer to the [XISA white paper](https://cdn.sanity.io/files/eqivwe42/production/affd0d0005566d4d8c50e05eff7fb60a43049a9f.pdf). Ordered by spec section number.

## Parser ISA (Section 3 of XISA spec)

| Spec Section | Instruction(s) | Status | Notes |
|-------------|----------------|--------|-------|
| 3.12.1 | NXTP | Done | |
| 3.12.2 | PSEEK, PSEEKNXTP | Done | No PSEEK_ERROR/trap, no .CD. Fixed hdr length per entry |
| 3.12.3 | EXT, EXTNXTP | Done | .CD supported. No .PR, .SCSM, .ECSM yet |
| 3.12.4 | EXTMAP | Done | No .PR, .SCSM, .ECSM yet |
| 3.12.5 | MOVMAP | Done | No .HDR modifier yet |
| 3.12.6 | CNCTBY, CNCTBI | Done | .CD supported |
| 3.12.7 | STH | Done | .H supported. No JumpMode, .SCSM, .ECSM yet |
| 3.12.8 | STC, STCI | Done | No JumpMode, .SCSM, .ECSM yet |
| 3.12.9 | STCH, STHC | Done | .H supported (STCH). No JumpMode, .SCSM, .ECSM yet |
| 3.12.10 | ST, STI | Done | .H supported (ST). HW bits 6-31 restriction not enforced |
| 3.12.11 | MOV, MOVI | Done | .CD supported |
| 3.12.12 | MOVL, MOVLI, MOVLII, MOVR, MOVRI, MOVRII | Done | .CD supported |
| 3.12.13 | ADD, ADDI | Done | .CD supported |
| 3.12.14 | SUB, SUBI, SUBII | Done | .CD supported |
| 3.12.15 | AND, ANDI | Done | .CD supported |
| 3.12.16 | OR, ORI | Done | .CD supported |
| 3.12.17 | CMP, CMPIBY, CMPIBI | Done | |
| 3.12.18 | BR, BRBTST, BRNS, BRNXTP, BRBTSTNXTP, BRBTSTNS | Done | JumpMode 100 (trap) deferred |
| 3.12.19 | HALT, HALTDROP | Done | No .RP or MAP-PC support yet |
| 3.12.20 | NOP | Done | |

## MAP ISA (Section 4 of XISA spec)

Not yet started. See Section 4.12 of the XISA white paper for the full instruction list (~54 instructions).
