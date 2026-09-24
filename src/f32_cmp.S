# Copyright ETH Zurich 2020
# Copyright Benard Mesander 2026	
#
# Author: Matteo Perotti, Benard Mesander
#
# This file is part of rvflt32e.
#
# rvflt32e is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# rvflt32e is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# Under Section 7 of GPL version 3, you are granted additional
# permissions described in the GCC Runtime Library Exception, version
# 3.1, as published by the Free Software Foundation.
#
# You should have received a copy of the GNU General Public License and
# a copy of the GCC Runtime Library Exception along with this program;
# see the files LICENSE.txt and LICENSE-EXCEPTION.txt respectively.  If not, see
# <http://www.gnu.org/licenses/>.

/* src/f32_cmp.S - Consolidated Relational Comparisons for rvflt32e
 * Target: RV32EC / ilp32e (CH32V003)
 *
 * GCC libgcc interface conventions for single-precision floats:
 *   __eqsf2 / __nesf2 : 0 if equal, non-zero if not equal or unordered
 *   __ltsf2 / __lesf2 : < 0 if a < b (or a <= b), >= 0 otherwise, > 0 if unordered
 *   __gtsf2 / __gesf2 : > 0 if a > b (or a >= b), <= 0 otherwise, < 0 if unordered
 *   __unordsf2        : non-zero if either operand is NaN
 *
 * A value is NaN iff its magnitude (sign shifted out) exceeds 0xFF000000.
 */

    .text

/* -------------------------------------------------------------------
 * Equal / Not Equal (__eqsf2, __nesf2)
 * ------------------------------------------------------------------- */
    .section .text.__eqsf2, "ax", @progbits
    .globl __eqsf2
    .globl __nesf2
    .type __eqsf2, @function
    .type __nesf2, @function

__eqsf2:
__nesf2:
    lui     a4, 0xFF000
    slli    a2, a0, 1           # magnitude of a
    bltu    a4, a2, .Leq_unord
    slli    a3, a1, 1           # magnitude of b
    bltu    a4, a3, .Leq_unord
    or      a5, a2, a3
    beqz    a5, .Leq_zero       # +0 equals -0
    sub     a0, a0, a1          # zero only for identical bit patterns
    ret
.Leq_zero:
    li      a0, 0
    ret
.Leq_unord:
    li      a0, 1
    ret
    .size __eqsf2, . - __eqsf2
    .size __nesf2, . - __nesf2


/* -------------------------------------------------------------------
 * Ordered comparisons (__ltsf2, __lesf2, __gtsf2, __gesf2)
 *
 * For ordered operands all four return the same three-way result, so they
 * share one core and differ only in the value produced for NaN.
 * ------------------------------------------------------------------- */
    .section .text.__ltsf2, "ax", @progbits
    .globl __ltsf2
    .globl __lesf2
    .type __ltsf2, @function
    .type __lesf2, @function

__ltsf2:
__lesf2:
    li      t0, 1               # unordered must make "a < b" false
    j       .Lcmp
    .size __ltsf2, . - __ltsf2
    .size __lesf2, . - __lesf2


/* Greater Than / Greater Than or Equal share the core below; they cannot be
 * an argument swap of __ltsf2 because the NaN result has the opposite sign. */
    .globl __gtsf2
    .globl __gesf2
    .type __gtsf2, @function
    .type __gesf2, @function

__gtsf2:
__gesf2:
    li      t0, -1              # unordered must make "a > b" false

.Lcmp:
    lui     a4, 0xFF000
    slli    a2, a0, 1           # magnitude of a
    bltu    a4, a2, .Lcmp_unord
    slli    a3, a1, 1           # magnitude of b
    bltu    a4, a3, .Lcmp_unord
    or      a5, a2, a3
    beqz    a5, .Lcmp_eq        # +0 equals -0
    srli    a4, a0, 31          # sign of a
    srli    a5, a1, 31          # sign of b
    bne     a4, a5, .Lcmp_signs
    li      a0, -1
    bltu    a2, a3, .Lcmp_adj
    li      a0, 1
    bltu    a3, a2, .Lcmp_adj
.Lcmp_eq:
    li      a0, 0
    ret
.Lcmp_adj:
    beqz    a4, 1f              # both negative reverses the magnitude order
    neg     a0, a0
1:
    ret
.Lcmp_signs:
    li      a0, 1               # a positive, b negative
    beqz    a4, 1f
    li      a0, -1              # a negative, b positive
1:
    ret
.Lcmp_unord:
    mv      a0, t0
    ret
    .size __gtsf2, . - __gtsf2
    .size __gesf2, . - __gesf2


/* -------------------------------------------------------------------
 * Unordered predicate (__unordsf2)
 * ------------------------------------------------------------------- */
    .section .text.__unordsf2, "ax", @progbits
    .globl __unordsf2
    .type __unordsf2, @function

__unordsf2:
    lui     a4, 0xFF000
    slli    a2, a0, 1
    slli    a3, a1, 1
    li      a0, 1
    bltu    a4, a2, 1f
    bltu    a4, a3, 1f
    li      a0, 0
1:
    ret
    .size __unordsf2, . - __unordsf2
	
