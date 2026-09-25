# rvflt32e

A compact, high-performance soft floating-point single-precision library written in hand-optimized RISC-V assembly for RV32E targets (such as the WCH CH32V003).

This library offers GCC and Clang-compatible single-precision IEEE 754 floating-point support for highly constrained RISC-V processors (48 MHz, 2 KB RAM, 16 KB Flash, 16 registers `x0`–`x15`, no hardware multiplier or FPU).

To keep the binary footprint minimal and execution fast:
1. **Single precision only (`float`).**
2. **Flush-to-zero (FTZ):** Subnormal inputs and results are flushed to zero.
3. **No signaling NaN support:** Quiet NaNs are maintained.
4. **Rounding Mode:** Round to Nearest, Ties to Even (RNE) is the only supported mode.
5. **Zero Stack Allocation:** Operations execute strictly in registers without stack pushing or popping.

---

## Integration into Your C Program

Because `rvflt32e` implements the standard RISC-V GCC soft-float ABI routines (`__addsf3`, `__mulsf3`, `__divsf3`, etc.), **no special header files or custom API function calls are required**. 

When compiling C code without hardware floating-point support (`-march=rv32e_c`), GCC and Clang automatically emit calls to these routines whenever you perform standard C `float` arithmetic or type conversions.

### 1. Avoiding Implicit `double` Promotion

In standard C, floating-point literals without an `f` suffix (e.g., `3.14`) are treated as 64-bit `double`. Additionally, standard C promotes `float` arguments passed to variadic functions (`printf`) up to `double`.

Because `rvflt32e` only provides 32-bit single-precision routines, accidentally triggering `double` operations will cause linker errors for missing `double` symbols (e.g., `__adddf3`, `__extendsfdf2`) or pull in massive soft-double library code.

To prevent this, **always compile with these flags**:
* `-fsingle-precision-constant`: Treats floating-point constants like `3.14` as `float` rather than `double`.
* `-Wdouble-promotion`: Emits a compiler warning whenever a `float` is implicitly promoted to a `double`.

### 2. Warning Regarding `printf` and `%f`

Standard C library `printf("%f", val)` implementation should **never** be used on ultra-constrained targets like the CH32V003:
1. `printf` variadic argument rules automatically convert `float` arguments to `double`.
2. Standard `newlib` or `stdio` formatting routines for floating-point values require 5 KB to 12 KB of Flash, quickly exceeding small MCU memory limits.

**Recommended Alternatives:**
* Print floating-point values by splitting them into integer and fractional parts using integer division/modulo.
* I may implement nano floating point input/output routines if there is demand.
* Always append `f` to floating-point constants in C (e.g., `12.34f`).

### 3. C Code Example

```c
// main.c
volatile float a = 12.34f;
volatile float b = 56.78f;

int main(void) {
    // GCC automatically calls __addsf3 and __mulsf3 under the hood
    volatile float sum = a + b;
    volatile float prod = a * b;
    volatile int   truncated = (int)sum; // Calls __fixsfsi

    (void)prod;
    (void)truncated;
    return 0;
}

### 4. Compiler and Linker Flags
To integrate `librvflt32e.a` into your project build, configure your toolchain with the following flags:
1. Compilation Flags: Enforce single precision and enable section-level garbage collection:
```sh
-ffunction-sections -fdata-sections -fsingle-precision-constant -Wdouble-promotion
```
2. Linker Flags: Link `librvflt32e.a` and enable linker garbage collection (`--gc-sections`):
```sh
-L/path/to/librvflt32e/lib -lrvflt32e -Wl,--gc-sections
```
#### Complete Command Line Example:
```sh
riscv64-unknown-elf-gcc -march=rv32e_c -mabi=ilp32e -Os \
    -ffunction-sections -fdata-sections \
    -fsingle-precision-constant -Wdouble-promotion \
    -T link.ld -nostdlib \
    main.c crt0.S \
    -L../lib -lrvflt32e \
    -Wl,--gc-sections \
    -o firmware.elf
```

## Linking only what you use

Every routine is emitted into its own `.text.<name>` section, so link with
garbage collection enabled:

```
-Wl,--gc-sections
```

This matters because several routines share a translation unit. Measured cost of
pulling in a single routine, `rv32ec`/`ilp32e`, whole program including startup:

| Routine | without `--gc-sections` | with |
| --- | ---: | ---: |
| `__unordsf2` | 160 | 42 |
| `__eqsf2` | 160 | 54 |
| `__ltsf2` | 160 | 96 |
| `__floatunsisf` | 272 | 70 |
| `__fixunssfsi` | 272 | 88 |
| `__fixsfsi` | 272 | 120 |
| `__addsf3` | 296 | 296 |

There is no penalty for the single-routine objects, and linker relaxation is
unaffected. The whole library is 1182 bytes of `.text` if you use all of it.

Some routines unavoidably pull in a neighbour because they share code:

- `__subsf3` falls through into `__addsf3`.
- `__floatsisf` branches into `__floatunsisf` for the normalise and pack step.
- `__ltsf2`, `__lesf2`, `__gtsf2` and `__gesf2` share one comparison core.
- `__eqsf2`/`__nesf2` and `__unordsf2` are independent of the above.

## Benchmarking & Demo

A standalone benchmark suite is located in the `demo/` directory. It compares `librvflt32e` directly against standard libgcc soft-float routines on an RV32EC target, measuring both binary size footprint and execution cycle counts per operation.

### Prerequisites
1. **RISC-V Toolchain with** `ilp32e` **Multilib Support:**
A toolchain supporting `rv32e/ilp32e` (such as `riscv-none-elf-gcc` from xPack) is required to build against standard libgcc.
1. **Spike Simulator:**
Install the RISC-V ISA simulator (`spike`) to execute cycle count benchmarks over HTIF.

### Building and Running

```sh
cd demo

# Measure code size delta
make compare

# Run cycle count benchmarks on Spike
make run-spike
```

### Typical Results
**Target Architecture:** `rv32e_c_zicsr` | **ABI:** `ilp32e` | **Optimization:** `-Os`

### Code Size Footprint

librvflt32e achieves a **~76% reduction in code size** compared to standard `libgcc`, saving over 5.5 KB of flash—critical for resource-constrained microcontrollers like the CH32V003 (16 KB Flash).

```Plaintext
============================================================
 Code Size Comparison (Standard libgcc vs. rvflt32e)
============================================================
   text	   data	    bss	    dec	    hex	filename
   7256	     84	      0	   7340	   1cac	demo_standard.elf
   1707	     84	      0	   1791	    6ff	demo_rvflt32e.elf
```

### Cycle Count Benchmarks (mcycle on Spike)
Through bit-serial shift-and-subtract/add loops optimized specifically for 16-register RISC-V cores, floating-point division is **~4.5x faster** (191 vs. 865 cycles) and multiplication is **~1.65x faster** (253 vs. 418 cycles) compared to standard `libgcc`:

```Plaintext
>>> RUNNING STANDARD LIBGCC ON SPIKE <<<
====================================
  Floating-Point Cycle Benchmark    
====================================
  Add (+): 63 cycles/op
  Sub (-): 87 cycles/op
  Mul (*): 418 cycles/op
  Div (/): 865 cycles/op
  Int->Float: 137 cycles/op
  Float->Int: 82 cycles/op
====================================

>>> RUNNING RVFLT32E ON SPIKE <<<
====================================
  Floating-Point Cycle Benchmark    
====================================
  Add (+): 60 cycles/op
  Sub (-): 61 cycles/op
  Mul (*): 253 cycles/op
  Div (/): 191 cycles/op
  Int->Float: 189 cycles/op
  Float->Int: 153 cycles/op
====================================
```


## Testing

```sh
make test
```

This generates reference vectors on the build host using native IEEE-754
arithmetic, links a freestanding harness against the library, and runs it under
spike. The harness talks to the simulator over HTIF directly, so it needs no
proxy kernel, no newlib, and no libgcc; that in turn lets it link at the
library's real `rv32ec`/`ilp32e` target rather than a merely compatible one.

Subnormal inputs and results are excluded, since the library flushes them to
zero by design. NaN results are compared by class rather than by payload.

Increase the randomised coverage for a longer soak:

```sh
make test VEC_RANDOM=500000
```
## Attributions

The core algorithms are based upon the excellent [RVfplib](https://github.com/pulp-platform/RVfplib) . I was going to write my own, but this code was so good I decided to fork it and keep it alive as it has been archived. I also snagged some algorithms from my [rvint](https://github.com/benmesander/rvint) integer math library and modified them to be optimal for this application.

## Building on macOS

### Toolchain

The library itself only needs an assembler, so either toolchain below works for
`make all`. The `riscv-tools` tap additionally provides the simulator needed for
`make test`.

```sh
brew tap riscv-software-src/riscv
brew trust riscv-software-src/riscv      # required for third-party taps
brew install riscv-tools                 # riscv-gnu-toolchain + spike + pk
```

`riscv-tools` is a meta-formula pulling in:

| Formula | Provides |
| --- | --- |
| `riscv-gnu-toolchain` | `riscv64-unknown-elf-{gcc,as,ld,ar,objdump,size}` |
| `riscv-isa-sim` | `spike`, the reference ISA simulator |
| `riscv-pk` | `pk`, a proxy kernel (not used by this project) |

Precompiled bottles exist only up to macOS Sequoia (15). On anything newer this
builds from source and needs roughly 6.5 GB of scratch space.

Only `riscv-gnu-toolchain` and `riscv-isa-sim` are actually required. The test
harness is freestanding and drives spike over HTIF directly, so `riscv-pk` is
not needed.

If you only want to build the library and not run the tests, the smaller
homebrew-core formulae are enough:

```sh
brew install riscv64-elf-gcc             # pulls in riscv64-elf-binutils
```

Note the different tool prefix — build with
`make CROSS_COMPILE=riscv64-elf-`.

### Optional

```sh
brew install make        # GNU Make 4.x; macOS ships 3.81, which also works
brew install riscv-openocd   # only for on-chip debugging
```

### Berkeley TestFloat

Not packaged in Homebrew. Build [SoftFloat-3e and
TestFloat-3e](http://www.jhauser.us/arithmetic/TestFloat.html) from source with
the system clang; this yields `testfloat_gen` and `testfloat_ver`. Put both on
your `PATH`.

### Caveat: rv32e multilib

Stock toolchains ship no newlib or libgcc multilib for `rv32ec`/`ilp32e`;
`-print-libgcc-file-name` silently resolves to the rv64 default. The test
harness sidesteps this by linking neither, which is why it can run at the
library's true target. Anything you link against this library in firmware
should be checked the same way.

