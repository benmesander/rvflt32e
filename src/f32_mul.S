/* src/f32_mul.S - Single-Precision Floating-Point Multiplication (__mulsf3)
 * Target: RV32EC / ilp32e (CH32V003)
 *
 * Implements IEEE 754 single-precision multiplication using a software
 * 24-bit shift-and-add bit-serial multiplier (no M extension required).
 * Flushes denormals to zero, rounds to nearest-even (RNE), and returns canonical quiet NaNs.
 */

.text
.section .text.__mulsf3, "ax", @progbits
.globl __mulsf3
.type __mulsf3, @function

__mulsf3:
  lui a4, 0x80000           # Prepare sign mask (0x80000000)
  xor a5, a0, a1            # Determine final sign
  and a4, a4, a5            # Isolate final sign in a4

  # Isolate exponents and check for special cases
  addi a5, x0, 0xff         # Exponent mask (0xFF)
  srli a2, a0, 23           # Isolate exp(A)
  and a2, a2, a5
  srli a3, a1, 23           # Isolate exp(B)
  and a3, a3, a5

  beq a2, a5, inf_nan       # Jump if A is Inf or NaN
  beq a3, a5, inf_nan       # Jump if B is Inf or NaN
  beqz a2, zero_denormal    # Jump if A is zero/denormal
  beqz a3, zero_denormal    # Jump if B is zero/denormal

normal_case:
  # Add exponents together
  add a2, a2, a3           # a2 = expA + expB

  # Isolate 24-bit mantissas (bit 23 = implicit 1)
  slli a0, a0, 8           # Clear sign & exp of A
  srli a0, a0, 8           # a0 = 23-bit fraction A
  lui t0, 0x00800          # t0 = 0x800000 (implicit 1 at bit 23)
  or a0, a0, t0            # a0 = 24-bit Mantissa A

  slli a1, a1, 8           # Clear sign & exp of B
  srli a1, a1, 8           # a1 = 23-bit fraction B
  or a1, a1, t0            # a1 = 24-bit Mantissa B

  # Software 24-bit x 24-bit multiplication loop
  # Multiplicand in a0
  # Multiplier in a1 (terminates when a1 == 0 after 24 right shifts)
  # Product High in t1, Product Low in a3
  li t1, 0
  li a3, 0

mul_loop:
  andi t2, a1, 1
  beqz t2, 1f
  add t1, t1, a0           # Add multiplicand to Product High
1:
  srli a3, a3, 1           # Shift Product Low right
  slli t2, t1, 31          # Extract LSB of Product High
  or a3, a3, t2            # Insert into MSB of Product Low
  srli t1, t1, 1           # Shift Product High right
  srli a1, a1, 1           # Shift Multiplier right
  bnez a1, mul_loop        # Exactly 24 iterations until a1 == 0

  # Right-align Product Low (a3) from bits [31:8] to bits [23:0]
  srli a3, a3, 8

  # Apply exponent bias
  addi a2, a2, -127

  # Check normalization requirement (Product >= 2.0 vs < 2.0)
  bgeu t1, t0, 1f          # If t1 >= 0x800000 (bit 23 set), product in [2.0, 4.0)
  # Product in [1.0, 2.0): shift 48-bit product left by 1 bit
  slli t1, t1, 1
  srli t2, a3, 23          # Extract MSB of a3
  or t1, t1, t2            # Bring into LSB of t1
  slli a3, a3, 9           # Drop the bit just merged into t1, keeping 24 bits
  srli a3, a3, 8
  j 2f
1:
  # Product in [2.0, 4.0): increment exponent
  addi a2, a2, 1
2:

  # Check for exponent underflow or overflow. a2 is the final biased exponent,
  # so 254 is still finite; a negative a2 wraps and is caught by the unsigned test.
  addi a5, x0, 255
  bgeu a2, a5, und_ov_flow
  beqz a2, tiny            # exponent 0 cannot be encoded as a normal

  # Assemble unrounded result in a0
  xor t1, t1, t0           # Clear implicit 1 (bit 23) from t1
  slli a2, a2, 23          # Align exponent to bits [30:23]
  add a0, a4, a2           # Merge sign (a4) and exponent (a2)
  add a0, a0, t1           # Merge fraction bits [22:0]

  # Round to nearest-even (RNE) using Guard bit in a3 (0x800000)
  bltu a3, t0, exit        # If remainder < 0.5 (a3 < 0x800000), do not round up
  addi a0, a0, 1           # Round up candidate
  bne a3, t0, exit         # If remainder > 0.5, keep round up
  andi a0, a0, -2          # Tie case (remainder == 0.5): round to even LSB
exit:
  ret

tiny:
  # The true value is s * 2^-150, so the result is RNE(s/2). That reaches the
  # minimum normal only for s == 0xFFFFFF, where the halfway case rounds to
  # even; every other subnormal result is flushed to zero.
  not a5, t1
  slli a5, a5, 8           # zero only when all 24 significand bits are set
  bnez a5, zero_denormal
  lui a5, 0x00800
  or a0, a4, a5            # signed minimum normal
  ret

und_ov_flow:
  # Overflow (a2 > 0) vs Underflow (a2 <= 0)
  blt x0, a2, inf
  # Underflow: return signed zero
  mv a0, a4
  ret

zero_denormal:
  mv a0, a4                # Return signed zero
  ret

inf_nan:
  slli a2, a2, 24          # Isolate exponent of A
  slli a3, a3, 24          # Isolate exponent of B
  beqz a2, nan             # Return NaN if A is 0 or denormal (0 * Inf)
  beqz a3, nan             # Return NaN if B is 0 or denormal (Inf * 0)
  slli a5, a5, 24          # Mask 0xFF000000 for NaN check
  slli a3, a0, 1           # Clear sign of A
  bltu a5, a3, nan         # Return NaN if A is NaN
  slli a3, a1, 1           # Clear sign of B
  bltu a5, a3, nan         # Return NaN if B is NaN

inf:
  lui a0, 0x7f800          # Load Inf exponent
  or a0, a0, a4            # Apply sign
  ret

nan:
  lui a0, 0x7fc00          # Quiet NaN
  ret