#include <stdint.h>

/* --- Minimal Soft Integer Division/Modulo for RV32E --- */
uint32_t __udivsi3(uint32_t num, uint32_t den) {
    if (den == 0) return 0;
    uint32_t quot = 0, qbit = 1;
    while ((int32_t)den >= 0 && den < num) {
        den <<= 1;
        qbit <<= 1;
    }
    while (qbit != 0) {
        if (num >= den) {
            num -= den;
            quot |= qbit;
        }
        den >>= 1;
        qbit >>= 1;
    }
    return quot;
}

uint32_t __umodsi3(uint32_t num, uint32_t den) {
    if (den == 0) return 0;
    uint32_t qbit = 1;
    while ((int32_t)den >= 0 && den < num) {
        den <<= 1;
        qbit <<= 1;
    }
    while (qbit != 0) {
        if (num >= den) {
            num -= den;
        }
        den >>= 1;
        qbit >>= 1;
    }
    return num;
}

/* --- Spike HTIF Driver --- */
volatile uint32_t tohost[2]   __attribute__((section(".htif"), aligned(64)));
volatile uint32_t fromhost[2] __attribute__((section(".htif"), aligned(64)));

static void htif_putc(char c) {
    while (tohost[0] != 0 || tohost[1] != 0);
    tohost[0] = (uint8_t)c;
    __asm__ volatile ("" ::: "memory");
    /* FIX: Explicitly set Device 1 (Console), Command 1 (Print char) */
    tohost[1] = (1U << 24) | (1U << 16);
}

static void print_str(const char *s) {
    while (*s) htif_putc(*s++);
}

static void print_dec(uint32_t val) {
    char buf[11];
    int i = 10;
    buf[i] = '\0';
    if (val == 0) {
        htif_putc('0');
        return;
    }
    while (val > 0) {
        buf[--i] = '0' + (val % 10);
        val /= 10;
    }
    print_str(&buf[i]);
}

static void htif_exit(int code) {
    while (tohost[0] != 0 || tohost[1] != 0);
    tohost[0] = ((uint32_t)code << 1) | 1U;
    __asm__ volatile ("" ::: "memory");
    tohost[1] = 0;
    while (1);
}

/* --- Cycle Measurement Helpers --- */
static inline uint32_t read_cycle(void) {
    uint32_t cy;
    /* FIX: Read the machine-mode cycle counter to avoid illegal instruction traps */
    __asm__ volatile ("csrr %0, mcycle" : "=r"(cy));
    return cy;
}

#define BENCH_LOOP_COUNT 100

volatile float g_a = 123.456f;
volatile float g_b = 78.901f;
volatile int   g_i = 42;

static void bench_op(const char *label, float (*op)(float, float)) {
    float a = g_a;
    float b = g_b;
    volatile float res;

    res = op(a, b);

    __asm__ volatile ("" ::: "memory");
    uint32_t start = read_cycle();

    for (int i = 0; i < BENCH_LOOP_COUNT; i++) {
        res = op(a, b);
    }

    __asm__ volatile ("" ::: "memory");
    uint32_t end = read_cycle();

    (void)res;

    uint32_t total_cycles = end - start;
    uint32_t cycles_per_op = total_cycles / BENCH_LOOP_COUNT;

    print_str("  ");
    print_str(label);
    print_str(": ");
    print_dec(cycles_per_op);
    print_str(" cycles/op\n");
}

__attribute__((noinline)) static float op_add(float a, float b) { return a + b; }
__attribute__((noinline)) static float op_sub(float a, float b) { return a - b; }
__attribute__((noinline)) static float op_mul(float a, float b) { return a * b; }
__attribute__((noinline)) static float op_div(float a, float b) { return a / b; }
__attribute__((noinline)) static float op_i2f(float a, float b) { (void)b; return (float)g_i + a; }
__attribute__((noinline)) static float op_f2i(float a, float b) { (void)b; return (float)((int)a); }

int main(void) {
    print_str("====================================\n");
    print_str("  Floating-Point Cycle Benchmark    \n");
    print_str("====================================\n");

    bench_op("Add (+)", op_add);
    bench_op("Sub (-)", op_sub);
    bench_op("Mul (*)", op_mul);
    bench_op("Div (/)", op_div);
    bench_op("Int->Float", op_i2f);
    bench_op("Float->Int", op_f2i);

    print_str("====================================\n");

    htif_exit(0);
    return 0;
}
