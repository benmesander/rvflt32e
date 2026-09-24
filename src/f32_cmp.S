# Copyright ETH Zurich 2020
# Copyright Benard Mesander 2026	
#
# Author: Matteo Perotti, Benard Mesander
#
# This file is part of rvfp32e.
#
# rvfp32e is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# rvfp32e is distributed in the hope that it will be useful,
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

/* src/f32_cmp.S - Consolidated Relational Comparisons for rvfp32e
 * Target: RV32EC / ilp32e (CH32V003)
 *
 * GCC libgcc interface conventions for single-precision floats:
 *   __eqsf2 / __nesf2 : returns 0 if equal, non-zero if not equal
 *   __ltsf2 / __lesf2 : returns < 0 if a < b (or a <= b), >= 0 otherwise
 *   __gtsf2 / __gesf2 : returns > 0 if a > b (or a >= b), <= 0 otherwise
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
    # Handle +0.0 vs -0.0 equivalence (0x00000000 == 0x80000000)
    slli    a2, a0, 1           # Strip sign bit from a
    slli    a3, a1, 1           # Strip sign bit from b
    or      a2, a2, a3          # Combine both magnitude checks
    beqz    a2, 1f              # If both are zero, return 0 (equal)

    sub     a0, a0, a1          # Bitwise subtraction
1:
    ret
    .size __eqsf2, . - __eqsf2
    .size __nesf2, . - __nesf2


/* -------------------------------------------------------------------
 * Less Than / Less Than or Equal (__ltsf2, __lesf2)
 * ------------------------------------------------------------------- */
    .section .text.__ltsf2, "ax", @progbits
    .globl __ltsf2
    .globl __lesf2
    .type __ltsf2, @function
    .type __lesf2, @function

__ltsf2:
__lesf2:
    # Handle zero sign checks (+0.0 == -0.0)
    slli    a2, a0, 1
    slli    a3, a1, 1
    or      a2, a2, a3
    beqz    a2, 2f              # Both zero -> return 0

    # Compare signs
    srli    a2, a0, 31          # a sign bit
    srli    a3, a1, 31          # b sign bit
    bne     a2, a3, 1f          # If signs differ, negative operand is smaller

    # Signs are equal: check magnitude
    # If both negative (a2 == 1), reverse comparison order
    sub     a0, a0, a1
    beqz    a2, 3f
    neg     a0, a0              # Invert comparison for negative numbers
3:
    ret

1:
    # Signs differ: return -1 if a is negative (a2 == 1), else +1
    li      a0, 1
    beqz    a2, 3b
2:
    li      a0, -1
    ret
    .size __ltsf2, . - __ltsf2
    .size __lesf2, . - __lesf2


/* -------------------------------------------------------------------
 * Greater Than / Greater Than or Equal (__gtsf2, __gesf2)
 * ------------------------------------------------------------------- */
    .section .text.__gtsf2, "ax", @progbits
    .globl __gtsf2
    .globl __gesf2
    .type __gtsf2, @function
    .type __gesf2, @function

__gtsf2:
__gesf2:
    # Greater Than is simply the inverted result of Less Than (__ltsf2)
    # Swap arguments (a0 <-> a1) and branch into less-than comparison logic
    mv      a2, a0
    mv      a0, a1
    mv      a1, a2
    j       __ltsf2

    .size __gtsf2, . - __gtsf2
    .size __gesf2, . - __gesf2
	
