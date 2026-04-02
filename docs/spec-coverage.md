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

| Spec Section | Instruction(s) | Status | Notes |
|-------------|----------------|--------|-------|
| 4.13.1 | ADD, ADDI | Done | .F, .SX, .SH supported |
| 4.13.2 | SUB, SUBI | Done | .F, .SX, .SH supported |
| 4.13.3 | MOD, MODI | Not started | Async, needs LFLAG |
| 4.13.4 | CMP, CMPI | Done | Always sets Z, C |
| 4.13.5 | AND, ANDI | Done | .F supported |
| 4.13.6 | OR, ORI | Done | .F supported |
| 4.13.7 | XOR, XORI | Done | .F supported |
| 4.13.8 | NOT | Done | .F supported |
| 4.13.9 | SHL, SHLI, SHR, SHRI | Done | 4B mode. .F, .CD supported |
| 4.13.10 | CONCAT | Done | .CD supported |
| 4.13.11 | MOV, MOVI | Done | .CD supported |
| 4.13.12 | FFI | Done | .F supported |
| 4.13.13 | LD, LDD, LDDI, LDH, LDS, LDSP, LDSPI | Not started | Needs RAM/PMEM model |
| 4.13.14 | ST, STD, STDI, STH, STS, STSP, STSPI | Not started | Needs RAM/PMEM model |
| 4.13.15 | JTL | Not started | |
| 4.13.16 | CALL | Not started | |
| 4.13.17 | RET | Not started | |
| 4.13.18 | BR, BRI, BRBTST | Done | All 11 condition codes |
| 4.13.19 | HASH | Not started | Needs LFLAG |
| 4.13.20 | LKP, LKPLPM, LKPT, LKPTI | Not started | Needs LFLAG, TCAM model |
| 4.13.21 | SYNC, SYNCALL | Not started | Needs LFLAG |
| 4.13.22 | HALT | Done | |
| 4.13.23-25 | CP/CHKSUM/SEND | Not started | Needs frame memory model |
| 4.13.26-30 | COUNTER/METER/CAS/BW/DLB | Not started | Atomic operations |
| 4.13.31-54 | Misc (LDRTC..MCDONE) | Not started | |
| 4.13.51 | NOP | Done | |
