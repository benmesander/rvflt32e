################################################################################
# Copyright ETH Zurich 2020
# Copyright Benard Mesander 2026
#
# Author: Matteo Perotti, Benard Mesander
#
# Derived from rvfplib. The exponent handling, sign handling and special case
# paths come from that implementation; the multiplier core was replaced with a
# bit serial loop so that no M extension is required.
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

.globl	__mulsf3

	.section .text.__mulsf3, "ax", @progbits
	.p2align 1
	.type	__mulsf3, @function

################################################################################
# routine: __mulsf3
#
# IEEE 754 single precision multiplication, using a bit serial 24x24
# shift and add multiplier so that no M extension is required.
# Subnormals are flushed to zero, rounding is to nearest with ties to even,
# and a canonical quiet NaN is returned for every invalid case.
#
# input registers:
# a0 = operand a
# a1 = operand b
#
# output registers:
# a0 = product
################################################################################

__mulsf3:
	lui	a4, 0x80000
	xor	a5, a0, a1
	and	a4, a4, a5		# final sign

	addi	a5, x0, 0xff		# exponent mask
	srli	a2, a0, 23
	and	a2, a2, a5		# exp(a)
	srli	a3, a1, 23
	and	a3, a3, a5		# exp(b)

	beq	a2, a5, .Linf_nan
	beq	a3, a5, .Linf_nan
	beqz	a2, .Lzero_denormal
	beqz	a3, .Lzero_denormal

	add	a2, a2, a3		# exp(a) + exp(b)

	# Build the two 24-bit significands, implicit 1 at bit 23.
	slli	a0, a0, 8
	srli	a0, a0, 8
	lui	t0, 0x00800
	or	a0, a0, t0		# multiplicand
	slli	a1, a1, 8
	srli	a1, a1, 8
	or	a1, a1, t0		# multiplier

	# 48-bit product accumulates with the high half in t1 and the low half
	# in a3. The multiplier always has bit 23 set, so the loop runs exactly
	# 24 times before a1 reaches zero.
	li	t1, 0
	li	a3, 0

.Lmul_loop:
	andi	t2, a1, 1
	beqz	t2, .Lmul_shift
	add	t1, t1, a0

.Lmul_shift:
	srli	a3, a3, 1
	slli	t2, t1, 31		# carry the low bit of the high half
	or	a3, a3, t2
	srli	t1, t1, 1
	srli	a1, a1, 1
	bnez	a1, .Lmul_loop

	srli	a3, a3, 8		# right align the low half into [23:0]
	addi	a2, a2, -127		# remove the doubled bias

	bgeu	t1, t0, .Lmul_shifted	# product already in [2.0, 4.0)

	# Product is in [1.0, 2.0), so shift the whole 48-bit value left by one.
	slli	t1, t1, 1
	srli	t2, a3, 23
	or	t1, t1, t2
	slli	a3, a3, 9		# drop the bit just merged into t1
	srli	a3, a3, 8
	j	.Lmul_round

.Lmul_shifted:
	addi	a2, a2, 1

.Lmul_round:
	# a2 is the final biased exponent, so 254 is still finite. A negative a2
	# wraps and is caught by the same unsigned comparison.
	addi	a5, x0, 255
	bgeu	a2, a5, .Lund_ov_flow
	beqz	a2, .Ltiny		# exponent 0 cannot encode a normal

	xor	t1, t1, t0		# clear the implicit 1
	slli	a2, a2, 23
	add	a0, a4, a2		# sign and exponent
	add	a0, a0, t1		# fraction

	# Round to nearest, ties to even, with the guard bit at 0x800000 of a3.
	bltu	a3, t0, .Lmul_done	# below half, so truncate
	addi	a0, a0, 1
	bne	a3, t0, .Lmul_done	# above half, so keep the increment
	andi	a0, a0, -2		# exact tie, so clear the low bit

.Lmul_done:
	ret

.Ltiny:
	# The true value is s * 2^-150, so the result is RNE(s/2). That reaches
	# the minimum normal only for s == 0xFFFFFF, where the halfway case
	# rounds to even. Every other subnormal result is flushed to zero.
	not	a5, t1
	slli	a5, a5, 8		# zero only if all 24 bits are set
	bnez	a5, .Lzero_denormal
	lui	a5, 0x00800
	or	a0, a4, a5		# signed minimum normal
	ret

.Lund_ov_flow:
	blt	x0, a2, .Linf		# positive exponent means overflow
	mv	a0, a4			# underflow gives a signed zero
	ret

.Lzero_denormal:
	mv	a0, a4			# signed zero
	ret

.Linf_nan:
	slli	a2, a2, 24
	slli	a3, a3, 24
	beqz	a2, .Lnan		# 0 * Inf
	beqz	a3, .Lnan		# Inf * 0
	slli	a5, a5, 24		# 0xFF000000
	slli	a3, a0, 1
	bltu	a5, a3, .Lnan		# a is NaN
	slli	a3, a1, 1
	bltu	a5, a3, .Lnan		# b is NaN

.Linf:
	lui	a0, 0x7f800
	or	a0, a0, a4		# signed infinity
	ret

.Lnan:
	lui	a0, 0x7fc00		# canonical quiet NaN
	ret

	.size	__mulsf3, .-__mulsf3
