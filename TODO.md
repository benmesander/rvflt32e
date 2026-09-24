# rvflt32e — Outstanding Work

Items from the 2026-09-24 code review. Numbering matches the original review.

Already resolved: #1–#12, #14, #21–#24.

Verified under spike at the library's real `rv32ec`/`ilp32e` target via
`make test`: 305,775 checks, **0 failures**. Strict build is 1182 bytes of
`.text`.

---

## P0 — Wrong results

- [x] **#1 — `__ltsf2` returned `-1` instead of `0` for the ±0 case.**
  Branch target `2f` landed on `li a0, -1`. Now routed to a zeroing path.

- [x] **#2 — No NaN handling in `f32_cmp.S`.**
  All entry points now test for NaN (magnitude > `0xFF000000`) first.
  `__eqsf2`/`__nesf2` return 1, `__ltsf2`/`__lesf2` return 1, and
  `__gtsf2`/`__gesf2` return -1, so every ordered predicate evaluates false.

- [x] **#3 — `__gtsf2` was an argument-swap of `__ltsf2`.**
  For ordered operands all four routines return the same three-way result, so
  they now share one core and differ only in the NaN constant loaded into `t0`.

- [x] **#4 — `__unordsf2` was missing.**
  Implemented and declared in `include/rvflt32e.h`. Note this was previously
  being satisfied silently by `libgcc` at link time.

- [x] **#5 — `__fixunssfsi` was aliased to `__fixsfsi`.** Now separate; negative
  inputs (including `-0.0`) return 0.

- [x] **#6 — `__fixsfsi` had no clamping or NaN/Inf handling.**
  Now saturates to `INT_MAX`/`INT_MIN` (`UINT_MAX`/0 for the unsigned form)
  following RISC-V `fcvt` semantics, including NaN → `INT_MAX`/`UINT_MAX`.

- [x] **#7 — `__floatsisf`/`__floatunsisf` truncated instead of rounding.**
  Now round-to-nearest-even, with the rounding carry propagating naturally into
  the exponent. `(float)0x7FFFFFFF` gives `0x4F000000`; `(float)16777219` gives
  `16777220`.

- [x] **#8 — `__mulsf3` overflow threshold was off by one.**
  Compared against 254 when `a2` is the final biased exponent, flushing finite
  products in 1.7e38…3.4e38 to `Inf`. Now 255. The old `a2 == 0` case also fell
  through and emitted a subnormal encoding, which the FTZ policy forbids; that
  binade is now handled explicitly (see #23).

- [x] **#9 — `__mulsf3` leaked a stale bit into the rounding decision.**
  `slli a3, a3, 1` reintroduced at bit 24 the bit already merged into the
  significand, forcing round-up and breaking tie detection. Now masked with
  `slli a3, a3, 9; srli a3, a3, 8`.

---

## P0 — New findings

- [x] **#23 — `__divsf3` (and `__mulsf3`) flushed a result that rounds up to the
  minimum normal.**
  ```
  0x3FFFFFFF / 0x7F000000  ->  was 0x00000000, expected 0x00800000
  0x00800000 * 0x3F7FFFFF  ->  was 0x00000000, expected 0x00800000
  ```
  The first diagnosis of this was wrong. It is *not* an ordering problem between
  the underflow test and the rounding step: for the div case the division is
  exact (quotient `0xFFFFFF`, remainder 0), so there is no rounding remainder to
  carry. The tie comes from the precision bit lost when the result is subnormal.

  At a final exponent of 0 the true value is `s * 2^-150` for a 24-bit
  significand `s`, so the correctly rounded result is `RNE(s / 2)`. That reaches
  the minimum normal only when `s == 0xFFFFFF`, where the halfway case rounds to
  even; every other value in that binade is subnormal and is flushed under the
  FTZ policy. Both routines now test exactly that condition, which costs three
  instructions plus a small tail and needs no general gradual-underflow support.

  Verified load-bearing: disabling just these two handlers reproduces 18
  failures (12 mul, 6 div) out of the same 249,859 checks.

- [x] **#24 — `f32_div.S` did not assemble.** The label `zero:` shadows the `zero`
  register alias for `x0`, so `beq a3, a5, zero` was parsed as a register operand.
  Renamed to `.Lzero` in `f32_div.S`, and the same latent shadow removed from
  `f32_add.S`. This is #15 manifesting as a hard build failure.

---

## P1 — Build and test infrastructure

Do the tier-1 vector table **first** — every P0 item above is detectable with it,
and it needs no external tooling.

- [x] **#14 — Test coverage.**
  `make test` now builds a freestanding harness (`tests/gen.c`,
  `tests/spike_main.c`, `tests/start.S`, `tests/spike.ld`) and runs 305,775
  checks under spike in a few seconds, covering every routine. Verified by
  mutation: reverting the #9 rounding mask and breaking the `f32_cmp.S` NaN test
  produces 11,549 failures.
  The superseded 4-vector `tests/main_test.c` was removed. `tests/test_bridge.c`
  is still unused and is kept only for the TestFloat work in #13.

- [x] **#10 — Simulation strategy resolved.**
  The harness is freestanding, so the whole test binary links at `rv32ec`/`ilp32e`
  (`Tag_RISCV_arch: rv32e2p0_c2p0_zca1p0`, no libc or libgcc). The
  `-Wl,--no-warn-mismatch` override is gone, as is the pk dependency.
  Note the toolchain ships no rv32e multilib, so `-print-libgcc-file-name`
  silently resolves to the rv64 default; anything linking libgcc at this target
  would be wrong. Avoid `/` and `%` in harness C code for that reason.

- [ ] **#13 — Berkeley TestFloat integration.**
  The old non-functional `testfloat-stream` target has been removed. `make test`
  now covers the same ground with host-generated vectors and no external
  dependencies, so TestFloat is strictly a second tier for exhaustive runs.
  Correct idiom is a three-stage pipe with the target as the filter:
  `testfloat_gen f32_add | <DUT> | testfloat_ver f32_add`.
  Four things will bite when building it:
  1. **No `scanf`/`printf` in the target.** Hand-roll hex parse/emit over
     buffered reads. Note the current harness links no libc at all, so adding a
     stdin filter means implementing the I/O path from scratch.
  2. **Exception flags.** `testfloat_ver` expects a flags byte; this library has
     no flag support. Run in a flags-ignoring mode or every case mismatches.
  3. **Subnormals mass-fail by design** (library is FTZ). Filter them or real
     bugs drown in expected failures.
  4. **`-level 2` is not feasible** — ~10⁹ cases for a binary op, and a
     bit-serial 24×24 multiply is ~150–250 instructions. Level 1 routinely.

- [x] **#11 — Hardcoded personal path.** The `PK` variable and its
  `/Users/ben/src/riscv-pk/build/pk` default are gone; the harness no longer
  uses a proxy kernel.

- [x] **#12 — Object-file namespace collision.**
  Library objects land in `build/` and harness objects in `build/tests/`, so
  `src/foo.S` and `tests/foo.c` can no longer collide. The `wildcard tests/*.c`
  glob is also gone, which matters now that `tests/` holds host-only code.

---

## P2 — Maintainability and hygiene

- [ ] **#15 — Non-local labels pollute the symbol table.**
  `normal_case`, `mul_loop`, `exit`, `inf`, `nan`, `zero`, `zero_denormal`,
  `inf_nan`, `und_ov_flow`, `sum`, `rounding`, `adjust`, `skip_add` lack a `.L`
  prefix in `f32_add.S`, `f32_div.S`, `f32_mul.S`, `mul.S`. They are `STB_LOCAL`
  so linking works, but they bloat the symbol table and make disassembly and
  refactoring hazardous. `f32_conv.S` and `f32_cmp.S` already do this correctly.

- [ ] **#16 — Dead code and inverted comments.**
  - `f32_add.S` label `7:`: `a5` is `0` there (the `beqz a5, 7f` only branches when
    `sltiu` produced 0), yet the comment claims "a5 is 1". `slli a5,a5,31` and
    `and a3,a5,a0` therefore compute zero into `a3`, which is never read —
    `inf:` uses `a4`. Two dead instructions in a ROM-constrained library.
  - `f32_add.S` `# a5 = 0xFF` — it is actually `0xFF000000`.
  - `f32_add.S` "branch if the final exponent is lower than zero" on a
    `bge a2, zero` — condition is inverted.
  - `f32_div.S` `# t0 = 0x80000` (twice) — `t0` is `0x80000000`.
  - `f32_mul.S` "Exactly 24 iterations" is true only because mantissa B always has
    bit 23 set; state that load-bearing assumption explicitly.

- [ ] **#17 — Header: bogus `__c51__` guard.**
  C51 is an 8051 compiler, irrelevant here. Worse, the closing
  `#ifdef __cplusplus } #endif` is unconditional, so if both macros were defined
  you get an unbalanced brace. Delete the `__c51__` arm.

- [ ] **#18 — Header: `#include <stdint.h>` sits inside `extern "C"`.**
  Move the system include above the linkage block.

- [ ] **#19 — `f32_mul.S` is missing its license header.**
  It is the only source without the GPL + Runtime Library Exception banner, which
  is a real distribution concern for a GPL-with-exception library. The missing
  `.size __mulsf3` part of this item is done.

- [ ] **#20 — Copyright attribution on the newer files.**
  `f32_cmp.S` and `f32_conv.S` carry "Copyright ETH Zurich 2020 / Author: Matteo
  Perotti", but their style, label convention, and algorithms differ markedly from
  the RVfplib-derived `f32_add.S`/`f32_div.S`. If written fresh, drop the ETH
  attribution; if derived, `f32_mul.S` needs it too. Worth getting right.

---

## Settled decisions

Recorded so they are not reopened.

- **Source files are not split one-routine-per-file.** `f32_cmp.S` holds seven
  routines and `f32_conv.S` four, so without `-Wl,--gc-sections` a caller pulls in
  neighbours it does not use (64–202 bytes). Splitting would recover that through
  archive-member granularity alone, but every routine already has its own
  `.text.<name>` section, gc-sections costs nothing and does not inhibit linker
  relaxation, and CH32V003 toolchains enable it by default. Keeping related code
  together wins over ~7 near-empty source files. The requirement is documented in
  the README rather than worked around in the tree.

- [ ] **Minor — `__subsf3` `.size` is computed at end of file**, so it spans
  `__addsf3` too. Should end where `__addsf3` begins.

- [ ] **Minor — other libgcc symbols.** RV32EC has no M extension, so GCC may emit
  `__divsi3`, `__udivsi3`, `__modsi3`, `__umodsi3` alongside the existing
  `__mulsi3`. Audit what a real CH32V003 build actually references.
