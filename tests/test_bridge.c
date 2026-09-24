/* test_bridge.c - Bridge between TestFloat and rvflt32e assembly routines */
#include <stdint.h>

/* Declarations of assembly functions in librvflt32e.a */
extern float __addsf3(float a, float b);
extern float __subsf3(float a, float b);
extern float __mulsf3(float a, float b);
extern float __divsf3(float a, float b);
extern int   __eqsf2(float a, float b);
extern int   __ltsf2(float a, float b);
extern int   __gtsf2(float a, float b);
extern float __floatsisf(int32_t a);
extern float __floatunsisf(uint32_t a);
extern int32_t  __fixsfsi(float a);
extern uint32_t __fixunssfsi(float a);

/* TestFloat 32-bit float representation wrapper */
typedef union {
    float f;
    uint32_t u;
} float32_t;

/* Adapter functions for TestFloat harness */
uint32_t test_f32_add(uint32_t a, uint32_t b) {
    float32_t fa = {.u = a}, fb = {.u = b}, fr;
    fr.f = __addsf3(fa.f, fb.f);
    return fr.u;
}

uint32_t test_f32_sub(uint32_t a, uint32_t b) {
    float32_t fa = {.u = a}, fb = {.u = b}, fr;
    fr.f = __subsf3(fa.f, fb.f);
    return fr.u;
}

uint32_t test_f32_mul(uint32_t a, uint32_t b) {
    float32_t fa = {.u = a}, fb = {.u = b}, fr;
    fr.f = __mulsf3(fa.f, fb.f);
    return fr.u;
}

uint32_t test_f32_div(uint32_t a, uint32_t b) {
    float32_t fa = {.u = a}, fb = {.u = b}, fr;
    fr.f = __divsf3(fa.f, fb.f);
    return fr.u;
}

int test_f32_eq(uint32_t a, uint32_t b) {
    float32_t fa = {.u = a}, fb = {.u = b};
    return (__eqsf2(fa.f, fb.f) == 0);
}

int test_f32_lt(uint32_t a, uint32_t b) {
    float32_t fa = {.u = a}, fb = {.u = b};
    return (__ltsf2(fa.f, fb.f) < 0);
}
