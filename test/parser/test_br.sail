// Tests for BR (branch) instruction with all condition codes.

val test_br_unconditional : unit -> unit
function test_br_unconditional() = {
    parser_init();
    assert(ppc == 0x0000, "PC starts at 0");

    let _ = pexecute(PBR(PCC_AL, 0x0042));

    assert(ppc == 0x0042, "BR unconditional should set PC")
}

val test_br_eq_taken : unit -> unit
function test_br_eq_taken() = {
    parser_init();
    pflag_z = true;

    let _ = pexecute(PBR(PCC_EQ, 0x0100));

    assert(ppc == 0x0100, "BREQ with Z=1 should branch")
}

val test_br_eq_not_taken : unit -> unit
function test_br_eq_not_taken() = {
    parser_init();
    pflag_z = false;

    let _ = pexecute(PBR(PCC_EQ, 0x0100));

    assert(ppc == 0x0000, "BREQ with Z=0 should not branch")
}

val test_br_neq_taken : unit -> unit
function test_br_neq_taken() = {
    parser_init();
    pflag_z = false;

    let _ = pexecute(PBR(PCC_NEQ, 0x0200));

    assert(ppc == 0x0200, "BRNEQ with Z=0 should branch")
}

val test_br_neq_not_taken : unit -> unit
function test_br_neq_not_taken() = {
    parser_init();
    pflag_z = true;

    let _ = pexecute(PBR(PCC_NEQ, 0x0200));

    assert(ppc == 0x0000, "BRNEQ with Z=1 should not branch")
}

val test_br_lt_taken : unit -> unit
function test_br_lt_taken() = {
    parser_init();
    pflag_n = true;

    let _ = pexecute(PBR(PCC_LT, 0x0300));

    assert(ppc == 0x0300, "BRLT with N=1 should branch")
}

val test_br_lt_not_taken : unit -> unit
function test_br_lt_not_taken() = {
    parser_init();
    pflag_n = false;

    let _ = pexecute(PBR(PCC_LT, 0x0300));

    assert(ppc == 0x0000, "BRLT with N=0 should not branch")
}

val test_br_gt_taken : unit -> unit
function test_br_gt_taken() = {
    parser_init();
    pflag_n = false;
    pflag_z = false;

    let _ = pexecute(PBR(PCC_GT, 0x0400));

    assert(ppc == 0x0400, "BRGT with N=0,Z=0 should branch")
}

val test_br_gt_not_taken_z : unit -> unit
function test_br_gt_not_taken_z() = {
    parser_init();
    pflag_n = false;
    pflag_z = true;

    let _ = pexecute(PBR(PCC_GT, 0x0400));

    assert(ppc == 0x0000, "BRGT with Z=1 should not branch")
}

val test_br_gt_not_taken_n : unit -> unit
function test_br_gt_not_taken_n() = {
    parser_init();
    pflag_n = true;
    pflag_z = false;

    let _ = pexecute(PBR(PCC_GT, 0x0400));

    assert(ppc == 0x0000, "BRGT with N=1 should not branch")
}

val test_br_ge_taken : unit -> unit
function test_br_ge_taken() = {
    parser_init();
    pflag_n = false;

    let _ = pexecute(PBR(PCC_GE, 0x0500));

    assert(ppc == 0x0500, "BRGE with N=0 should branch")
}

val test_br_le_taken_z : unit -> unit
function test_br_le_taken_z() = {
    parser_init();
    pflag_z = true;
    pflag_n = false;

    let _ = pexecute(PBR(PCC_LE, 0x0600));

    assert(ppc == 0x0600, "BRLE with Z=1 should branch")
}

val test_br_le_taken_n : unit -> unit
function test_br_le_taken_n() = {
    parser_init();
    pflag_n = true;
    pflag_z = false;

    let _ = pexecute(PBR(PCC_LE, 0x0600));

    assert(ppc == 0x0600, "BRLE with N=1 should branch")
}

val test_br_le_not_taken : unit -> unit
function test_br_le_not_taken() = {
    parser_init();
    pflag_n = false;
    pflag_z = false;

    let _ = pexecute(PBR(PCC_LE, 0x0600));

    assert(ppc == 0x0000, "BRLE with N=0,Z=0 should not branch")
}

val main : unit -> unit
function main() = {
    test_br_unconditional();
    test_br_eq_taken();
    test_br_eq_not_taken();
    test_br_neq_taken();
    test_br_neq_not_taken();
    test_br_lt_taken();
    test_br_lt_not_taken();
    test_br_gt_taken();
    test_br_gt_not_taken_z();
    test_br_gt_not_taken_n();
    test_br_ge_taken();
    test_br_le_taken_z();
    test_br_le_taken_n();
    test_br_le_not_taken()
}
