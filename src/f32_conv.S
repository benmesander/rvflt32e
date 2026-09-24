/* src/f32_conv.S - Consolidated Type Conversions for rvfp32e
 * Target: RV32EC / ilp32e (CH32V003)
 *
 * GCC libgcc interface conventions for single-precision conversions:
 *   __floatsisf   : signed 32-bit int -> float (a0 -> a0)
 *   __floatunsisf : unsigned 32-bit int -> float (a0 -> a0)
 *   __fixsfsi     : float -> signed 32-bit int (a0 -> a0, truncates toward zero)
 *   __fixunssfsi   : float -> unsigned 32-bit int (a0 -> a0, truncates toward zero)
 */

    .text

/* -------------------------------------------------------------------
 * Integer to Float Conversions (__floatsisf, __floatunsisf)
 * ------------------------------------------------------------------- */
    .section .text.__floatsisf, "ax", @progbits
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
    # Mantissa setup: strip explicit MSB (bit 31), align 23-bit fraction
    slli    a0, a0, 1           # Drop implicit leading 1
    srli    a0, a0, 9           # Shift 23-bit mantissa into position [22:0]

    # Combine exponent [30:23] and mantissa [22:0]
    slli    a2, a2, 23
    or      a0, a0, a2

    # Apply sign bit [31]
    or      a0, a0, a1
1:
    ret
    .size __floatunsisf, . - __floatunsisf


/* -------------------------------------------------------------------
 * Float to Integer Conversions (__fixsfsi, __fixunssfsi)
 * ------------------------------------------------------------------- */
    .section .text.__fixsfsi, "ax", @progbits
    .globl __fixsfsi
    .globl __fixunssfsi
    .type __fixsfsi, @function
    .type __fixunssfsi, @function

__fixsfsi:
__fixunssfsi:
    # Extract sign, exponent, and mantissa
    srli    a1, a0, 31          # a1 = sign bit
    slli    a2, a0, 1
    srli    a2, a2, 24          # a2 = unbiased exponent [30:23]

    # Calculate biased exponent (exp - 127)
    addi    a2, a2, -127
    bltz    a2, .Lunderflow     # Exp < 0 -> absolute value < 1.0 -> return 0

    # Extract 23-bit fraction and restore explicit leading 1
    slli    a0, a0, 9
    srli    a0, a0, 9
    li      a3, 1
    slli    a3, a3, 23
    or      a0, a0, a3          # a0 = 24-bit mantissa (1.fraction)

    # Shift mantissa according to exponent value
    li      a3, 23
    sub     a2, a2, a3
    bltz    a2, .Lshift_right

    # Exponent >= 23: shift left
    sll     a0, a0, a2
    j       .Lapply_sign

.Lshift_right:
    # Exponent < 23: shift right
    neg     a2, a2
    srl     a0, a0, a2

.Lapply_sign:
    # Negate integer if float sign bit was set
    beqz    a1, 1f
    neg     a0, a0
1:
    ret

.Lunderflow:
    li      a0, 0
    ret

    .size __fixsfsi, . - __fixsfsi
    .size __fixunssfsi, . - __fixunssfsi
