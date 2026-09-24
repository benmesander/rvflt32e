/* tests/gen.c - Host-side reference vector generator for rvflt32e.
 *
 * Runs on the build machine and uses native IEEE-754 single precision as the
 * reference, emitting a vectors.h consumed by tests/spike_main.c.
 *
 * usage: gen <output-path> [random-cases-per-op]
 *
 * This file is part of rvflt32e and is distributed under the same terms; see
 * LICENSE.txt and LICENSE-EXCEPTION.txt.
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

typedef union { float f; uint32_t u; } fu;

/* Edge cases: zeroes, subnormals, the normal/subnormal boundary, powers of two
 * around the int32 and uint32 limits, NaNs, and operands whose products land on
 * exponent 254 or on an exact tie at the subnormal boundary. */
static const uint32_t pats[] = {
    0x00000000, 0x80000000,                         /* +-0                  */
    0x00000001, 0x80000001, 0x007FFFFF, 0x807FFFFF, /* subnormals           */
    0x00800000, 0x80800000, 0x00800001,             /* +- min normal        */
    0x3F800000, 0xBF800000, 0x40000000, 0xC0000000, /* +-1, +-2             */
    0x3F000000, 0xBF000000, 0x3FC00000,             /* +-0.5, 1.5           */
    0x40490FDB, 0xC0490FDB,                         /* +-pi                 */
    0x7F7FFFFF, 0xFF7FFFFF,                         /* +-FLT_MAX            */
    0x7F800000, 0xFF800000,                         /* +-Inf                */
    0x7FC00000, 0xFFC00000, 0x7F800001, 0x7FBFFFFF, /* NaNs                 */
    0x4B000000, 0x4B7FFFFF, 0x4B800000,             /* around 2^24          */
    0x4B800001, 0x4B800002, 0x4B800003,             /* int->float tie cases */
    0x4EFFFFFF, 0x4F000000, 0x4F000001, 0x4F800000, /* around 2^31, 2^32    */
    0xCF000000, 0xCF000001, 0xCF800000,             /* around -2^31         */
    0x5F000000, 0x5F400000, 0x5F7FFFFF,             /* exponent-254 sources */
    0x7E800000, 0x7F000000, 0x7F400000, 0x7EFFFFFF,
    0x33800000, 0x01000000, 0x02000000, 0x7C000000,
    0x3FFFFFFF, 0xBFFFFFFF, 0x41200000, 0xC1200000,
    0x3F7FFFFF, 0xBF7FFFFF, 0x7E7FFFFF, 0x00FFFFFF, /* subnormal-boundary ties */
};
#define NPAT ((int)(sizeof(pats)/sizeof(pats[0])))

static int nrandom = 20000;

static uint32_t rnd_state = 0x12345678u;
static uint32_t rnd(void) {
    rnd_state = rnd_state * 1664525u + 1013904223u;
    return rnd_state;
}

static int is_sub(uint32_t u) { return ((u >> 23) & 0xFF) == 0 && (u & 0x7FFFFF) != 0; }
static int is_nan(uint32_t u) { return (u & 0x7FFFFFFF) > 0x7F800000; }

/* The library flushes subnormals to zero, so those cases are out of contract. */
static int skip(uint32_t a, uint32_t b, uint32_t r) {
    return is_sub(a) || is_sub(b) || is_sub(r);
}

static void pick(int pass, int i, fu *a, fu *b) {
    if (pass == 0) { a->u = pats[i / NPAT]; b->u = pats[i % NPAT]; }
    else           { a->u = rnd();          b->u = rnd(); }
}

static void emit_binop(FILE *o, const char *name, int op) {
    fprintf(o, "static const vec2_t %s[] = {\n", name);
    int n = 0;
    for (int pass = 0; pass < 2; pass++) {
        int count = (pass == 0) ? NPAT * NPAT : nrandom;
        for (int i = 0; i < count; i++) {
            fu a, b, r;
            pick(pass, i, &a, &b);
            switch (op) {
                case 0: r.f = a.f + b.f; break;
                case 1: r.f = a.f - b.f; break;
                case 2: r.f = a.f * b.f; break;
                default: r.f = a.f / b.f; break;
            }
            if (skip(a.u, b.u, r.u)) continue;
            fprintf(o, "  {0x%08X,0x%08X,0x%08X},\n", a.u, b.u, r.u);
            n++;
        }
    }
    fprintf(o, "};\n#define %s_N %d\n\n", name, n);
}

static void emit_cmp(FILE *o) {
    fprintf(o, "static const cmp_t cmp_vectors[] = {\n");
    int n = 0;
    for (int pass = 0; pass < 2; pass++) {
        int count = (pass == 0) ? NPAT * NPAT : nrandom;
        for (int i = 0; i < count; i++) {
            fu a, b;
            pick(pass, i, &a, &b);
            if (is_sub(a.u) || is_sub(b.u)) continue;
            int eq = (a.f == b.f), lt = (a.f < b.f), le = (a.f <= b.f);
            int gt = (a.f > b.f), ge = (a.f >= b.f);
            int un = (is_nan(a.u) || is_nan(b.u));
            fprintf(o, "  {0x%08X,0x%08X,%d},\n", a.u, b.u,
                    eq | (lt << 1) | (le << 2) | (gt << 3) | (ge << 4) | (un << 5));
            n++;
        }
    }
    fprintf(o, "};\n#define cmp_vectors_N %d\n\n", n);
}

static void emit_conv(FILE *o) {
    static const uint32_t ints[] = {
        0, 1, 2, 3, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x7FFFFFFE,
        0x00FFFFFF, 0x01000000, 0x01000001, 0x01000002, 0x01000003,
        0x01000004, 0x01000005, 0xFF000001, 0xFEFFFFFF, 0x80000001,
        16777216, 16777217, 16777218, 16777219, 16777220, 16777221,
        0x40000000, 0xC0000000, 123456789, 0xF8000001, 0x00800001,
    };
    int nint = (int)(sizeof(ints)/sizeof(ints[0]));

    fprintf(o, "static const conv_i2f_t i2f_vectors[] = {\n");
    int n = 0;
    for (int i = 0; i < nint + nrandom; i++) {
        uint32_t v = (i < nint) ? ints[i] : rnd();
        fu s, u;
        s.f = (float)(int32_t)v;
        u.f = (float)v;
        fprintf(o, "  {0x%08X,0x%08X,0x%08X},\n", v, s.u, u.u);
        n++;
    }
    fprintf(o, "};\n#define i2f_vectors_N %d\n\n", n);

    /* Out-of-range and NaN conversions follow RISC-V fcvt saturating semantics. */
    fprintf(o, "static const conv_f2i_t f2i_vectors[] = {\n");
    n = 0;
    for (int i = 0; i < NPAT + nrandom; i++) {
        fu a;
        a.u = (i < NPAT) ? pats[i] : rnd();
        if (is_sub(a.u)) continue;
        uint32_t si, ui;
        if (is_nan(a.u))               { si = 0x7FFFFFFF; ui = 0xFFFFFFFF; }
        else {
            if (a.f >= 2147483648.0f)      si = 0x7FFFFFFF;
            else if (a.f < -2147483648.0f) si = 0x80000000;
            else                           si = (uint32_t)(int32_t)a.f;
            if (a.f >= 4294967296.0f)      ui = 0xFFFFFFFF;
            else if (a.f < 0.0f)           ui = 0;
            else                           ui = (uint32_t)a.f;
        }
        fprintf(o, "  {0x%08X,0x%08X,0x%08X},\n", a.u, si, ui);
        n++;
    }
    fprintf(o, "};\n#define f2i_vectors_N %d\n\n", n);
}

int main(int argc, char **argv) {
    const char *path = (argc > 1) ? argv[1] : "vectors.h";
    if (argc > 2) nrandom = atoi(argv[2]);

    FILE *o = fopen(path, "w");
    if (!o) { perror(path); return 1; }

    fprintf(o, "/* generated by tests/gen.c - do not edit */\n");
    fprintf(o, "typedef struct { uint32_t a, b, r; } vec2_t;\n");
    fprintf(o, "typedef struct { uint32_t a, b; int flags; } cmp_t;\n");
    fprintf(o, "typedef struct { uint32_t v, s, u; } conv_i2f_t;\n");
    fprintf(o, "typedef struct { uint32_t a, s, u; } conv_f2i_t;\n\n");
    emit_binop(o, "add_vectors", 0);
    emit_binop(o, "sub_vectors", 1);
    emit_binop(o, "mul_vectors", 2);
    emit_binop(o, "div_vectors", 3);
    emit_cmp(o);
    emit_conv(o);
    fclose(o);
    return 0;
}
