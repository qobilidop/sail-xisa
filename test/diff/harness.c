#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gmp.h>
#include "sail.h"
#include "rts.h"

// Forward declarations from Sail-generated code.
void model_init(void);
void model_fini(void);

// Sail-generated functions.
extern unit zparser_init(unit);
extern unit zwrite_pimem_raw(sail_int, uint64_t);
extern enum zExecutionResult zparser_run(unit);

// Sail-generated register globals.
extern zz5vecz8z5bvz9 zPR;
extern uint64_t zppc;
extern uint64_t zpcursor;
extern bool zpflag_zz;
extern bool zpflag_n;
extern bool zparser_halted;
extern bool zparser_drop;
extern lbits zstruct0;
extern zz5vecz8z5boolz9 zhdr_present;
extern zz5vecz8z5bv8z9 zhdr_offset;
extern zz5vecz8z5bv8z9 zpacket_hdr;

// Print a 128-bit lbits value as a 0x-prefixed 32-digit hex string.
static void print_lbits_hex(FILE *f, const lbits *val) {
    char *str = mpz_get_str(NULL, 16, *val->bits);
    size_t len = strlen(str);
    fprintf(f, "\"0x");
    for (size_t i = len; i < 32; i++) fprintf(f, "0");
    fprintf(f, "%s\"", str);
    free(str);
}

// Dump parser-observable state as JSON to stdout.
static void dump_state(void) {
    printf("{\n");

    printf("  \"pc\": %lu,\n", (unsigned long)zppc);

    printf("  \"regs\": [\n");
    for (int i = 0; i < 4; i++) {
        printf("    ");
        print_lbits_hex(stdout, &zPR.data[i]);
        printf("%s\n", i < 3 ? "," : "");
    }
    printf("  ],\n");

    printf("  \"flag_z\": %s,\n", zpflag_zz ? "true" : "false");
    printf("  \"flag_n\": %s,\n", zpflag_n ? "true" : "false");

    printf("  \"cursor\": %lu,\n", (unsigned long)zpcursor);

    printf("  \"halted\": %s,\n", zparser_halted ? "true" : "false");
    printf("  \"dropped\": %s,\n", zparser_drop ? "true" : "false");

    printf("  \"struct0\": ");
    print_lbits_hex(stdout, &zstruct0);
    printf(",\n");

    printf("  \"hdr_present\": [");
    for (int i = 0; i < 32; i++) {
        printf("%s%s", zhdr_present.data[i] ? "true" : "false", i < 31 ? ", " : "");
    }
    printf("],\n");

    printf("  \"hdr_offset\": [");
    for (int i = 0; i < 32; i++) {
        printf("%lu%s", (unsigned long)zhdr_offset.data[i], i < 31 ? ", " : "");
    }
    printf("]\n");

    printf("}\n");
}

// Usage: sail-c-emu-harness <program.bin> [packet.bin]
int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: sail-c-emu-harness <program.bin> [packet.bin]\n");
        return 1;
    }

    model_init();
    zparser_init(UNIT);

    // Load program binary.
    FILE *prog = fopen(argv[1], "rb");
    if (!prog) {
        fprintf(stderr, "Error: cannot open %s\n", argv[1]);
        model_fini();
        return 1;
    }

    uint8_t buf[8];
    sail_int idx;
    CREATE(sail_int)(&idx);
    int pc = 0;
    while (fread(buf, 1, 8, prog) == 8) {
        uint64_t word = 0;
        for (int i = 0; i < 8; i++) {
            word = (word << 8) | buf[i];
        }
        mpz_set_si(*idx, pc);
        zwrite_pimem_raw(idx, word);
        pc++;
    }
    fclose(prog);
    KILL(sail_int)(&idx);

    // Load packet data (optional).
    if (argc >= 3) {
        FILE *pkt = fopen(argv[2], "rb");
        if (!pkt) {
            fprintf(stderr, "Error: cannot open %s\n", argv[2]);
            model_fini();
            return 1;
        }
        uint8_t pkt_buf[256];
        memset(pkt_buf, 0, 256);
        size_t n = fread(pkt_buf, 1, 256, pkt);
        fclose(pkt);
        (void)n;

        for (int i = 0; i < 256; i++) {
            zpacket_hdr.data[i] = pkt_buf[i];
        }
    }

    // Run the parser.
    zparser_run(UNIT);

    dump_state();

    model_fini();
    return 0;
}
