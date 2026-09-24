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
# src/f32_conv.S - Integer and floating point conversions for rvflt32e
# Target: RV32EC / ilp32e (CH32V003)
#
# Out of range and NaN float to integer conversions follow RISC-V fcvt
# semantics: NaN and positive overflow give INT_MAX or UINT_MAX, negative
# overflow gives INT_MIN, and any negative input to __fixunssfsi gives 0.
################################################################################

.globl	__floatsisf
.globl	__floatunsisf
.globl	__fixsfsi
.globl	__fixunssfsi

	.section .text.__floatsisf, "ax", @progbits
	.p2align 1
	.type	__floatsisf, @function

################################################################################
# routine: __floatsisf
#
# Signed 32-bit integer to float, rounding to nearest with ties to even.
# A non-negative input is handed to __floatunsisf, and a negative one is
# negated and then normalized through the same shared tail, so this routine
# always pulls __floatunsisf in with it.
#
# input registers:
# a0 = signed integer
#
# output registers:
# a0 = float
################################################################################

__floatsisf:
	beqz	a0, .Lfloatsi_zero	# 0 converts to +0.0
	srli	a1, a0, 31		# sign bit
	beqz	a1, __floatunsisf
	neg	a0, a0			# magnitude of a negative input
	slli	a1, a1, 31		# sign into bit 31
	j	.Lnorm_int

.Lfloatsi_zero:
	ret

	.size	__floatsisf, .-__floatsisf

	.section .text.__floatunsisf, "ax", @progbits
	.p2align 1
	.type	__floatunsisf, @function

################################################################################
# routine: __floatunsisf
#
# Unsigned 32-bit integer to float, rounding to nearest with ties to even.
# Also holds the normalize and pack tail shared with __floatsisf.
#
# input registers:
# a0 = unsigned integer
# a1 = sign to apply, when entered at .Lnorm_int
#
# output registers:
# a0 = float
################################################################################

__floatunsisf:
	beqz	a0, .Lfloatun_zero	# 0 converts to +0.0
	li	a1, 0			# unsigned values are always positive

.Lnorm_int:
	li	a2, 158			# exponent for a value scaled to bit 31

.Lnorm_loop:
	bltz	a0, .Lpack_float	# stop once the MSB is set
	slli	a0, a0, 1
	addi	a2, a2, -1
	j	.Lnorm_loop

.Lpack_float:
	andi	a3, a0, 0xFF		# guard and sticky bits
	srli	a0, a0, 8		# significand, bit 23 = implicit 1
	addi	a2, a2, -1		# implicit 1 carries into the exponent
	slli	a2, a2, 23
	add	a0, a0, a2

	# Round to nearest, ties to even. A carry out of the fraction runs into
	# the exponent on its own, which is what we want.
	li	a4, 0x80
	bltu	a3, a4, .Lapply_isign
	bne	a3, a4, .Lround_up
	andi	a4, a0, 1		# exact tie, so round up only if odd
	beqz	a4, .Lapply_isign

.Lround_up:
	addi	a0, a0, 1

.Lapply_isign:
	or	a0, a0, a1

.Lfloatun_zero:
	ret

	.size	__floatunsisf, .-__floatunsisf

	.section .text.__fixsfsi, "ax", @progbits
	.p2align 1
	.type	__fixsfsi, @function

################################################################################
# routine: __fixsfsi
#
# Float to signed 32-bit integer, truncating toward zero.
#
# input registers:
# a0 = float
#
# output registers:
# a0 = signed integer, saturated to INT_MAX or INT_MIN when out of range
################################################################################

__fixsfsi:
	slli	a2, a0, 1		# magnitude
	lui	a3, 0xFF000
	bltu	a3, a2, .Lfix_max	# NaN
	srli	a1, a0, 31		# sign
	srli	a2, a2, 24
	addi	a2, a2, -127		# unbiased exponent
	bltz	a2, .Lfix_zero		# |x| < 1.0
	li	a3, 31
	bgtu	a2, a3, .Lfix_sat	# |x| >= 2^32, or Inf

	slli	a0, a0, 9
	srli	a0, a0, 9
	lui	a3, 0x00800
	or	a0, a0, a3		# significand, bit 23 = implicit 1
	addi	a2, a2, -23
	bltz	a2, .Lfix_shr
	sll	a0, a0, a2		# exponent <= 31 keeps this in 32 bits
	j	.Lfix_sign

.Lfix_shr:
	neg	a2, a2
	srl	a0, a0, a2

.Lfix_sign:
	lui	a3, 0x80000
	beqz	a1, .Lfix_pos
	bltu	a3, a0, .Lfix_min	# magnitude beyond 2^31
	neg	a0, a0			# -2^31 negates to itself, as required
	ret

.Lfix_pos:
	bgeu	a0, a3, .Lfix_max
	ret

.Lfix_zero:
	li	a0, 0
	ret

.Lfix_sat:
	bnez	a1, .Lfix_min

.Lfix_max:
	lui	a0, 0x80000
	addi	a0, a0, -1		# INT_MAX
	ret

.Lfix_min:
	lui	a0, 0x80000		# INT_MIN
	ret

	.size	__fixsfsi, .-__fixsfsi

	.section .text.__fixunssfsi, "ax", @progbits
	.p2align 1
	.type	__fixunssfsi, @function

################################################################################
# routine: __fixunssfsi
#
# Float to unsigned 32-bit integer, truncating toward zero. Kept separate from
# __fixsfsi so that neither routine drags the other in, and because a negative
# input has to produce 0 rather than a negated magnitude.
#
# input registers:
# a0 = float
#
# output registers:
# a0 = unsigned integer, saturated to UINT_MAX or 0 when out of range
################################################################################

__fixunssfsi:
	slli	a2, a0, 1		# magnitude
	lui	a3, 0xFF000
	bltu	a3, a2, .Lfixu_max	# NaN
	bltz	a0, .Lfixu_zero		# any negative input, including -0.0
	srli	a2, a2, 24
	addi	a2, a2, -127		# unbiased exponent
	bltz	a2, .Lfixu_zero		# x < 1.0
	li	a3, 31
	bgtu	a2, a3, .Lfixu_max	# x >= 2^32, or +Inf

	slli	a0, a0, 9
	srli	a0, a0, 9
	lui	a3, 0x00800
	or	a0, a0, a3		# significand, bit 23 = implicit 1
	addi	a2, a2, -23
	bltz	a2, .Lfixu_shr
	sll	a0, a0, a2
	ret

.Lfixu_shr:
	neg	a2, a2
	srl	a0, a0, a2
	ret

.Lfixu_zero:
	li	a0, 0
	ret

.Lfixu_max:
	li	a0, -1			# UINT_MAX
	ret

	.size	__fixunssfsi, .-__fixunssfsi
