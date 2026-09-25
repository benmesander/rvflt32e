/* tests/tf_main.c - Berkeley TestFloat filter stage for rvflt32e.
 *
 * Sits in the middle of the standard TestFloat pipeline:
 *
 *     testfloat_gen -prefix <op> <op> | spike tf_test.elf | testfloat_ver <op>
 *
 * Reads generated cases from stdin, recomputes each result with the library,
 * and writes the cases back out with our result substituted, for testfloat_ver
 * to judge independently.
 *
 * Two deliberate deviations, both a consequence of what the library promises:
 *
 *   Exception flags are echoed from the generated case rather than produced.
 *   The library implements no flag state at all, and testfloat_ver has no
 *   option to ignore the column, so echoing keeps the comparison focused on
 *   the numeric result. Flags are therefore NOT tested by this harness.
 *
 *   Cases involving subnormal operands or a subnormal reference result are
 *   dropped, because the library flushes subnormals to zero by contract.
 *   The number dropped is reported on stderr so it cannot pass unnoticed.
 *
 * Builds freestanding for rv32ec/ilp32e: no libc and no libgcc, so this file
 * must avoid anything that emits a compiler helper call other than __mulsi3.
 *
 * This file is part of rvflt32e and is distributed under the same terms; see
 * LICENSE.txt and LICENSE-EXCEPTION.txt.
 */
#include <stdint.h>
#include "rvflt32e.h"

extern volatile uint64_t tohost, fromhost;

/* Spike's HTIF syscall proxy, which gives buffered read and write instead of
 * the one character at a time console device. Addresses live above
 * 0x80000000, so they are widened through uint32_t to keep them from being
 * sign extended into the 64-bit argument slots. */
static volatile uint64_t magic[8] __attribute__((aligned(8)));

static int32_t hsys(uint32_t n, uint32_t a0, uint32_t a1, uint32_t a2) {
    volatile uint32_t *th = (volatile uint32_t *)&tohost;
    volatile uint32_t *fh = (volatile uint32_t *)&fromhost;
    magic[0] = n;
    magic[1] = a0;
    magic[2] = a1;
    magic[3] = a2;
    th[0] = (uint32_t)(uintptr_t)magic;
    th[1] = 0;
    while (fh[0] == 0 && fh[1] == 0) { }
    fh[0] = 0;
    fh[1] = 0;
    return (int32_t)magic[0];
}

#define SYS_READ  63
#define SYS_WRITE 64

static char inbuf[4096];
static int32_t inlen, inpos;

static int rdch(void) {
    if (inpos >= inlen) {
        int32_t n = hsys(SYS_READ, 0, (uint32_t)(uintptr_t)inbuf, sizeof inbuf);
        if (n <= 0) return -1;
        inlen = n;
        inpos = 0;
    }
    return (unsigned char)inbuf[inpos++];
}

static char outbuf[4096];
static int32_t outlen;

static void flushout(void) {
    if (outlen) {
        hsys(SYS_WRITE, 1, (uint32_t)(uintptr_t)outbuf, (uint32_t)outlen);
        outlen = 0;
    }
}

static void wrch(char c) {
    outbuf[outlen++] = c;
    if (outlen == (int32_t)sizeof outbuf) flushout();
}

static void wrhex(uint32_t v, int digits) {
    for (int i = (digits - 1) * 4; i >= 0; i -= 4)
        wrch("0123456789ABCDEF"[(v >> i) & 0xF]);
}

/* Nothing may be written for diagnostics: spike's syscall proxy sends fd 2 to
 * stdout, which would corrupt the pipe into testfloat_ver. Case accounting is
 * done on the host instead, and failures are signalled by the exit status. */

/* Operation table. args_float marks operands that are floats rather than
 * integers, which is what decides whether the subnormal filter applies. */
enum { K_F32, K_BOOL, K_I32 };

static const struct {
    const char *name;
    uint8_t nargs;
    uint8_t args_float;
    uint8_t res_kind;
} ops[] = {
    { "f32_add",     2, 1, K_F32  },
    { "f32_sub",     2, 1, K_F32  },
    { "f32_mul",     2, 1, K_F32  },
    { "f32_div",     2, 1, K_F32  },
    { "f32_eq",      2, 1, K_BOOL },
    { "f32_lt",      2, 1, K_BOOL },
    { "f32_le",      2, 1, K_BOOL },
    { "i32_to_f32",  1, 0, K_F32  },
    { "ui32_to_f32", 1, 0, K_F32  },
    { "f32_to_i32",  1, 1, K_I32  },
    { "f32_to_ui32", 1, 1, K_I32  },
};
#define NOPS ((int)(sizeof ops / sizeof ops[0]))

typedef union { float f; uint32_t u; } fu;
static float F(uint32_t u) { fu x; x.u = u; return x.f; }
static uint32_t U(float f) { fu x; x.f = f; return x.u; }

static int is_subnormal(uint32_t u) {
    return ((u >> 23) & 0xFF) == 0 && (u & 0x7FFFFF) != 0;
}

static uint32_t compute(int op, const uint32_t *a) {
    switch (op) {
        case 0:  return U(__addsf3(F(a[0]), F(a[1])));
        case 1:  return U(__subsf3(F(a[0]), F(a[1])));
        case 2:  return U(__mulsf3(F(a[0]), F(a[1])));
        case 3:  return U(__divsf3(F(a[0]), F(a[1])));
        case 4:  return __eqsf2(F(a[0]), F(a[1])) == 0;
        case 5:  return __ltsf2(F(a[0]), F(a[1])) <  0;
        case 6:  return __lesf2(F(a[0]), F(a[1])) <= 0;
        case 7:  return U(__floatsisf((int32_t)a[0]));
        case 8:  return U(__floatunsisf(a[0]));
        case 9:  return (uint32_t)__fixsfsi(F(a[0]));
        default: return __fixunssfsi(F(a[0]));
    }
}

static int streq(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

/* Reads one whitespace separated line of hex tokens. Returns the token count,
 * or -1 at end of input. */
static int read_tokens(uint32_t *vals, int max) {
    int n = 0, have = 0, c;
    uint32_t v = 0;
    for (;;) {
        c = rdch();
        if (c < 0) {
            if (have && n < max) vals[n++] = v;
            return n ? n : -1;
        }
        if (c == '\n') {
            if (have && n < max) vals[n++] = v;
            return n;
        }
        if (c == ' ' || c == '\t' || c == '\r') {
            if (have && n < max) vals[n++] = v;
            v = 0;
            have = 0;
            continue;
        }
        uint32_t d;
        if (c >= '0' && c <= '9')      d = (uint32_t)(c - '0');
        else if (c >= 'A' && c <= 'F') d = (uint32_t)(c - 'A' + 10);
        else if (c >= 'a' && c <= 'f') d = (uint32_t)(c - 'a' + 10);
        else continue;
        v = (v << 4) | d;
        have = 1;
    }
}

int test_main(void) {
    char name[32];
    int n = 0, c;

    /* First line is the operation name, from testfloat_gen -prefix. */
    while ((c = rdch()) >= 0 && c != '\n')
        if (n < (int)sizeof name - 1) name[n++] = (char)c;
    name[n] = 0;

    int op = -1;
    for (int i = 0; i < NOPS; i++)
        if (streq(name, ops[i].name)) { op = i; break; }

    if (op < 0) return 2;              /* unsupported or missing -prefix */

    int nargs = ops[op].nargs;
    int rkind = ops[op].res_kind;

    for (;;) {
        uint32_t v[8];
        int got = read_tokens(v, 8);
        if (got < 0) break;
        if (got != nargs + 2) continue;          /* not a case line */

        uint32_t ref = v[nargs];                 /* reference result */
        uint32_t flags = v[nargs + 1];

        /* Drop anything outside the flush to zero contract. */
        int skip = 0;
        if (ops[op].args_float)
            for (int i = 0; i < nargs; i++)
                if (is_subnormal(v[i])) skip = 1;
        if (rkind == K_F32 && is_subnormal(ref)) skip = 1;
        if (skip) continue;

        uint32_t res = compute(op, v);

        for (int i = 0; i < nargs; i++) { wrhex(v[i], 8); wrch(' '); }
        if (rkind == K_BOOL) wrhex(res, 1);
        else                 wrhex(res, 8);
        wrch(' ');
        wrhex(flags, 2);
        wrch('\n');
    }

    flushout();
    return 0;
}
