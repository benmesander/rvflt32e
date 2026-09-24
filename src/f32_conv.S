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

/* src/f32_conv.S - Consolidated Type Conversions for rvflt32e
 * Target: RV32EC / ilp32e (CH32V003)
 *
 * GCC libgcc interface conventions for single-precision conversions:
 *   __floatsisf   : signed 32-bit int -> float (a0 -> a0), round-to-nearest-even
 *   __floatunsisf : unsigned 32-bit int -> float (a0 -> a0), round-to-nearest-even
 *   __fixsfsi     : float -> signed 32-bit int (a0 -> a0, truncates toward zero)
 *   __fixunssfsi  : float -> unsigned 32-bit int (a0 -> a0, truncates toward zero)
 *
 * Out-of-range and NaN float->int conversions follow RISC-V fcvt semantics:
 * NaN and positive overflow give INT_MAX / UINT_MAX, negative overflow gives
 * INT_MIN, and any negative input to __fixunssfsi gives 0.
 */

    .text

/* -------------------------------------------------------------------
 * Integer to Float Conversions (__floatsisf, __floatunsisf)
 * ------------------------------------------------------------------- */
    .section .text.__floatsisf, "ax", @progbits
    .globl __floatsisf
    .globl __floatunsisf
    .type __floatsisf, @function
    .type __floatunsisf, @function

__floatsisf:
    # If input integer is zero, return 0.0 directly
    beqz    a0, 1f

    # Extract and record sign bit
    srli    a1, a0, 31          # a1 = sign bit (1 if negative)
    beqz    a1, __floatunsisf   # If positive, use unsigned conversion logic

    # Handle negative signed int: take absolute value
    neg     a0, a0
    slli    a1, a1, 31          # Move sign bit to MSB (0x80000000)
    j       .Lnorm_int

1:
    ret
    .size __floatsisf, . - __floatsisf

    .section .text.__floatunsisf, "ax", @progbits
    .globl __floatunsisf
    .type __floatunsisf, @function

__floatunsisf:
    beqz    a0, 1f
    li      a1, 0               # Sign bit is 0 for unsigned

.Lnorm_int:
    # Normalize 32-bit integer into 24-bit IEEE 754 mantissa
    # Base exponent for 32-bit integer scaling is 158 (127 + 31)
    li      a2, 158

.Lnorm_loop:
    # Shift left until MSB (bit 31) is set
    bltz    a0, .Lpack_float
    slli    a0, a0, 1
    addi    a2, a2, -1
    j       .Lnorm_loop

.Lpack_float:
    # a0 is normalized with bit 31 set; a2 is the biased exponent.
    andi    a3, a0, 0xFF        # guard + sticky bits
    srli    a0, a0, 8           # [23:0], bit 23 = implicit 1
    addi    a2, a2, -1          # implicit 1 carries back into the exponent
    slli    a2, a2, 23
    add     a0, a0, a2

    # Round to nearest, ties to even. A carry out of the fraction propagates
    # into the exponent, which is exactly what we want.
    li      a4, 0x80
    bltu    a3, a4, .Lapply_isign
    bne     a3, a4, .Lround_up
    andi    a4, a0, 1           # exact tie: round up only if odd
    beqz    a4, .Lapply_isign
.Lround_up:
    addi    a0, a0, 1

.Lapply_isign:
    or      a0, a0, a1
1:
    ret
    .size __floatunsisf, . - __floatunsisf


/* -------------------------------------------------------------------
 * Float to Integer Conversions (__fixsfsi, __fixunssfsi)
 * ------------------------------------------------------------------- */
    .section .text.__fixsfsi, "ax", @progbits
    .globl __fixsfsi
    .type __fixsfsi, @function

__fixsfsi:
    slli    a2, a0, 1           # magnitude
    lui     a3, 0xFF000
    bltu    a3, a2, .Lfix_max   # NaN
    srli    a1, a0, 31          # sign
    srli    a2, a2, 24
    addi    a2, a2, -127        # unbiased exponent
    bltz    a2, .Lfix_zero      # |x| < 1.0
    li      a3, 31
    bgtu    a2, a3, .Lfix_sat   # |x| >= 2^32, or Inf

    slli    a0, a0, 9
    srli    a0, a0, 9
    lui     a3, 0x00800
    or      a0, a0, a3          # 24-bit significand, bit 23 = implicit 1
    addi    a2, a2, -23
    bltz    a2, .Lfix_shr
    sll     a0, a0, a2          # exponent <= 31 keeps this inside 32 bits
    j       .Lfix_sign
.Lfix_shr:
    neg     a2, a2
    srl     a0, a0, a2

.Lfix_sign:
    lui     a3, 0x80000
    beqz    a1, .Lfix_pos
    bltu    a3, a0, .Lfix_min   # magnitude beyond 2^31
    neg     a0, a0              # -2^31 negates to itself, which is correct
    ret
.Lfix_pos:
    bgeu    a0, a3, .Lfix_max
    ret

.Lfix_zero:
    li      a0, 0
    ret
.Lfix_sat:
    bnez    a1, .Lfix_min
.Lfix_max:
    lui     a0, 0x80000
    addi    a0, a0, -1          # INT_MAX
    ret
.Lfix_min:
    lui     a0, 0x80000         # INT_MIN
    ret
    .size __fixsfsi, . - __fixsfsi

    .section .text.__fixunssfsi, "ax", @progbits
    .globl __fixunssfsi
    .type __fixunssfsi, @function

__fixunssfsi:
    slli    a2, a0, 1           # magnitude
    lui     a3, 0xFF000
    bltu    a3, a2, .Lfixu_max  # NaN
    bltz    a0, .Lfixu_zero     # any negative input, including -0.0
    srli    a2, a2, 24
    addi    a2, a2, -127        # unbiased exponent
    bltz    a2, .Lfixu_zero     # x < 1.0
    li      a3, 31
    bgtu    a2, a3, .Lfixu_max  # x >= 2^32, or +Inf

    slli    a0, a0, 9
    srli    a0, a0, 9
    lui     a3, 0x00800
    or      a0, a0, a3          # 24-bit significand, bit 23 = implicit 1
    addi    a2, a2, -23
    bltz    a2, .Lfixu_shr
    sll     a0, a0, a2
    ret
.Lfixu_shr:
    neg     a2, a2
    srl     a0, a0, a2
    ret

.Lfixu_zero:
    li      a0, 0
    ret
.Lfixu_max:
    li      a0, -1              # UINT_MAX
    ret
    .size __fixunssfsi, . - __fixunssfsi
