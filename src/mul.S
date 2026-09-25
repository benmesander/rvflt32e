################################################################################
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
	
################################################################################
# routine: __mulsi3
#
# Native word length signed/unsigned multiplication. The sign of the product
# depends only on the signs of the operands, so the magnitudes are multiplied
# and the sign is reapplied at the end.
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

.globl	__mulsi3

	.section .text.__mulsi3, "ax", @progbits
	.p2align 1
	.type	__mulsi3, @function

__mulsi3:
	xor	t0, a0, a1		# bit 31 holds the expected final sign

	# Convert a0 to |a0|
	bgez	a0, .Labs_b
	neg	a0, a0

.Labs_b:
	# Convert a1 to |a1|
	bgez	a1, .Lorder
	neg	a1, a1

.Lorder:
	# Swap so the smaller magnitude ends up in a1, since the multiplier is
	# what bounds the loop count.
	bgeu	a0, a1, .Linit
	mv	a2, a0
	mv	a0, a1
	mv	a1, a2

.Linit:
	mv	a2, a0			# multiplicand magnitude
	li	a0, 0			# product accumulator

.Lloop:
	andi	a3, a1, 1
	beqz	a3, .Lskip_add
	add	a0, a0, a2

.Lskip_add:
	srli	a1, a1, 1
	slli	a2, a2, 1
	bnez	a1, .Lloop		# stop once no multiplier bits remain

	# Apply sign correction
	bgez	t0, .Ldone
	neg	a0, a0

.Ldone:
	ret

	.size	__mulsi3, .-__mulsi3
