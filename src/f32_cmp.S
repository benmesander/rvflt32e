# Copyright Benard Mesander 2026
#
# Author: Benard Mesander
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

################################################################################
# src/f32_cmp.S - Relational comparisons for rvflt32e
# Target: RV32EC / ilp32e (CH32V003)
#
# A value is NaN iff its magnitude, with the sign shifted out, exceeds
# 0xFF000000. Every entry point tests that first so the unordered result can
# be chosen before any ordering work is done.
################################################################################

.globl	__eqsf2
.globl	__nesf2
.globl	__ltsf2
.globl	__lesf2
.globl	__gtsf2
.globl	__gesf2
.globl	__unordsf2

	.section .text.__eqsf2, "ax", @progbits
	.p2align 1
	.type	__eqsf2, @function
	.type	__nesf2, @function

################################################################################
# routine: __eqsf2, __nesf2
#
# Equality comparison following the libgcc convention: zero when the operands
# are equal, non-zero otherwise. A NaN operand is never equal to anything,
# including itself, so it must report non-zero.
#
# input registers:
# a0 = operand a
# a1 = operand b
#
# output registers:
# a0 = 0 if a == b, non-zero otherwise
################################################################################

__eqsf2:
__nesf2:
	lui	a4, 0xFF000
	slli	a2, a0, 1		# magnitude of a
	bltu	a4, a2, .Leq_unord
	slli	a3, a1, 1		# magnitude of b
	bltu	a4, a3, .Leq_unord
	or	a5, a2, a3
	beqz	a5, .Leq_zero		# +0 equals -0
	sub	a0, a0, a1		# zero only for identical bit patterns
	ret

.Leq_zero:
	li	a0, 0
	ret

.Leq_unord:
	li	a0, 1
	ret

	.size	__eqsf2, .-__eqsf2
	.size	__nesf2, .-__nesf2

	.section .text.__ltsf2, "ax", @progbits
	.p2align 1
	.type	__ltsf2, @function
	.type	__lesf2, @function
	.type	__gtsf2, @function
	.type	__gesf2, @function

################################################################################
# routine: __ltsf2, __lesf2, __gtsf2, __gesf2
#
# Three-way ordered comparison. For ordered operands all four routines want the
# same answer, so they share one core and differ only in the value returned for
# an unordered pair. That value cannot be obtained by swapping the arguments of
# a single routine, because the NaN result has to keep the same sign for both
# members of a pair while the ordered result flips.
#
# input registers:
# a0 = operand a
# a1 = operand b
#
# output registers:
# a0 = negative if a < b, zero if a == b, positive if a > b
#      positive if unordered for lt/le, negative if unordered for gt/ge
################################################################################

__ltsf2:
__lesf2:
	li	t0, 1			# unordered has to make "a < b" false
	j	.Lcmp

__gtsf2:
__gesf2:
	li	t0, -1			# unordered has to make "a > b" false

.Lcmp:
	lui	a4, 0xFF000
	slli	a2, a0, 1		# magnitude of a
	bltu	a4, a2, .Lcmp_unord
	slli	a3, a1, 1		# magnitude of b
	bltu	a4, a3, .Lcmp_unord
	or	a5, a2, a3
	beqz	a5, .Lcmp_eq		# +0 equals -0
	srli	a4, a0, 31		# sign of a
	srli	a5, a1, 31		# sign of b
	bne	a4, a5, .Lcmp_signs
	li	a0, -1
	bltu	a2, a3, .Lcmp_adj
	li	a0, 1
	bltu	a3, a2, .Lcmp_adj

.Lcmp_eq:
	li	a0, 0
	ret

.Lcmp_adj:
	beqz	a4, .Lcmp_adj_ret	# two negatives reverse the magnitude order
	neg	a0, a0

.Lcmp_adj_ret:
	ret

.Lcmp_signs:
	li	a0, 1			# a positive, b negative
	beqz	a4, .Lcmp_signs_ret
	li	a0, -1			# a negative, b positive

.Lcmp_signs_ret:
	ret

.Lcmp_unord:
	mv	a0, t0
	ret

	# All four entry points run into the shared core, so the extents overlap.
	.size	__ltsf2, .-__ltsf2
	.size	__lesf2, .-__lesf2
	.size	__gtsf2, .-__gtsf2
	.size	__gesf2, .-__gesf2

	.section .text.__unordsf2, "ax", @progbits
	.p2align 1
	.type	__unordsf2, @function

################################################################################
# routine: __unordsf2
#
# Unordered predicate. GCC emits calls to this for isunordered(), and for
# relational operators on operands it cannot prove are not NaN.
#
# input registers:
# a0 = operand a
# a1 = operand b
#
# output registers:
# a0 = non-zero if either operand is NaN, zero otherwise
################################################################################

__unordsf2:
	lui	a4, 0xFF000
	slli	a2, a0, 1
	slli	a3, a1, 1
	li	a0, 1
	bltu	a4, a2, .Lunord_done
	bltu	a4, a3, .Lunord_done
	li	a0, 0

.Lunord_done:
	ret

	.size	__unordsf2, .-__unordsf2

