/* tests/spike_main.c - Bare-metal conformance harness for rvflt32e.
 *
 * Compares every library routine against host-generated IEEE-754 reference
 * vectors (see tests/gen.c). Builds freestanding for the library's real
 * rv32ec/ilp32e target: no libc, and no libgcc, so this file must avoid
 * anything that would emit a compiler helper call other than __mulsi3.
 *
 * This file is part of rvflt32e and is distributed under the same terms; see
 * LICENSE.txt and LICENSE-EXCEPTION.txt.
 */
#include <stdint.h>
#include "vectors.h"
#include "rvflt32e.h"

extern volatile uint32_t tohost[2];

static void htif_putc(char c) {
    while (tohost[0] || tohost[1]) { }  /* spike zeroes tohost once it has drained */
    tohost[0] = (uint32_t)(unsigned char)c;
    tohost[1] = 0x01010000u;            /* device 1 (console), command 1 (putchar) */
}

static void puts_(const char *s) { while (*s) htif_putc(*s++); }

static void put_hex(uint32_t v) {
    puts_("0x");
    for (int i = 28; i >= 0; i -= 4)
        htif_putc("0123456789ABCDEF"[(v >> i) & 0xF]);
}

/* Repeated subtraction keeps this free of __udivsi3 / __umodsi3. */
static void put_dec(uint32_t v) {
    static const uint32_t p10[] = {
        1000000000u, 100000000u, 10000000u, 1000000u, 100000u,
        10000u, 1000u, 100u, 10u, 1u,
    };
    int started = 0;
    for (int i = 0; i < 10; i++) {
        char d = '0';
        while (v >= p10[i]) { v -= p10[i]; d++; }
        if (d != '0' || started || i == 9) { htif_putc(d); started = 1; }
    }
}

typedef union { float f; uint32_t u; } fu;
static float F(uint32_t u) { fu x; x.u = u; return x.f; }
static uint32_t U(float f) { fu x; x.f = f; return x.u; }
static int is_nan(uint32_t u) { return (u & 0x7FFFFFFF) > 0x7F800000; }

static const char *const cat_names[] = {
    "addsf3", "subsf3", "mulsf3", "divsf3",
    "eqsf2", "ltsf2", "lesf2", "gtsf2", "gesf2", "unordsf2",
    "floatsisf", "floatunsisf", "fixsfsi", "fixunssfsi",
};
#define NCAT ((int)(sizeof(cat_names)/sizeof(cat_names[0])))

static uint32_t checks;
static int failures;
static int reported;
static int cat_fail[NCAT];

static void fail(int cat, uint32_t a, uint32_t b, uint32_t got, uint32_t exp) {
    failures++;
    cat_fail[cat]++;
    if (reported++ >= 10) return;
    puts_("FAIL ");
    puts_(cat_names[cat]);
    puts_(" a=");   put_hex(a);
    puts_(" b=");   put_hex(b);
    puts_(" got="); put_hex(got);
    puts_(" exp="); put_hex(exp);
    htif_putc('\n');
}

static void check_binop(int cat, const vec2_t *v, int n, float (*fn)(float, float)) {
    for (int i = 0; i < n; i++) {
        uint32_t got = U(fn(F(v[i].a), F(v[i].b)));
        checks++;
        /* The library returns the canonical quiet NaN; any NaN is acceptable. */
        if (is_nan(v[i].r)) {
            if (!is_nan(got)) fail(cat, v[i].a, v[i].b, got, v[i].r);
        } else if (got != v[i].r) {
            fail(cat, v[i].a, v[i].b, got, v[i].r);
        }
    }
}

static void check_one_cmp(int cat, int actual, int expected, uint32_t a, uint32_t b) {
    checks++;
    if (actual != expected) fail(cat, a, b, (uint32_t)actual, (uint32_t)expected);
}

static void check_cmp(void) {
    for (int i = 0; i < cmp_vectors_N; i++) {
        uint32_t a = cmp_vectors[i].a, b = cmp_vectors[i].b;
        int f = cmp_vectors[i].flags;
        float x = F(a), y = F(b);
        check_one_cmp(4, __eqsf2(x, y) == 0,    (f >> 0) & 1, a, b);
        check_one_cmp(5, __ltsf2(x, y) <  0,    (f >> 1) & 1, a, b);
        check_one_cmp(6, __lesf2(x, y) <= 0,    (f >> 2) & 1, a, b);
        check_one_cmp(7, __gtsf2(x, y) >  0,    (f >> 3) & 1, a, b);
        check_one_cmp(8, __gesf2(x, y) >= 0,    (f >> 4) & 1, a, b);
        check_one_cmp(9, __unordsf2(x, y) != 0, (f >> 5) & 1, a, b);
    }
}

static void check_conv(void) {
    for (int i = 0; i < i2f_vectors_N; i++) {
        uint32_t v = i2f_vectors[i].v;
        uint32_t gs = U(__floatsisf((int32_t)v));
        uint32_t gu = U(__floatunsisf(v));
        checks += 2;
        if (gs != i2f_vectors[i].s) fail(10, v, 0, gs, i2f_vectors[i].s);
        if (gu != i2f_vectors[i].u) fail(11, v, 0, gu, i2f_vectors[i].u);
    }
    for (int i = 0; i < f2i_vectors_N; i++) {
        uint32_t a = f2i_vectors[i].a;
        uint32_t gs = (uint32_t)__fixsfsi(F(a));
        uint32_t gu = __fixunssfsi(F(a));
        checks += 2;
        if (gs != f2i_vectors[i].s) fail(12, a, 0, gs, f2i_vectors[i].s);
        if (gu != f2i_vectors[i].u) fail(13, a, 0, gu, f2i_vectors[i].u);
    }
}

int test_main(void) {
    check_binop(0, add_vectors, add_vectors_N, __addsf3);
    check_binop(1, sub_vectors, sub_vectors_N, __subsf3);
    check_binop(2, mul_vectors, mul_vectors_N, __mulsf3);
    check_binop(3, div_vectors, div_vectors_N, __divsf3);
    check_cmp();
    check_conv();

    puts_("checks: ");
    put_dec(checks);
    puts_("  failures: ");
    put_dec((uint32_t)failures);
    htif_putc('\n');
    for (int i = 0; i < NCAT; i++) {
        if (!cat_fail[i]) continue;
        puts_("  ");
        puts_(cat_names[i]);
        puts_(": ");
        put_dec((uint32_t)cat_fail[i]);
        htif_putc('\n');
    }
    puts_(failures ? "RESULT: FAIL\n" : "RESULT: PASS\n");
    return failures ? 1 : 0;
}
