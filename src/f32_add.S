################################################################################
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
################################################################################



.globl	__addsf3
.globl	__subsf3

	.section .text.__addsf3, "ax", @progbits
	.p2align 1
	.type	__addsf3, @function
	.type	__subsf3, @function

################################################################################
# routine: __subsf3
#
# IEEE 754 single precision subtraction. Flips the sign of the subtrahend and
# falls straight into __addsf3, so the two are always linked together.
#
# input registers:
# a0 = minuend
# a1 = subtrahend
#
# output registers:
# a0 = difference
################################################################################

__subsf3:
	lui	a5, 0x80000
	xor	a1, a1, a5		# negate b, then fall through

	.size	__subsf3, .-__subsf3

################################################################################
# routine: __addsf3
#
# IEEE 754 single precision addition. The operands are ordered by magnitude so
# the larger one supplies the result sign and exponent, then the smaller is
# aligned and added or subtracted. Subnormals are flushed to zero, rounding is
# to nearest with ties to even, and a canonical quiet NaN is returned for every
# invalid case.
#
# input registers:
# a0 = operand a
# a1 = operand b
#
# output registers:
# a0 = sum
################################################################################

__addsf3:
	lui	t1, 0x80000
	xor	t2, a0, a1		# sign bit selects add versus subtract
	and	a4, a0, t1		# provisional result sign
	slli	a2, a0, 1		# magnitude of a
	slli	a3, a1, 1		# magnitude of b

	# Swap so a2 holds the larger magnitude, and take the sign with it.
	bgeu	a2, a3, .Lordered
	and	a4, a1, t1
	slli	a2, a1, 1
	slli	a3, a0, 1

.Lordered:
	lui	a5, 0xFF000		# smallest {Inf, NaN} magnitude
	bgeu	a2, a5, .Linf_nan
	bgeu	a3, a5, .Linf_nan

	# Equal magnitudes must be caught before the zero test below, otherwise
	# the sign of a +0 + -0 result is lost.
	beq	a2, a3, .Lequal

	# Ordered, finite, and possibly zero or subnormal. Leave room for the
	# implicit 1 at the top of each significand.
	slli	a0, a2, 7
	slli	a1, a3, 7
	srli	a2, a2, 24		# larger exponent
	srli	a3, a3, 24		# smaller exponent
	beqz	a2, .Lboth_tiny		# larger is zero or subnormal, so both are

	sub	t0, a2, a3		# exponent difference
	or	a0, a0, t1		# implicit 1 of the larger operand
	addi	a2, a2, -1		# the kept implicit 1 adds one back later
	beqz	a3, .Lreturn_a0		# smaller is zero or subnormal
	sltiu	a3, t0, 26		# 25 still matters when signs differ
	beqz	a3, .Lreturn_a0		# smaller operand cannot affect the sum
	or	a1, a1, t1		# implicit 1 of the smaller operand

	srl	a5, a1, t0		# align the smaller operand
	addi	t0, t0, 1
	neg	t0, t0
	sll	a1, a1, t0		# bits shifted out, plus the guard bit
	bltz	t2, .Ldiff_sign

	# Effective addition, so no cancellation, but it may overflow by one bit.
	add	a0, a0, a5
	bgeu	a0, a5, .Ladjust	# no renormalization needed
	srli	a0, a0, 1
	or	a0, a0, t1		# restore the implicit bit
	addi	a2, a2, 1
	li	a5, 254
	bge	a2, a5, .Linf

.Ladjust:
	# Collect the bits that fell out of the sum to the right of the round
	# bit, so the rounding decision below sees a correct sticky value.
	srli	a1, a1, 1
	slli	a3, a0, 24
	or	a3, a3, a1

.Lreturn_a0:
	srli	a0, a0, 8		# implicit 1 lands on the exponent

	# Round to nearest, ties to even.
	bltu	a3, t1, .Lexp_sign_and_exit
	addi	a0, a0, 1
	bne	a3, t1, .Lexp_sign_and_exit
	andi	a0, a0, -2		# exact tie, so clear the low bit

.Lexp_sign_and_exit:
	slli	a2, a2, 23
	add	a0, a0, a2

.Lsign_and_exit:
	or	a0, a0, a4

.Ldone:
	ret

.Ldiff_sign:
	# Effective subtraction. Fold the discarded bits into a sticky bit so
	# the subtraction borrows correctly.
	snez	a3, a1
	or	a5, a5, a3
	sub	a0, a0, a5
	bltz	a0, .Ladjust		# no cancellation, so just round

	# Cancellation happened, and the alignment shift was 0 or 1, so the
	# whole result is still in a0.
	slli	a0, a0, 1
	mv	a5, a2			# remember the larger exponent
	addi	a2, a2, -1
	beqz	a5, .Lsigned_zero	# exponent was 0, so the result is tiny
	bgeu	a0, t1, .Ladjust	# only mild cancellation, so round

	# Strong cancellation. This is an inline count-leading-zeros; no
	# rounding is needed because every remaining bit is already exact.
.Lclz_loop:
	slli	a0, a0, 1
	addi	a2, a2, -1
	bltu	a0, t1, .Lclz_loop

	srli	a0, a0, 8
	bge	a2, zero, .Lexp_sign_and_exit	# still normal, so finish
					# otherwise fall through and flush

.Lsigned_zero:
	mv	a0, a4
	ret

.Lboth_tiny:
	# Both operands are zero or subnormal. Under flush to zero the result
	# is a zero whose sign is negative only if both operands were negative,
	# which keeps +0 + -0 positive.
	xor	t2, t2, t1
	and	a0, a4, t2

.Lzero_mantissa:
	srli	a0, a0, 31
	slli	a0, a0, 31
	ret

.Lequal:
	# The magnitudes match. a0 and a1 still hold the original operands, and
	# a2 and a3 are interchangeable because the magnitudes are the same.
	beq	a0, a1, .Lequal_samesign
	mv	a0, zero		# opposite signs cancel exactly
	ret

.Lequal_samesign:
	# a5 still holds 0xFF000000, so this isolates the exponent field.
	and	a5, a5, a2
	beqz	a5, .Lzero_mantissa	# both operands are subnormal

	srli	a2, a2, 24
	sltiu	a5, a2, 0xFE		# can the exponent absorb a doubling?
	beqz	a5, .Linf
	lui	a5, 0x00800
	add	a0, a0, a5		# doubling is just exponent plus one
	ret

.Linf:
	lui	a0, 0x7F800
	j	.Lsign_and_exit

.Linf_nan:
	# The larger magnitude is Inf or NaN; nothing is known about the smaller
	# one yet beyond it being no larger.
	bgtu	a2, a5, .Lproduce_nan	# larger operand is NaN
	bne	a2, a3, .Linf		# smaller one is finite
	beq	a0, a1, .Ldone		# two identical infinities

.Lproduce_nan:
	lui	a0, 0x7FC00		# canonical quiet NaN
	ret

	.size	__addsf3, .-__addsf3
