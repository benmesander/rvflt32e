/* tests/main_test.c */
#include <stdio.h>
#include <stdint.h>

extern uint32_t test_f32_add(uint32_t a, uint32_t b);

typedef struct {
    uint32_t a;
    uint32_t b;
    uint32_t expected;
} test_vector_t;

static const test_vector_t add_vectors[] = {
    {0x3f800000, 0x3f800000, 0x40000000}, /* 1.0 + 1.0 = 2.0 */
    {0xbf800000, 0x3f800000, 0x00000000}, /* -1.0 + 1.0 = 0.0 */
    {0x00000000, 0x80000000, 0x00000000}, /* +0.0 + -0.0 = +0.0 */
    {0x7f800000, 0x3f800000, 0x7f800000}, /* +Inf + 1.0 = +Inf */
};

int main(void) {
    int passes = 0;
    int total = sizeof(add_vectors) / sizeof(add_vectors[0]);

    for (int i = 0; i < total; i++) {
        uint32_t res = test_f32_add(add_vectors[i].a, add_vectors[i].b);
        if (res == add_vectors[i].expected) {
            passes++;
        } else {
            printf("FAIL [%d]: a=0x%08lx b=0x%08lx -> got 0x%08lx, exp 0x%08lx\n",
                   i,
                   (unsigned long)add_vectors[i].a,
                   (unsigned long)add_vectors[i].b,
                   (unsigned long)res,
                   (unsigned long)add_vectors[i].expected);
        }
    }

    printf("Test Results: %d/%d Passed\n", passes, total);
    return (passes == total) ? 0 : 1;
}
