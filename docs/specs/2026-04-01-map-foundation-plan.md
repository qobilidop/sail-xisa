# MAP ISA Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the MAP ISA execution model with registers, ZNCV flags, fetch-decode-execute loop, and 22 instruction variants (arithmetic, logic, data movement, branching, control).

**Architecture:** Extends the existing project by adding `model/map/` files (types, state, decode, insts, exec) mirroring the parser structure. MAP uses word-oriented (32-bit) register addressing within 128-bit registers, 4 condition code flags (ZNCV), and 64-bit binary instruction encoding. Tests go in `test/map/`.

**Tech Stack:** Sail language, CMake/CTest, dev container via `./dev.sh`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `model/map/state.sail` | Modify | Extend: 16 registers, word accessors, ZNCV flags, MAP PC, instruction memory, halted flag |
| `model/map/types.sail` | Create | Register index enum, word select enum, condition codes, instruction union |
| `model/map/decode.sail` | Create | 64-bit binary encoding mappings |
| `model/map/insts.sail` | Create | Execute clauses for all 22 instruction variants |
| `model/map/exec.sail` | Create | MAP fetch-decode-execute loop (map_step, map_run) |
| `model/main.sail` | Modify | Add `$include` lines for new MAP files |
| `test/CMakeLists.txt` | Modify | Register MAP test executables |
| `test/map/test_nop_halt.sail` | Create | NOP and HALT tests |
| `test/map/test_mov.sail` | Create | MOV, MOVI, .CD tests |
| `test/map/test_add.sail` | Create | ADD, ADDI, .F, .SX, .SH tests |
| `test/map/test_sub.sail` | Create | SUB, SUBI tests |
| `test/map/test_cmp.sail` | Create | CMP, CMPI, flag tests |
| `test/map/test_logic.sail` | Create | AND, ANDI, OR, ORI, XOR, XORI, NOT, .F tests |
| `test/map/test_br.sail` | Create | BR, BRI, BRBTST, condition code tests |
| `test/map/test_program.sail` | Create | Multi-instruction MAP programs via map_run |
| `test/map/test_encoding.sail` | Create | Encoding round-trip tests |
| `docs/spec-coverage.md` | Modify | Add MAP ISA coverage table |

---

### Task 1: MAP state model

Extend `model/map/state.sail` with the full MAP execution state.

**Files:**
- Modify: `model/map/state.sail`

- [ ] **Step 1: Expand register file and add MAP state**

Replace the entire contents of `model/map/state.sail` with:

```sail
// MAP register file and execution state.
// See XISA spec sections 4.2-4.3, 4.8.2.

// MAP register file: 16 x 128-bit registers.
// R0-R10: general purpose
// R11: HDR.PRESENT (preloaded by parser)
// R12-R13: HDR.OFFSET0/1 (preloaded by parser)
// R14: debug (not modeled)
// R15: null register (reads zero, writes discarded)
register MAP : vector(16, bits128)

// Condition code flags (Section 4.8.2).
// Only updated when .F modifier is used (except CMP which always updates).
register mflag_z : bool  // Zero
register mflag_n : bool  // Negative
register mflag_c : bool  // Carry
register mflag_v : bool  // Overflow

// MAP program counter (16-bit, matching parser convention).
register mpc : bits16

// MAP halted flag.
register map_halted : bool

// MAP instruction memory: 65536 x 64-bit slots.
register map_imem : vector(65536, bits(64))

val init_map_regs : unit -> vector(16, bits128)
function init_map_regs() = [
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
    sail_zeros(128), sail_zeros(128), sail_zeros(128), sail_zeros(128),
]

val init_map_imem : unit -> vector(65536, bits(64))
function init_map_imem() = {
    var mem : vector(65536, bits(64)) = undefined;
    var i : int = 0;
    while i < 65536 do {
        mem[i] = sail_zeros(64);
        i = i + 1
    };
    mem
}

// Initialize all MAP state.
val map_init : unit -> unit
function map_init() = {
    MAP = init_map_regs();
    mflag_z = false;
    mflag_n = false;
    mflag_c = false;
    mflag_v = false;
    mpc = 0x0000;
    map_halted = false;
    map_imem = init_map_imem()
}

// Read a full 128-bit MAP register.
// R15 always reads as zero (null register).
val read_mapreg : int -> bits128
function read_mapreg(idx) = {
    assert(0 <= idx & idx < 16, "MAP register index out of bounds");
    if idx == 15 then sail_zeros(128)
    else MAP[idx]
}

// Write a full 128-bit MAP register.
// Writes to R15 are silently discarded.
val write_mapreg : (int, bits128) -> unit
function write_mapreg(idx, v) = {
    assert(0 <= idx & idx < 16, "MAP register index out of bounds");
    if idx != 15 then MAP[idx] = v
}

// Read a 32-bit word from a MAP register.
// word_sel: 0=MSW (bits 127:96), 1=(95:64), 2=(63:32), 3=LSW (31:0).
val read_mapword : (int, int) -> bits(32)
function read_mapword(reg_idx, word_sel) = {
    let full = read_mapreg(reg_idx);
    let shift_amount = (3 - word_sel) * 32;
    sail_mask(32, sail_shiftright(full, shift_amount))
}

// Write a 32-bit word to a MAP register.
// Preserves other words in the register.
val write_mapword : (int, int, bits(32)) -> unit
function write_mapword(reg_idx, word_sel, val32) = {
    if reg_idx != 15 then {
        let full = read_mapreg(reg_idx);
        let bit_offset = (3 - word_sel) * 32;
        // Clear the target word, then OR in the new value
        let mask : bits128 = sail_shiftleft(sail_zero_extend(0xFFFFFFFF : bits(32), 128), bit_offset);
        let cleared = full & not_vec(mask);
        let new_val = cleared | sail_shiftleft(sail_zero_extend(val32, 128), bit_offset);
        MAP[reg_idx] = new_val
    }
}

// Read raw instruction memory slot.
val read_map_imem_raw : int -> bits(64)
function read_map_imem_raw(idx) = {
    assert(0 <= idx & idx < 65536, "MAP instruction memory index out of bounds");
    map_imem[idx]
}

// Load a MAP program into instruction memory starting at address 0.
val map_load_program : vector('n, bits(64)) -> unit
function map_load_program(prog) = {
    var i : int = 0;
    while i < length(prog) do {
        map_imem[i] = prog[i];
        i = i + 1
    }
}
```

- [ ] **Step 2: Update parser state.sail to use new MAP init**

In `model/parser/state.sail`, the `parser_init()` function calls `MAP = init_map()`. Update it to call `map_init()` instead, and remove the old `MAP = init_map()` line. The `map_init()` function now handles MAP register initialization.

Find the line `MAP = init_map();` in `parser_init()` and replace with `map_init();`.

- [ ] **Step 3: Build to verify compilation**

Run: `./dev.sh cmake --build build 2>&1 | tail -5`
Expected: Build succeeds (may have warnings about unused functions)

- [ ] **Step 4: Commit**

```bash
git add model/map/state.sail model/parser/state.sail
git commit -m "Extend MAP state: 16 registers, word accessors, ZNCV flags, PC, instruction memory"
```

---

### Task 2: MAP types and instruction union

**Files:**
- Create: `model/map/types.sail`

- [ ] **Step 1: Create types.sail with register index, word select, conditions, and instruction union**

```sail
// MAP ISA types: register indices, word select, conditions, instruction union.

// MAP register indices (4-bit, 0-15).
enum mregidx = { MR0, MR1, MR2, MR3, MR4, MR5, MR6, MR7,
                 MR8, MR9, MR10, MR11, MR12, MR13, MR14, MRN }

val mregidx_to_nat : mregidx -> range(0, 15)
function mregidx_to_nat(r) = match r {
    MR0  => 0,  MR1  => 1,  MR2  => 2,  MR3  => 3,
    MR4  => 4,  MR5  => 5,  MR6  => 6,  MR7  => 7,
    MR8  => 8,  MR9  => 9,  MR10 => 10, MR11 => 11,
    MR12 => 12, MR13 => 13, MR14 => 14, MRN  => 15,
}

// Word select within a 128-bit register (2-bit, 0-3).
// Word 0 = MSW (bits 127:96), Word 3 = LSW (bits 31:0).
enum mwordsel = { MW0, MW1, MW2, MW3 }

val mwordsel_to_nat : mwordsel -> range(0, 3)
function mwordsel_to_nat(w) = match w {
    MW0 => 0, MW1 => 1, MW2 => 2, MW3 => 3,
}

// Branch condition codes (4-bit).
enum mcond = {
    MCC_EQ,    // Z = 1
    MCC_NEQ,   // Z = 0
    MCC_LT,    // N = 1
    MCC_GT,    // N = 0 and Z = 0
    MCC_GE,    // N = 0
    MCC_LE,    // N = 1 or Z = 1
    MCC_C,     // C = 1
    MCC_NC,    // C = 0
    MCC_V,     // V = 1
    MCC_NV,    // V = 0
    MCC_AL,    // Always
}

// Bit-test condition for BRBTST.
enum mbtcond = { MBT_CLR, MBT_SET }

// MAP instruction union (scattered).
scattered union minstr

// NOP: No operation.
union clause minstr = MNOP : unit

// HALT: End MAP execution.
union clause minstr = MHALT : unit

// MOV: Copy 4B word. Fields: (dest_reg, dest_word, src_reg, src_word, clear_dest)
union clause minstr = MMOV : (mregidx, mwordsel, mregidx, mwordsel, bool)

// MOVI: Load immediate into 4B word.
// Fields: (dest_reg, dest_word, immediate32, clear_dest)
union clause minstr = MMOVI : (mregidx, mwordsel, bits(32), bool)

// ADD: Dest[N:0] = Src1[i1:j1] + Src2[i2:j2]
// Fields: (dest_reg, dest_word, src1_reg, src1_word, src1_offset, src1_size,
//          src2_reg, src2_word, src2_offset, src2_size, set_flags, sign_extend, short_mode)
union clause minstr = MADD : (mregidx, mwordsel, mregidx, mwordsel, bits(5), bits(5),
                              mregidx, mwordsel, bits(5), bits(5), bool, bool, bool)

// ADDI: Dest[N:0] = Src1[i1:j1] + ImmediateValue
// Fields: (dest_reg, dest_word, src1_reg, src1_word, src1_offset, src1_size,
//          immediate16, set_flags, sign_extend, short_mode)
union clause minstr = MADDI : (mregidx, mwordsel, mregidx, mwordsel, bits(5), bits(5),
                               bits16, bool, bool, bool)

// SUB: Dest[N:0] = Src1[i1:j1] - Src2[i2:j2]
// Fields: same as ADD
union clause minstr = MSUB : (mregidx, mwordsel, mregidx, mwordsel, bits(5), bits(5),
                              mregidx, mwordsel, bits(5), bits(5), bool, bool, bool)

// SUBI: Dest[N:0] = Src1[i1:j1] - ImmediateValue
// Fields: same as ADDI
union clause minstr = MSUBI : (mregidx, mwordsel, mregidx, mwordsel, bits(5), bits(5),
                               bits16, bool, bool, bool)

// CMP: Compare two register sub-fields. Always sets Z and C flags. Result discarded.
// Fields: (src1_reg, src1_word, src1_offset, src2_reg, src2_word, src2_offset, size)
union clause minstr = MCMP : (mregidx, mwordsel, bits(5), mregidx, mwordsel, bits(5), bits(5))

// CMPI: Compare register sub-field with immediate.
// Fields: (src1_reg, src1_word, src1_offset, immediate16, size)
union clause minstr = MCMPI : (mregidx, mwordsel, bits(5), bits16, bits(5))

// AND: Dest[Size-1:0] = Src1[i1:j1] & Src2[i2:j2]
// Fields: (dest_reg, dest_word, src1_reg, src1_word, src1_offset,
//          src2_reg, src2_word, src2_offset, size, set_flags)
union clause minstr = MAND : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                              mregidx, mwordsel, bits(5), bits(5), bool)

// ANDI: Dest[Size-1:0] = Src1[i1:j1] & ImmediateValue
// Fields: (dest_reg, dest_word, src1_reg, src1_word, src1_offset,
//          immediate16, size, set_flags)
union clause minstr = MANDI : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                               bits16, bits(5), bool)

// OR: Dest[Size-1:0] = Src1[i1:j1] | Src2[i2:j2]
// Fields: same as AND
union clause minstr = MOR : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                             mregidx, mwordsel, bits(5), bits(5), bool)

// ORI: Dest[Size-1:0] = Src1[i1:j1] | ImmediateValue
// Fields: same as ANDI
union clause minstr = MORI : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                              bits16, bits(5), bool)

// XOR: Dest[Size-1:0] = Src1[i1:j1] ^ Src2[i2:j2]
// Fields: same as AND
union clause minstr = MXOR : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                              mregidx, mwordsel, bits(5), bits(5), bool)

// XORI: Dest[Size-1:0] = Src1[i1:j1] ^ ImmediateValue
// Fields: same as ANDI
union clause minstr = MXORI : (mregidx, mwordsel, mregidx, mwordsel, bits(5),
                               bits16, bits(5), bool)

// NOT: Dest[Size-1:0] = ~Src[i:j]
// Fields: (dest_reg, dest_word, src_reg, src_word, src_offset, size, set_flags)
union clause minstr = MNOT : (mregidx, mwordsel, mregidx, mwordsel, bits(5), bits(5), bool)

// BR: Branch to address in register if condition met (absolute address).
// Fields: (condition, src_reg, src_word)
union clause minstr = MBR : (mcond, mregidx, mwordsel)

// BRI: Branch to PC-relative offset if condition met.
// Fields: (condition, offset16)
union clause minstr = MBRI : (mcond, bits16)

// BRBTST: Test bit in register word and branch.
// Fields: (bit_test_cond, src_reg, src_word, bit_offset, target16)
union clause minstr = MBRBTST : (mbtcond, mregidx, mwordsel, bits(5), bits16)

end minstr
```

- [ ] **Step 2: Update main.sail to include new MAP files**

Replace `model/main.sail` contents with:

```sail
$include "prelude.sail"
$include "map/types.sail"
$include "map/state.sail"
$include "parser/params.sail"
$include "parser/types.sail"
$include "parser/transition.sail"
$include "parser/pseek.sail"
$include "parser/decode.sail"
$include "parser/state.sail"
$include "parser/insts.sail"
$include "parser/exec.sail"
```

Note: `map/types.sail` must come before `map/state.sail` (state uses types). Both must come before parser state (which calls `map_init()`).

- [ ] **Step 3: Build to verify**

Run: `./dev.sh cmake --build build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add model/map/types.sail model/main.sail
git commit -m "Add MAP types: register indices, word select, conditions, instruction union"
```

---

### Task 3: MAP instruction execution — NOP, HALT, MOV, MOVI

**Files:**
- Create: `model/map/insts.sail`
- Modify: `model/main.sail`

- [ ] **Step 1: Create insts.sail with execute function and first instructions**

```sail
// MAP instruction execution.

val mexecute : minstr -> ExecutionResult
scattered function mexecute

// NOP: No operation.
function clause mexecute(MNOP()) = RETIRE_SUCCESS

// HALT: End MAP execution.
function clause mexecute(MHALT()) = {
    map_halted = true;
    RETIRE_HALT
}

// MOV: Copy 4B word from source to destination.
// If clear_dest, clear the entire 16B destination register first.
function clause mexecute(MMOV(rd, rw, rs, sw, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let rs_idx = mregidx_to_nat(rs);
    let sw_idx = mwordsel_to_nat(sw);
    if clear_dest then write_mapreg(rd_idx, sail_zeros(128));
    let val32 = read_mapword(rs_idx, sw_idx);
    write_mapword(rd_idx, rw_idx, val32);
    RETIRE_SUCCESS
}

// MOVI: Load immediate (up to 32b) into a 4B word.
// If clear_dest, clear the entire 16B destination register first.
function clause mexecute(MMOVI(rd, rw, imm32, clear_dest)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    if clear_dest then write_mapreg(rd_idx, sail_zeros(128));
    write_mapword(rd_idx, rw_idx, imm32);
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Add include to main.sail**

Add `$include "map/insts.sail"` after `$include "map/state.sail"` in `model/main.sail`.

- [ ] **Step 3: Build to verify**

Run: `./dev.sh cmake --build build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add model/map/insts.sail model/main.sail
git commit -m "Add MAP execute function: NOP, HALT, MOV, MOVI"
```

---

### Task 4: MAP execution loop + NOP/HALT/MOV tests

**Files:**
- Create: `model/map/exec.sail`
- Create: `test/map/test_nop_halt.sail`
- Create: `test/map/test_mov.sail`
- Modify: `model/main.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create exec.sail**

```sail
// MAP fetch-decode-execute loop.

val map_step : unit -> ExecutionResult
function map_step() = {
    let pc_idx : int = unsigned(mpc);
    let encoded : bits(64) = read_map_imem_raw(pc_idx);
    let instr : minstr = decode_minstr(encoded);
    mpc = mpc + 0x0001;
    mexecute(instr)
}

val map_run : unit -> ExecutionResult
function map_run() = {
    var steps : int = 0;
    var result : ExecutionResult = RETIRE_SUCCESS;
    var done : bool = false;
    while not_bool(done) & steps < 10000 do {
        result = map_step();
        match result {
            RETIRE_HALT => done = true,
            RETIRE_DROP => done = true,
            RETIRE_SUCCESS => (),
        };
        steps = steps + 1
    };
    result
}
```

Note: This depends on `decode_minstr` which will be created in the encoding task. For now, the exec.sail will be created but tests using `map_step`/`map_run` must wait until encoding is done. NOP/HALT/MOV tests in this task use direct `mexecute()` calls.

- [ ] **Step 2: Create test_nop_halt.sail**

```sail
// Tests for MAP NOP and HALT instructions.

val test_nop : unit -> unit
function test_nop() = {
    map_init();
    let result = mexecute(MNOP());
    assert(result == RETIRE_SUCCESS, "NOP should return success");
    assert(map_halted == false, "NOP should not halt")
}

val test_halt : unit -> unit
function test_halt() = {
    map_init();
    let result = mexecute(MHALT());
    assert(result == RETIRE_HALT, "HALT should return RETIRE_HALT");
    assert(map_halted == true, "HALT should set map_halted")
}

val main : unit -> unit
function main() = {
    test_nop();
    test_halt()
}
```

- [ ] **Step 3: Create test_mov.sail**

```sail
// Tests for MAP MOV and MOVI instructions.

val test_mov_basic : unit -> unit
function test_mov_basic() = {
    map_init();
    // Write a value to R0.W3 (LSW)
    write_mapword(0, 3, 0xDEADBEEF);
    // MOV R1.W3, R0.W3
    let _ = mexecute(MMOV(MR1, MW3, MR0, MW3, false));
    assert(read_mapword(1, 3) == 0xDEADBEEF, "MOV should copy word")
}

val test_mov_word_select : unit -> unit
function test_mov_word_select() = {
    map_init();
    // Write to R0.W0 (MSW)
    write_mapword(0, 0, 0x12345678);
    // MOV R1.W2, R0.W0 — copy MSW to word 2
    let _ = mexecute(MMOV(MR1, MW2, MR0, MW0, false));
    assert(read_mapword(1, 2) == 0x12345678, "MOV should copy across word positions")
}

val test_mov_cd : unit -> unit
function test_mov_cd() = {
    map_init();
    // Fill R1 with all 1s
    write_mapreg(1, 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF);
    write_mapword(0, 3, 0x000000AB);
    // MOV.CD R1.W3, R0.W3 — should clear R1 first
    let _ = mexecute(MMOV(MR1, MW3, MR0, MW3, true));
    assert(read_mapreg(1) == 0x00000000_00000000_00000000_000000AB,
        "MOV.CD should clear entire 16B register then copy word")
}

val test_mov_null_reg : unit -> unit
function test_mov_null_reg() = {
    map_init();
    write_mapword(0, 3, 0xDEADBEEF);
    // MOV RN.W3, R0.W3 — write to null register, should be discarded
    let _ = mexecute(MMOV(MRN, MW3, MR0, MW3, false));
    assert(read_mapword(15, 3) == 0x00000000, "Null register should always read zero")
}

val test_movi_basic : unit -> unit
function test_movi_basic() = {
    map_init();
    // MOVI R0.W3, 0x42
    let _ = mexecute(MMOVI(MR0, MW3, 0x00000042, false));
    assert(read_mapword(0, 3) == 0x00000042, "MOVI should load immediate")
}

val test_movi_32bit : unit -> unit
function test_movi_32bit() = {
    map_init();
    // MOVI R0.W0, 0xDEADBEEF (full 32-bit immediate)
    let _ = mexecute(MMOVI(MR0, MW0, 0xDEADBEEF, false));
    assert(read_mapword(0, 0) == 0xDEADBEEF, "MOVI should load full 32-bit immediate")
}

val test_movi_cd : unit -> unit
function test_movi_cd() = {
    map_init();
    write_mapreg(0, 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF);
    // MOVI.CD R0.W3, 0xAB
    let _ = mexecute(MMOVI(MR0, MW3, 0x000000AB, true));
    assert(read_mapreg(0) == 0x00000000_00000000_00000000_000000AB,
        "MOVI.CD should clear entire 16B register then load immediate")
}

val main : unit -> unit
function main() = {
    test_mov_basic();
    test_mov_word_select();
    test_mov_cd();
    test_mov_null_reg();
    test_movi_basic();
    test_movi_32bit();
    test_movi_cd()
}
```

- [ ] **Step 4: Register tests in CMakeLists.txt**

Add these lines to the end of `test/CMakeLists.txt`:

```cmake
# MAP ISA tests
add_sail_test(test_map_nop_halt test/map/test_nop_halt.sail)
add_sail_test(test_map_mov test/map/test_mov.sail)
```

- [ ] **Step 5: Add exec.sail include to main.sail**

Add `$include "map/exec.sail"` after `$include "map/insts.sail"` in `model/main.sail`. (The exec.sail won't be fully functional until encoding is done, but it needs to compile.)

- [ ] **Step 6: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_map --output-on-failure`
Expected: test_map_nop_halt and test_map_mov PASS

- [ ] **Step 7: Commit**

```bash
git add model/map/exec.sail model/main.sail test/map/test_nop_halt.sail test/map/test_mov.sail test/CMakeLists.txt
git commit -m "Add MAP execution loop, NOP/HALT/MOV/MOVI with tests"
```

---

### Task 5: Arithmetic helpers and ADD/ADDI

Implement operand extraction, result writing, flag setting, and ADD/ADDI instructions.

**Files:**
- Modify: `model/map/insts.sail`
- Create: `test/map/test_add.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Add arithmetic helpers to insts.sail**

Add these helper functions at the top of `model/map/insts.sail` (before the execute clauses):

```sail
// Extract a bit-field from a 32-bit word and zero-extend to 32 bits.
val map_extract : (bits(32), nat, nat) -> bits(32)
function map_extract(word, offset, size) = {
    let shifted = sail_mask(32, sail_shiftright(sail_zero_extend(word, 64), offset));
    shifted & sail_mask(32, sail_ones(size))
}

// Extract and sign-extend a bit-field from a 32-bit word to 32 bits.
val map_extract_sx : (bits(32), nat, nat) -> bits(32)
function map_extract_sx(word, offset, size) = {
    let extracted = map_extract(word, offset, size);
    // Check sign bit (MSbit of the extracted field)
    let sign_bit = sail_shiftright(extracted, size - 1) & 0x00000001;
    if sign_bit == 0x00000001 then {
        // Sign-extend: set all bits above size to 1
        let sign_mask : bits(32) = not_vec(sail_mask(32, sail_ones(size)));
        extracted | sign_mask
    } else {
        extracted
    }
}

// Write result to destination word.
// For normal mode: writes 32 bits (full word replacement).
// For short mode (.SH): writes only low 16 bits, preserving upper 16.
val map_write_result : (int, int, bits(32), bool) -> unit
function map_write_result(rd_idx, rw_idx, result, short_mode) = {
    if short_mode then {
        let existing = read_mapword(rd_idx, rw_idx);
        let merged = (existing & 0xFFFF0000) | (result & 0x0000FFFF);
        write_mapword(rd_idx, rw_idx, merged)
    } else {
        write_mapword(rd_idx, rw_idx, result)
    }
}

// Set ZNCV flags for addition.
val map_set_flags_add : (bits(32), bits(32), bits(32), bool) -> unit
function map_set_flags_add(op1, op2, result, short_mode) = {
    let n : nat = if short_mode then 15 else 31;
    mflag_z = result == 0x00000000;
    mflag_n = (sail_shiftright(result, n) & 0x00000001) == 0x00000001;
    // C: carry out — use 64-bit addition to detect
    let wide_sum : bits(64) = sail_zero_extend(op1, 64) + sail_zero_extend(op2, 64);
    let limit : nat = if short_mode then 16 else 32;
    mflag_c = (sail_shiftright(wide_sum, limit) & sail_zero_extend(0x00000001 : bits(32), 64)) != sail_zeros(64);
    // V: signed overflow
    let a_sign = sail_shiftright(op1, n) & 0x00000001;
    let b_sign = sail_shiftright(op2, n) & 0x00000001;
    let r_sign = sail_shiftright(result, n) & 0x00000001;
    mflag_v = (a_sign == b_sign) & (r_sign != a_sign)
}

// Set ZNCV flags for subtraction (A - B).
val map_set_flags_sub : (bits(32), bits(32), bits(32), bool) -> unit
function map_set_flags_sub(op1, op2, result, short_mode) = {
    let n : nat = if short_mode then 15 else 31;
    mflag_z = result == 0x00000000;
    mflag_n = (sail_shiftright(result, n) & 0x00000001) == 0x00000001;
    // C: borrow (A < B unsigned)
    mflag_c = sail_zero_extend(op1, 64) < sail_zero_extend(op2, 64);
    // V: signed overflow
    let a_sign = sail_shiftright(op1, n) & 0x00000001;
    let b_sign = sail_shiftright(op2, n) & 0x00000001;
    let r_sign = sail_shiftright(result, n) & 0x00000001;
    mflag_v = (a_sign != b_sign) & (r_sign != a_sign)
}

// Set ZNCV flags for logic operations (AND, OR, XOR, NOT).
val map_set_flags_logic : bits(32) -> unit
function map_set_flags_logic(result) = {
    mflag_z = result == 0x00000000;
    mflag_n = (sail_shiftright(result, 31) & 0x00000001) == 0x00000001;
    mflag_c = false;
    mflag_v = false
}
```

- [ ] **Step 2: Add ADD and ADDI execute clauses**

Append to `model/map/insts.sail`:

```sail
// ADD: Dest[N:0] = Source1[i1:j1] + Source2[i2:j2]
function clause mexecute(MADD(rd, rw, rs1, sw1, s1off, s1sz, rs2, sw2, s2off, s2sz,
                              set_flags, sign_extend, short_mode)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let w2 = read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2));
    let op1 : bits(32) = if sign_extend then map_extract_sx(w1, unsigned(s1off), unsigned(s1sz))
                          else map_extract(w1, unsigned(s1off), unsigned(s1sz));
    let op2 : bits(32) = if sign_extend then map_extract_sx(w2, unsigned(s2off), unsigned(s2sz))
                          else map_extract(w2, unsigned(s2off), unsigned(s2sz));
    let mask : bits(32) = if short_mode then 0x0000FFFF else 0xFFFFFFFF;
    let result : bits(32) = (op1 + op2) & mask;
    if set_flags then map_set_flags_add(op1, op2, result, short_mode);
    map_write_result(rd_idx, rw_idx, result, short_mode);
    RETIRE_SUCCESS
}

// ADDI: Dest[N:0] = Source1[i1:j1] + ImmediateValue
function clause mexecute(MADDI(rd, rw, rs1, sw1, s1off, s1sz, imm16,
                               set_flags, sign_extend, short_mode)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let op1 : bits(32) = if sign_extend then map_extract_sx(w1, unsigned(s1off), unsigned(s1sz))
                          else map_extract(w1, unsigned(s1off), unsigned(s1sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let mask : bits(32) = if short_mode then 0x0000FFFF else 0xFFFFFFFF;
    let result : bits(32) = (op1 + op2) & mask;
    if set_flags then map_set_flags_add(op1, op2, result, short_mode);
    map_write_result(rd_idx, rw_idx, result, short_mode);
    RETIRE_SUCCESS
}
```

- [ ] **Step 3: Create test_add.sail**

```sail
// Tests for MAP ADD and ADDI instructions.

val test_add_basic : unit -> unit
function test_add_basic() = {
    map_init();
    write_mapword(0, 3, 0x0000000A);
    write_mapword(1, 3, 0x00000014);
    // ADD R2.W3, R0.W3[0:8], R1.W3[0:8] — no flags
    let _ = mexecute(MADD(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                          MR1, MW3, 0b00000, 0b01000, false, false, false));
    assert(read_mapword(2, 3) == 0x0000001E, "ADD: 10 + 20 = 30")
}

val test_add_flags : unit -> unit
function test_add_flags() = {
    map_init();
    write_mapword(0, 3, 0x7FFFFFFF);
    write_mapword(1, 3, 0x00000001);
    // ADD.F R2.W3, R0.W3[0:32], R1.W3[0:32]
    let _ = mexecute(MADD(MR2, MW3, MR0, MW3, 0b00000, 0b100000 : bits(5),
                          MR1, MW3, 0b00000, 0b100000 : bits(5), true, false, false));
    // 0x7FFFFFFF + 1 = 0x80000000
    assert(read_mapword(2, 3) == 0x80000000, "ADD.F: result");
    assert(mflag_z == false, "ADD.F: not zero");
    assert(mflag_n == true, "ADD.F: negative (bit 31 set)");
    assert(mflag_v == true, "ADD.F: signed overflow")
}

val test_add_zero_flag : unit -> unit
function test_add_zero_flag() = {
    map_init();
    write_mapword(0, 3, 0x00000000);
    write_mapword(1, 3, 0x00000000);
    // ADD.F R2.W3, R0.W3[0:8], R1.W3[0:8]
    let _ = mexecute(MADD(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                          MR1, MW3, 0b00000, 0b01000, true, false, false));
    assert(mflag_z == true, "ADD.F: zero flag set when result is 0")
}

val test_add_short : unit -> unit
function test_add_short() = {
    map_init();
    write_mapword(0, 3, 0xFFFF00FF);  // upper 16 bits should be preserved
    write_mapword(1, 3, 0x00000001);
    // ADD.SH R0.W3, R0.W3[0:16], R1.W3[0:16]
    let _ = mexecute(MADD(MR0, MW3, MR0, MW3, 0b00000, 0b10000,
                          MR1, MW3, 0b00000, 0b10000, false, false, true));
    assert(read_mapword(0, 3) == 0xFFFF0100, "ADD.SH: only low 16 bits modified")
}

val test_addi_basic : unit -> unit
function test_addi_basic() = {
    map_init();
    write_mapword(0, 3, 0x0000000A);
    // ADDI R1.W3, R0.W3[0:8], 5
    let _ = mexecute(MADDI(MR1, MW3, MR0, MW3, 0b00000, 0b01000,
                           0x0005, false, false, false));
    assert(read_mapword(1, 3) == 0x0000000F, "ADDI: 10 + 5 = 15")
}

val test_addi_flags : unit -> unit
function test_addi_flags() = {
    map_init();
    write_mapword(0, 3, 0x000000FF);
    // ADDI.F R1.W3, R0.W3[0:8], 1
    let _ = mexecute(MADDI(MR1, MW3, MR0, MW3, 0b00000, 0b01000,
                           0x0001, true, false, false));
    assert(read_mapword(1, 3) == 0x00000100, "ADDI.F: 255 + 1 = 256")
}

val main : unit -> unit
function main() = {
    test_add_basic();
    test_add_flags();
    test_add_zero_flag();
    test_add_short();
    test_addi_basic();
    test_addi_flags()
}
```

- [ ] **Step 4: Register test in CMakeLists.txt**

Add: `add_sail_test(test_map_add test/map/test_add.sail)`

- [ ] **Step 5: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_map --output-on-failure`
Expected: All MAP tests PASS

- [ ] **Step 6: Commit**

```bash
git add model/map/insts.sail test/map/test_add.sail test/CMakeLists.txt
git commit -m "Add MAP ADD/ADDI with arithmetic helpers, .F/.SX/.SH modifiers"
```

---

### Task 6: SUB/SUBI, CMP/CMPI

**Files:**
- Modify: `model/map/insts.sail`
- Create: `test/map/test_sub.sail`
- Create: `test/map/test_cmp.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Add SUB, SUBI, CMP, CMPI execute clauses to insts.sail**

```sail
// SUB: Dest[N:0] = Source1[i1:j1] - Source2[i2:j2]
function clause mexecute(MSUB(rd, rw, rs1, sw1, s1off, s1sz, rs2, sw2, s2off, s2sz,
                              set_flags, sign_extend, short_mode)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let w2 = read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2));
    let op1 : bits(32) = if sign_extend then map_extract_sx(w1, unsigned(s1off), unsigned(s1sz))
                          else map_extract(w1, unsigned(s1off), unsigned(s1sz));
    let op2 : bits(32) = if sign_extend then map_extract_sx(w2, unsigned(s2off), unsigned(s2sz))
                          else map_extract(w2, unsigned(s2off), unsigned(s2sz));
    let mask : bits(32) = if short_mode then 0x0000FFFF else 0xFFFFFFFF;
    let result : bits(32) = sub_bits(op1, op2) & mask;
    if set_flags then map_set_flags_sub(op1, op2, result, short_mode);
    map_write_result(rd_idx, rw_idx, result, short_mode);
    RETIRE_SUCCESS
}

// SUBI: Dest[N:0] = Source1[i1:j1] - ImmediateValue
function clause mexecute(MSUBI(rd, rw, rs1, sw1, s1off, s1sz, imm16,
                               set_flags, sign_extend, short_mode)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let op1 : bits(32) = if sign_extend then map_extract_sx(w1, unsigned(s1off), unsigned(s1sz))
                          else map_extract(w1, unsigned(s1off), unsigned(s1sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let mask : bits(32) = if short_mode then 0x0000FFFF else 0xFFFFFFFF;
    let result : bits(32) = sub_bits(op1, op2) & mask;
    if set_flags then map_set_flags_sub(op1, op2, result, short_mode);
    map_write_result(rd_idx, rw_idx, result, short_mode);
    RETIRE_SUCCESS
}

// CMP: Compare. Always sets Z and C flags. Result discarded.
function clause mexecute(MCMP(rs1, sw1, s1off, rs2, sw2, s2off, sz)) = {
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let w2 = read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2));
    let op1 = map_extract(w1, unsigned(s1off), unsigned(sz));
    let op2 = map_extract(w2, unsigned(s2off), unsigned(sz));
    let result : bits(32) = sub_bits(op1, op2);
    mflag_z = result == 0x00000000;
    mflag_c = sail_zero_extend(op1, 64) < sail_zero_extend(op2, 64);
    RETIRE_SUCCESS
}

// CMPI: Compare with immediate. Always sets Z and C flags.
function clause mexecute(MCMPI(rs1, sw1, s1off, imm16, sz)) = {
    let w1 = read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1));
    let op1 = map_extract(w1, unsigned(s1off), unsigned(sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let result : bits(32) = sub_bits(op1, op2);
    mflag_z = result == 0x00000000;
    mflag_c = sail_zero_extend(op1, 64) < sail_zero_extend(op2, 64);
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Create test_sub.sail**

```sail
// Tests for MAP SUB and SUBI instructions.

val test_sub_basic : unit -> unit
function test_sub_basic() = {
    map_init();
    write_mapword(0, 3, 0x00000014);
    write_mapword(1, 3, 0x0000000A);
    let _ = mexecute(MSUB(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                          MR1, MW3, 0b00000, 0b01000, false, false, false));
    assert(read_mapword(2, 3) == 0x0000000A, "SUB: 20 - 10 = 10")
}

val test_sub_flags_borrow : unit -> unit
function test_sub_flags_borrow() = {
    map_init();
    write_mapword(0, 3, 0x00000003);
    write_mapword(1, 3, 0x00000005);
    let _ = mexecute(MSUB(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                          MR1, MW3, 0b00000, 0b01000, true, false, false));
    assert(mflag_c == true, "SUB.F: borrow when A < B");
    assert(mflag_n == true, "SUB.F: negative result")
}

val test_subi_basic : unit -> unit
function test_subi_basic() = {
    map_init();
    write_mapword(0, 3, 0x0000000F);
    let _ = mexecute(MSUBI(MR1, MW3, MR0, MW3, 0b00000, 0b01000,
                           0x0005, false, false, false));
    assert(read_mapword(1, 3) == 0x0000000A, "SUBI: 15 - 5 = 10")
}

val main : unit -> unit
function main() = {
    test_sub_basic();
    test_sub_flags_borrow();
    test_subi_basic()
}
```

- [ ] **Step 3: Create test_cmp.sail**

```sail
// Tests for MAP CMP and CMPI instructions.

val test_cmp_equal : unit -> unit
function test_cmp_equal() = {
    map_init();
    write_mapword(0, 3, 0x0000000A);
    write_mapword(1, 3, 0x0000000A);
    let _ = mexecute(MCMP(MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000));
    assert(mflag_z == true, "CMP: equal sets Z");
    assert(mflag_c == false, "CMP: equal no borrow")
}

val test_cmp_less : unit -> unit
function test_cmp_less() = {
    map_init();
    write_mapword(0, 3, 0x00000003);
    write_mapword(1, 3, 0x0000000A);
    let _ = mexecute(MCMP(MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000));
    assert(mflag_z == false, "CMP: not equal");
    assert(mflag_c == true, "CMP: borrow when src1 < src2")
}

val test_cmpi_basic : unit -> unit
function test_cmpi_basic() = {
    map_init();
    write_mapword(0, 3, 0x00000042);
    let _ = mexecute(MCMPI(MR0, MW3, 0b00000, 0x0042, 0b01000));
    assert(mflag_z == true, "CMPI: equal sets Z")
}

val main : unit -> unit
function main() = {
    test_cmp_equal();
    test_cmp_less();
    test_cmpi_basic()
}
```

- [ ] **Step 4: Register tests in CMakeLists.txt**

Add:
```cmake
add_sail_test(test_map_sub test/map/test_sub.sail)
add_sail_test(test_map_cmp test/map/test_cmp.sail)
```

- [ ] **Step 5: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_map --output-on-failure`
Expected: All MAP tests PASS

- [ ] **Step 6: Commit**

```bash
git add model/map/insts.sail test/map/test_sub.sail test/map/test_cmp.sail test/CMakeLists.txt
git commit -m "Add MAP SUB/SUBI, CMP/CMPI with tests"
```

---

### Task 7: Logic instructions — AND, OR, XOR, NOT

**Files:**
- Modify: `model/map/insts.sail`
- Create: `test/map/test_logic.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Add AND, ANDI, OR, ORI, XOR, XORI, NOT execute clauses**

Append to `model/map/insts.sail`:

```sail
// AND: Dest[Size-1:0] = Src1[i1:j1] & Src2[i2:j2]
function clause mexecute(MAND(rd, rw, rs1, sw1, s1off, rs2, sw2, s2off, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 = map_extract(read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2)), unsigned(s2off), unsigned(sz));
    let result : bits(32) = op1 & op2;
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// ANDI: Dest[Size-1:0] = Src1[i1:j1] & ImmediateValue
function clause mexecute(MANDI(rd, rw, rs1, sw1, s1off, imm16, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let result : bits(32) = op1 & op2;
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// OR: Dest[Size-1:0] = Src1[i1:j1] | Src2[i2:j2]
function clause mexecute(MOR(rd, rw, rs1, sw1, s1off, rs2, sw2, s2off, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 = map_extract(read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2)), unsigned(s2off), unsigned(sz));
    let result : bits(32) = op1 | op2;
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// ORI: Dest[Size-1:0] = Src1[i1:j1] | ImmediateValue
function clause mexecute(MORI(rd, rw, rs1, sw1, s1off, imm16, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let result : bits(32) = op1 | op2;
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// XOR: Dest[Size-1:0] = Src1[i1:j1] ^ Src2[i2:j2]
function clause mexecute(MXOR(rd, rw, rs1, sw1, s1off, rs2, sw2, s2off, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 = map_extract(read_mapword(mregidx_to_nat(rs2), mwordsel_to_nat(sw2)), unsigned(s2off), unsigned(sz));
    let result : bits(32) = xor_vec(op1, op2);
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// XORI: Dest[Size-1:0] = Src1[i1:j1] ^ ImmediateValue
function clause mexecute(MXORI(rd, rw, rs1, sw1, s1off, imm16, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs1), mwordsel_to_nat(sw1)), unsigned(s1off), unsigned(sz));
    let op2 : bits(32) = sail_zero_extend(imm16, 32);
    let result : bits(32) = xor_vec(op1, op2);
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// NOT: Dest[Size-1:0] = ~Src[i:j]
function clause mexecute(MNOT(rd, rw, rs, sw, soff, sz, set_flags)) = {
    let rd_idx = mregidx_to_nat(rd);
    let rw_idx = mwordsel_to_nat(rw);
    let op1 = map_extract(read_mapword(mregidx_to_nat(rs), mwordsel_to_nat(sw)), unsigned(soff), unsigned(sz));
    let result : bits(32) = not_vec(op1) & sail_mask(32, sail_ones(unsigned(sz)));
    if set_flags then map_set_flags_logic(result);
    let existing = read_mapword(rd_idx, rw_idx);
    let mask : bits(32) = sail_mask(32, sail_ones(unsigned(sz)));
    write_mapword(rd_idx, rw_idx, (existing & not_vec(mask)) | result);
    RETIRE_SUCCESS
}

// Close the scattered function
end mexecute
```

- [ ] **Step 2: Create test_logic.sail**

```sail
// Tests for MAP logic instructions: AND, OR, XOR, NOT.

val test_and_basic : unit -> unit
function test_and_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000FF);
    write_mapword(1, 3, 0x0000000F);
    let _ = mexecute(MAND(MR2, MW3, MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000, false));
    assert(read_mapword(2, 3) == 0x0000000F, "AND: 0xFF & 0x0F = 0x0F")
}

val test_and_flags : unit -> unit
function test_and_flags() = {
    map_init();
    write_mapword(0, 3, 0x000000FF);
    write_mapword(1, 3, 0x00000000);
    let _ = mexecute(MAND(MR2, MW3, MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000, true));
    assert(mflag_z == true, "AND.F: zero result sets Z");
    assert(mflag_c == false, "AND.F: C cleared");
    assert(mflag_v == false, "AND.F: V cleared")
}

val test_or_basic : unit -> unit
function test_or_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000A0);
    write_mapword(1, 3, 0x0000000B);
    let _ = mexecute(MOR(MR2, MW3, MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000, false));
    assert(read_mapword(2, 3) == 0x000000AB, "OR: 0xA0 | 0x0B = 0xAB")
}

val test_xor_basic : unit -> unit
function test_xor_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000FF);
    write_mapword(1, 3, 0x0000000F);
    let _ = mexecute(MXOR(MR2, MW3, MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000, false));
    assert(read_mapword(2, 3) == 0x000000F0, "XOR: 0xFF ^ 0x0F = 0xF0")
}

val test_not_basic : unit -> unit
function test_not_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000F0);
    let _ = mexecute(MNOT(MR1, MW3, MR0, MW3, 0b00000, 0b01000, false));
    assert(read_mapword(1, 3) == 0x0000000F, "NOT: ~0xF0 (8-bit) = 0x0F")
}

val test_andi_basic : unit -> unit
function test_andi_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000AB);
    let _ = mexecute(MANDI(MR1, MW3, MR0, MW3, 0b00000, 0x000F, 0b01000, false));
    assert(read_mapword(1, 3) == 0x0000000B, "ANDI: 0xAB & 0x0F = 0x0B")
}

val test_ori_basic : unit -> unit
function test_ori_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000A0);
    let _ = mexecute(MORI(MR1, MW3, MR0, MW3, 0b00000, 0x000B, 0b01000, false));
    assert(read_mapword(1, 3) == 0x000000AB, "ORI: 0xA0 | 0x0B = 0xAB")
}

val test_xori_basic : unit -> unit
function test_xori_basic() = {
    map_init();
    write_mapword(0, 3, 0x000000FF);
    let _ = mexecute(MXORI(MR1, MW3, MR0, MW3, 0b00000, 0x00FF, 0b01000, false));
    assert(read_mapword(1, 3) == 0x00000000, "XORI: 0xFF ^ 0xFF = 0")
}

val main : unit -> unit
function main() = {
    test_and_basic();
    test_and_flags();
    test_or_basic();
    test_xor_basic();
    test_not_basic();
    test_andi_basic();
    test_ori_basic();
    test_xori_basic()
}
```

- [ ] **Step 3: Register test in CMakeLists.txt**

Add: `add_sail_test(test_map_logic test/map/test_logic.sail)`

- [ ] **Step 4: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_map --output-on-failure`
Expected: All MAP tests PASS

- [ ] **Step 5: Commit**

```bash
git add model/map/insts.sail test/map/test_logic.sail test/CMakeLists.txt
git commit -m "Add MAP logic instructions: AND, OR, XOR, NOT with .F modifier"
```

---

### Task 8: Branch instructions — BR, BRI, BRBTST

**Files:**
- Modify: `model/map/insts.sail`
- Create: `test/map/test_br.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Add condition evaluation and branch execute clauses**

Add before `end mexecute` in `model/map/insts.sail`:

```sail
// Evaluate a MAP branch condition.
val eval_mcond : mcond -> bool
function eval_mcond(cc) = match cc {
    MCC_EQ  => mflag_z,
    MCC_NEQ => not_bool(mflag_z),
    MCC_LT  => mflag_n,
    MCC_GT  => not_bool(mflag_n) & not_bool(mflag_z),
    MCC_GE  => not_bool(mflag_n),
    MCC_LE  => mflag_n | mflag_z,
    MCC_C   => mflag_c,
    MCC_NC  => not_bool(mflag_c),
    MCC_V   => mflag_v,
    MCC_NV  => not_bool(mflag_v),
    MCC_AL  => true,
}

// BR: Branch to absolute address in register if condition met.
function clause mexecute(MBR(cc, rs, sw)) = {
    if eval_mcond(cc) then {
        let target = read_mapword(mregidx_to_nat(rs), mwordsel_to_nat(sw));
        mpc = sail_mask(16, target)
    };
    RETIRE_SUCCESS
}

// BRI: Branch to PC-relative offset if condition met.
function clause mexecute(MBRI(cc, offset)) = {
    if eval_mcond(cc) then {
        // mpc was already incremented by map_step, so offset is relative to next instruction.
        // But when using direct mexecute(), mpc is wherever it was.
        mpc = mpc + offset
    };
    RETIRE_SUCCESS
}

// BRBTST: Test bit in register word and branch.
function clause mexecute(MBRBTST(btcc, rs, sw, bit_offset, target)) = {
    let word = read_mapword(mregidx_to_nat(rs), mwordsel_to_nat(sw));
    let bit_val = (sail_shiftright(word, unsigned(bit_offset)) & 0x00000001) == 0x00000001;
    let take_branch : bool = match btcc {
        MBT_CLR => not_bool(bit_val),
        MBT_SET => bit_val,
    };
    if take_branch then mpc = target;
    RETIRE_SUCCESS
}
```

- [ ] **Step 2: Create test_br.sail**

```sail
// Tests for MAP branch instructions.

val test_br_unconditional : unit -> unit
function test_br_unconditional() = {
    map_init();
    write_mapword(0, 3, 0x00000042);
    let _ = mexecute(MBR(MCC_AL, MR0, MW3));
    assert(mpc == 0x0042, "BR AL: should jump to R0.W3 value")
}

val test_br_eq_taken : unit -> unit
function test_br_eq_taken() = {
    map_init();
    mflag_z = true;
    write_mapword(0, 3, 0x00000010);
    let _ = mexecute(MBR(MCC_EQ, MR0, MW3));
    assert(mpc == 0x0010, "BR EQ: should branch when Z=1")
}

val test_br_eq_not_taken : unit -> unit
function test_br_eq_not_taken() = {
    map_init();
    mflag_z = false;
    write_mapword(0, 3, 0x00000010);
    let _ = mexecute(MBR(MCC_EQ, MR0, MW3));
    assert(mpc == 0x0000, "BR EQ: should not branch when Z=0")
}

val test_bri_relative : unit -> unit
function test_bri_relative() = {
    map_init();
    mpc = 0x0010;
    let _ = mexecute(MBRI(MCC_AL, 0x0005));
    assert(mpc == 0x0015, "BRI: should add offset to PC")
}

val test_br_gt : unit -> unit
function test_br_gt() = {
    map_init();
    mflag_n = false;
    mflag_z = false;
    write_mapword(0, 3, 0x00000020);
    let _ = mexecute(MBR(MCC_GT, MR0, MW3));
    assert(mpc == 0x0020, "BR GT: should branch when N=0 and Z=0")
}

val test_brbtst_set : unit -> unit
function test_brbtst_set() = {
    map_init();
    write_mapword(0, 3, 0x00000008);  // bit 3 is set
    let _ = mexecute(MBRBTST(MBT_SET, MR0, MW3, 0b00011, 0x0042));
    assert(mpc == 0x0042, "BRBTST SET: should branch when bit 3 is set")
}

val test_brbtst_clr : unit -> unit
function test_brbtst_clr() = {
    map_init();
    write_mapword(0, 3, 0x00000008);  // bit 3 is set, bit 0 is clear
    let _ = mexecute(MBRBTST(MBT_CLR, MR0, MW3, 0b00000, 0x0042));
    assert(mpc == 0x0042, "BRBTST CLR: should branch when bit 0 is clear")
}

val main : unit -> unit
function main() = {
    test_br_unconditional();
    test_br_eq_taken();
    test_br_eq_not_taken();
    test_bri_relative();
    test_br_gt();
    test_brbtst_set();
    test_brbtst_clr()
}
```

- [ ] **Step 3: Register test in CMakeLists.txt**

Add: `add_sail_test(test_map_br test/map/test_br.sail)`

- [ ] **Step 4: Build and run tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build -R test_map --output-on-failure`
Expected: All MAP tests PASS

- [ ] **Step 5: Commit**

```bash
git add model/map/insts.sail test/map/test_br.sail test/CMakeLists.txt
git commit -m "Add MAP branch instructions: BR, BRI, BRBTST with all condition codes"
```

---

### Task 9: Binary encoding

**Files:**
- Create: `model/map/decode.sail`
- Create: `test/map/test_encoding.sail`
- Modify: `model/main.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create decode.sail with sub-mappings and all instruction encodings**

Create `model/map/decode.sail` with sub-mappings for `mregidx`, `mwordsel`, `mcond`, `mbtcond`, `bool`, and all 20 instruction encoding mappings. Follow the same pattern as `model/parser/decode.sail`:
- 6-bit opcode at [63:58]
- Fields packed MSB-first
- Zero-padded at LSB
- Use scattered mapping `mencdec : minstr <-> bits(64)`

The sub-mappings:

```sail
// MAP instruction encoding/decoding.
// 64-bit fixed-width instruction word.

mapping encdec_mregidx : mregidx <-> bits(4) = {
    MR0  <-> 0x0, MR1  <-> 0x1, MR2  <-> 0x2, MR3  <-> 0x3,
    MR4  <-> 0x4, MR5  <-> 0x5, MR6  <-> 0x6, MR7  <-> 0x7,
    MR8  <-> 0x8, MR9  <-> 0x9, MR10 <-> 0xA, MR11 <-> 0xB,
    MR12 <-> 0xC, MR13 <-> 0xD, MR14 <-> 0xE, MRN  <-> 0xF,
}

mapping encdec_mwordsel : mwordsel <-> bits(2) = {
    MW0 <-> 0b00, MW1 <-> 0b01, MW2 <-> 0b10, MW3 <-> 0b11,
}

mapping encdec_mcond : mcond <-> bits(4) = {
    MCC_EQ  <-> 0x0, MCC_NEQ <-> 0x1, MCC_LT  <-> 0x2, MCC_GT  <-> 0x3,
    MCC_GE  <-> 0x4, MCC_LE  <-> 0x5, MCC_C   <-> 0x6, MCC_NC  <-> 0x7,
    MCC_V   <-> 0x8, MCC_NV  <-> 0x9, MCC_AL  <-> 0xA,
}

mapping encdec_mbtcond : mbtcond <-> bits(1) = {
    MBT_CLR <-> 0b0, MBT_SET <-> 0b1,
}

mapping encdec_bool : bool <-> bits(1) = {
    false <-> 0b0, true <-> 0b1,
}
```

Then define the main scattered mapping with all 20 opcodes. Exact bit layouts to be worked out during implementation, following the field-bit counts from the design spec.

Add `encode_minstr` and `decode_minstr` functions (same pattern as parser).

- [ ] **Step 2: Add include to main.sail**

Add `$include "map/decode.sail"` after `$include "map/types.sail"` and before `$include "map/state.sail"` in `model/main.sail`.

- [ ] **Step 3: Create test_encoding.sail with round-trip tests**

Test representative instructions: NOP, HALT, MOV, ADD, CMP, AND, BR, BRBTST.

```sail
// Tests for MAP binary instruction encoding/decoding round-trips.

val test_roundtrip_nop : unit -> unit
function test_roundtrip_nop() = {
    let instr = MNOP();
    let encoded = encode_minstr(instr);
    assert(encoded == 0x0000000000000000, "NOP should encode to all zeros");
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "NOP round-trip should be identity")
}

val test_roundtrip_halt : unit -> unit
function test_roundtrip_halt() = {
    let instr = MHALT();
    let encoded = encode_minstr(instr);
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "HALT round-trip should be identity")
}

val test_roundtrip_mov : unit -> unit
function test_roundtrip_mov() = {
    let instr = MMOV(MR1, MW3, MR0, MW3, true);
    let encoded = encode_minstr(instr);
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "MOV round-trip should be identity")
}

val test_roundtrip_add : unit -> unit
function test_roundtrip_add() = {
    let instr = MADD(MR2, MW3, MR0, MW3, 0b00000, 0b01000,
                     MR1, MW3, 0b00000, 0b01000, true, false, false);
    let encoded = encode_minstr(instr);
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "ADD round-trip should be identity")
}

val test_roundtrip_br : unit -> unit
function test_roundtrip_br() = {
    let instr = MBR(MCC_AL, MR0, MW3);
    let encoded = encode_minstr(instr);
    let decoded = decode_minstr(encoded);
    let re_encoded = encode_minstr(decoded);
    assert(re_encoded == encoded, "BR round-trip should be identity")
}

val main : unit -> unit
function main() = {
    test_roundtrip_nop();
    test_roundtrip_halt();
    test_roundtrip_mov();
    test_roundtrip_add();
    test_roundtrip_br()
}
```

- [ ] **Step 4: Register test in CMakeLists.txt**

Add: `add_sail_test(test_map_encoding test/map/test_encoding.sail)`

- [ ] **Step 5: Build and run all tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --output-on-failure`
Expected: All tests PASS (both parser and MAP)

- [ ] **Step 6: Commit**

```bash
git add model/map/decode.sail model/main.sail test/map/test_encoding.sail test/CMakeLists.txt
git commit -m "Add MAP 64-bit binary encoding with round-trip tests"
```

---

### Task 10: Program-level tests using map_run

**Files:**
- Create: `test/map/test_program.sail`
- Modify: `test/CMakeLists.txt`

- [ ] **Step 1: Create test_program.sail**

```sail
// Multi-instruction MAP program tests using map_run.

val test_simple_program : unit -> unit
function test_simple_program() = {
    map_init();
    // Program: MOVI R0.W3, 0x42; HALT
    map_load_program([|encode_minstr(MMOVI(MR0, MW3, 0x00000042, false)),
                       encode_minstr(MHALT())|]);
    let result = map_run();
    assert(result == RETIRE_HALT, "Program should halt");
    assert(read_mapword(0, 3) == 0x00000042, "R0.W3 should be 0x42")
}

val test_add_program : unit -> unit
function test_add_program() = {
    map_init();
    // Program: MOVI R0.W3, 10; MOVI R1.W3, 20; ADD R2.W3, R0.W3, R1.W3; HALT
    map_load_program([|
        encode_minstr(MMOVI(MR0, MW3, 0x0000000A, false)),
        encode_minstr(MMOVI(MR1, MW3, 0x00000014, false)),
        encode_minstr(MADD(MR2, MW3, MR0, MW3, 0b00000, 0b100000 : bits(5),
                           MR1, MW3, 0b00000, 0b100000 : bits(5), false, false, false)),
        encode_minstr(MHALT())
    |]);
    let result = map_run();
    assert(result == RETIRE_HALT, "Program should halt");
    assert(read_mapword(2, 3) == 0x0000001E, "10 + 20 = 30")
}

val test_branch_program : unit -> unit
function test_branch_program() = {
    map_init();
    // Program:
    //   0: MOVI R0.W3, 5
    //   1: MOVI R1.W3, 5
    //   2: CMP R0.W3, R1.W3 (8-bit)
    //   3: BRI EQ, +2 (skip to 6)
    //   4: MOVI R2.W3, 0xBB  (skipped)
    //   5: HALT              (skipped)
    //   6: MOVI R2.W3, 0xAA
    //   7: HALT
    map_load_program([|
        encode_minstr(MMOVI(MR0, MW3, 0x00000005, false)),
        encode_minstr(MMOVI(MR1, MW3, 0x00000005, false)),
        encode_minstr(MCMP(MR0, MW3, 0b00000, MR1, MW3, 0b00000, 0b01000)),
        encode_minstr(MBRI(MCC_EQ, 0x0002)),
        encode_minstr(MMOVI(MR2, MW3, 0x000000BB, false)),
        encode_minstr(MHALT()),
        encode_minstr(MMOVI(MR2, MW3, 0x000000AA, false)),
        encode_minstr(MHALT())
    |]);
    let result = map_run();
    assert(result == RETIRE_HALT, "Program should halt");
    assert(read_mapword(2, 3) == 0x000000AA, "Branch should skip to MOVI 0xAA")
}

val main : unit -> unit
function main() = {
    test_simple_program();
    test_add_program();
    test_branch_program()
}
```

- [ ] **Step 2: Register test in CMakeLists.txt**

Add: `add_sail_test(test_map_program test/map/test_program.sail)`

- [ ] **Step 3: Build and run all tests**

Run: `./dev.sh cmake --build build && ./dev.sh ctest --test-dir build --output-on-failure`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add test/map/test_program.sail test/CMakeLists.txt
git commit -m "Add MAP program-level tests using map_run"
```

---

### Task 11: Update documentation

**Files:**
- Modify: `docs/spec-coverage.md`

- [ ] **Step 1: Add MAP ISA coverage table**

Replace the "Not yet started" line in the MAP ISA section with a coverage table:

```markdown
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
| 4.13.9 | SHL, SHLI, SHR, SHRI | Not started | |
| 4.13.10 | CONCAT | Not started | |
| 4.13.11 | MOV, MOVI | Done | .CD supported |
| 4.13.12 | FFI | Not started | |
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/spec-coverage.md
git commit -m "Update spec coverage: add MAP ISA table with foundation instructions"
```
