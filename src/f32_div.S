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

.globl	__divsf3

	.section .text.__divsf3, "ax", @progbits
	.p2align 1
	.type	__divsf3, @function

################################################################################
# routine: __divsf3
#
# IEEE 754 single precision division, using a restoring division loop that
# produces one quotient bit per iteration and needs no M extension.
# Subnormals are flushed to zero, rounding is to nearest with ties to even,
# and a canonical quiet NaN is returned for every invalid case.
#
# input registers:
# a0 = dividend
# a1 = divisor
#
# output registers:
# a0 = quotient
################################################################################

__divsf3:
	lui	t0, 0x80000		# sign mask, 0x80000000
	li	a5, 0xff		# exponent mask
	srli	a2, a0, 23
	and	a2, a2, a5		# exp(x)
	srli	a3, a1, 23
	and	a3, a3, a5		# exp(y)
	beq	a2, a5, .Linf_nan
	beq	a3, a5, .Linf_nan
	beqz	a2, .Lzero_denormal
	beqz	a3, .Lzero_denormal

	sub	a2, a2, a3		# exp(x) - exp(y)
	xor	t2, a0, a1		# final sign

	# Build the significands as fixed point integers, implicit 1 at bit 28.
	slli	a0, a0, 9
	slli	a1, a1, 9
	lui	a3, 0x10000
	srli	a0, a0, 4
	srli	a1, a1, 4
	or	a1, a1, a3		# divisor
	or	a3, a3, a0		# dividend

	and	a0, t2, t0		# seed the result with the sign

	# Bias the exponent, and pre-shift the dividend if it is smaller than
	# the divisor so the first quotient bit is always significant.
	slt	a5, a3, a1
	sll	a3, a3, a5
	addi	a2, a2, 126		# one less, the implicit 1 adds the rest
	sub	a2, a2, a5

	lui	a5, 0x00800		# first quotient bit, at bit 23

.Ldiv_loop:
	blt	a3, a1, .Ldiv_shift
	sub	a3, a3, a1
	or	a0, a0, a5

.Ldiv_shift:
	slli	a3, a3, 1
	beqz	a3, .Ldiv_exit		# remainder is zero, division is exact
	srli	a5, a5, 1
	bnez	a5, .Ldiv_loop

.Ldiv_exit:
	li	t2, 254
	bgeu	a2, t2, .Lund_ov_flow

	slli	a2, a2, 23
	add	a0, a0, a2		# merge the exponent

	# Round to nearest, ties to even. The doubled remainder sits in a3 and
	# the divisor in a1, so they compare directly against one half.
	bltu	a3, a1, .Ldiv_done
	addi	a0, a0, 1
	bne	a3, a1, .Ldiv_done
	andi	a0, a0, -2

.Ldiv_done:
	ret

.Lund_ov_flow:
	bgtz	a2, .Lovf		# positive exponent means overflow

	# Underflow. At a final exponent of 0 the true value is q * 2^-150, so
	# the result is RNE(q/2). That reaches the minimum normal only for
	# q == 0xFFFFFF, where the halfway case rounds to even. Everything else
	# in that binade flushes to zero.
	li	t2, -1
	bne	a2, t2, .Lzero_signed
	not	t2, a0
	slli	t2, t2, 8		# zero only if all 24 bits are set
	bnez	t2, .Lzero_signed
	srli	a0, a0, 31
	slli	a0, a0, 31
	lui	t2, 0x00800
	or	a0, a0, t2		# signed minimum normal
	ret

.Lzero_signed:
	srli	a0, a0, 31
	slli	a0, a0, 31		# signed zero
	ret

.Lzero_denormal:
	# One or both operands are zero or subnormal.
	bnez	a2, .Linf		# x is non-zero, so y is zero
	beqz	a3, .Lnan		# 0 / 0

.Lzero:
	xor	a0, a0, a1
	and	a0, a0, t0		# signed zero
	ret

.Linf_nan:
	slli	a5, a5, 24		# 0xFF000000
	slli	a2, a0, 1
	bltu	a5, a2, .Lnan		# x is NaN
	slli	a3, a1, 1
	bltu	a5, a3, .Lnan		# y is NaN
	beq	a2, a3, .Lnan		# Inf / Inf
	beq	a3, a5, .Lzero		# finite / Inf

.Linf:
	xor	a0, a0, a1		# sign of the result

.Lovf:
	and	a0, a0, t0		# keep only the sign
	lui	t0, 0x7f800
	or	a0, a0, t0		# signed infinity
	ret

.Lnan:
	lui	a0, 0x7fc00		# canonical quiet NaN
	ret

	.size	__divsf3, .-__divsf3

