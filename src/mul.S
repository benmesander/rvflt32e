################################################################################
# Copyright Benard Mesander 2026
#
# Author: Benard Mesander
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
#
# routine: __mulsi3
#
# Native word length signed/unsigned multiplication.
#
# Optimizations:
# - Swaps operands to ensure the smaller value is the multiplier (loop counter).
#
# input registers:
# a0 = multiplicand
# a1 = multiplier
#
# output registers:
# a0 = product
################################################################################

    .text
    .section .text.__mulsi3, "ax", @progbits
    .globl __mulsi3
    .type __mulsi3, @function

__mulsi3:
    xor     t0, a0, a1          # t0 bit 31 stores the expected final sign

    # Convert a0 to |a0|
    bgez    a0, 1f
    neg     a0, a0
1:
    # Convert a1 to |a1|
    bgez    a1, 2f
    neg     a1, a1
2:
    # Swap operands so smaller magnitude is in a1 (multiplier)
    bgeu    a0, a1, 3f
    mv      a2, a0
    mv      a0, a1
    mv      a1, a2
3:
    mv      a2, a0              # a2 = multiplicand magnitude
    li      a0, 0              # a0 = product accumulator

mul_loop:
    andi    a3, a1, 1          # Test LSB of multiplier
    beqz    a3, skip_add
    add     a0, a0, a2          # Accumulate
skip_add:
    srli    a1, a1, 1          # Shift multiplier right
    slli    a2, a2, 1          # Shift multiplicand left
    bnez    a1, mul_loop       # Exit as soon as remaining multiplier bits are 0

    # Apply sign correction
    bgez    t0, exit
    neg     a0, a0
exit:
    ret
    .size __mulsi3, . - __mulsi3
