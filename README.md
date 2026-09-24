# rvflt32e
Soft floating point single precision implementation for RV32E processors such as CH32V003

This libary offers GCC and Clang-compatible single-precision IEEE754 floating point support for highly constrained RISC-V processors such as the ch32v003 (48Mhz, 2K RAM, 16K ROM, 16 registers, no multiplier, etc.). 

In order to make this code feasible, the implementation is minimal. In particular:
1. Single precision only.
1. No support for subnormal numbers.
2. No support for signalling NaN.
3. Only rounding mode supported is RNE.

The code is tested with the Berkely Softfloat package. (todo: links, description)

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

