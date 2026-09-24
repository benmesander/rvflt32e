/* ==========================================================================
 * rvflt32e.h - Lightweight Single-Precision Soft-Float Library for RV32EC
 * Target: CH32V003 and resource-constrained RISC-V targets (ilp32e)
 * ========================================================================== */

#ifndef RVFLT32E_H
#define RVFLT32E_H

#ifdef __c51__ /* C51 guard / placeholder */
#elif defined(__cplusplus)
extern "C" {
#endif

/* Ensure standard fixed-width types */
#include <stdint.h>

/* --------------------------------------------------------------------------
 * Floating-Point Arithmetic Routines (__addsf3, __subsf3, __mulsf3, __divsf3)
 * -------------------------------------------------------------------------- */
extern float __addsf3(float a, float b);
extern float __subsf3(float a, float b);
extern float __mulsf3(float a, float b);
extern float __divsf3(float a, float b);

/* --------------------------------------------------------------------------
 * Relational Comparison Routines
 * GCC libgcc convention:
 *   - __eqsf2 / __nesf2: returns 0 if equal, non-zero otherwise
 *   - __ltsf2 / __lesf2: returns negative if a < (or <=) b, 0 or positive otherwise
 *   - __gtsf2 / __gesf2: returns positive if a > (or >=) b, 0 or negative otherwise
 *   - __unordsf2: returns non-zero if either operand is NaN
 * If either operand is NaN, __eqsf2 / __nesf2 return non-zero, __ltsf2 / __lesf2
 * return positive, and __gtsf2 / __gesf2 return negative, so that every ordered
 * predicate evaluates false.
 * -------------------------------------------------------------------------- */
extern int __eqsf2(float a, float b);
extern int __nesf2(float a, float b);
extern int __ltsf2(float a, float b);
extern int __lesf2(float a, float b);
extern int __gtsf2(float a, float b);
extern int __gesf2(float a, float b);
extern int __unordsf2(float a, float b);

/* --------------------------------------------------------------------------
 * Type Conversion Routines
 * -------------------------------------------------------------------------- */
extern float __floatsisf(int32_t a);
extern float __floatunsisf(uint32_t a);
extern int32_t __fixsfsi(float a);
extern uint32_t __fixunssfsi(float a);

/* --------------------------------------------------------------------------
 * Integer Arithmetic Helper Routines (from rvint / mul.S)
 * -------------------------------------------------------------------------- */
extern int32_t __mulsi3(int32_t a, int32_t b);

#ifdef __cplusplus
}
#endif

#endif /* RVFLT32E_H */
