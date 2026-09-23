# rvflt32e
Soft floating point single precision implementation for RV32E processors such as CH32V003

This libary offers GCC and Clang-compatible single-precision IEEE754 floating point support for highly constrained RISC-V processors such as the ch32v003 (48Mhz, 2K RAM, 16K ROM, 16 registers, no multiplier, etc.). 

In order to make this code feasible, the implementation is minimal. In particular:
1. Single precision only.
1. No support for subnormal numbers.
2. No support for signalling NaN.
3. Only rounding mode supported is RNE.

The code is tested with the Berkely Softfloat package. (todo: links, description)

The core algorithms are based upon the excellent [RVfplib](https://github.com/pulp-platform/RVfplib)
