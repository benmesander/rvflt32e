# rvflt32e — Outstanding Work

Items from the 2026-09-24 code review. Numbering matches the original review.

Already resolved: #10 (partial — `-mabi=ilp32e`), #21 (stray `f32_conv.S~`), #22 (naming).

---

## P0 — Wrong results

These produce incorrect floating-point values or violate the libgcc ABI contract.
All are reachable with a handful of hand-picked vectors.

- [ ] **#1 — `__ltsf2` returns `-1` instead of `0` for the ±0 case.**
  `src/f32_cmp.S`: `beqz a2, 2f` targets the `2:` label, which is `li a0, -1; ret`.
  Result: `__ltsf2(0.0f, -0.0f)` reports `0.0 < -0.0`, and every `0.0 < 0.0`
  comparison in user code evaluates true. Needs a branch target that zeroes `a0`.

- [ ] **#2 — No NaN handling anywhere in `f32_cmp.S`.**
  All six entry points ignore NaN. Required libgcc behaviour:
  - `__eqsf2`/`__nesf2` must return **non-zero** if either operand is NaN.
    Currently `sub a0, a0, a1` on two identical NaN patterns returns `0`,
    so `NaN == NaN` is true.
  - `__ltsf2`/`__lesf2` must return a **positive** value when unordered.
  - `__gtsf2`/`__gesf2` must return a **negative** value when unordered.

- [ ] **#3 — `__gtsf2` cannot be an argument-swap of `__ltsf2`.**
  The swap is correct for ordered operands but has inverted polarity for
  unordered ones (`lt` needs positive for NaN, `gt` needs negative). Once NaN
  handling lands, `__gtsf2`/`__gesf2` need their own NaN branch or a carefully
  signed negation of a shared ordered-compare core.

- [ ] **#4 — `__unordsf2` is missing entirely.**
  GCC emits it for `isunordered()` and for `<`/`>` on possibly-NaN operands.
  Neither implemented nor declared in `include/rvflt32e.h`. Link failures will
  only surface in downstream firmware, not here.

- [ ] **#5 — `__fixunssfsi` is aliased to `__fixsfsi`.**
  The shared body applies the sign via `neg`. For negative input `__fixunssfsi`
  must return `0`; it currently returns a wrapped value. Needs to be split.

- [ ] **#6 — `__fixsfsi` has no range clamping and no NaN/Inf handling.**
  `sll a0, a0, a2` uses only the low 5 bits of the shift amount on RV32, so any
  input with |x| ≥ 2³¹ silently wraps instead of saturating to `INT_MAX`/`INT_MIN`.
  Inf and NaN take the same path. Downstream code often uses the result as an
  index or length, so this is a robustness concern too.

- [ ] **#7 — `__floatsisf` / `__floatunsisf` truncate instead of rounding.**
  `slli a0,a0,1; srli a0,a0,9` drops the low bits with no round-to-nearest-even.
  `(float)0x7FFFFFFF` yields `0x4EFFFFFF` instead of `0x4F000000`;
  `(float)16777219` yields `16777218` instead of `16777220`.
  RNE is a stated goal, so this is a spec violation, not a documented limitation.

- [ ] **#8 — `__mulsf3` overflow threshold is off by one.**
  `src/f32_mul.S`: `addi a5,x0,254; bgeu a2,a5,und_ov_flow`. Unlike `f32_add.S`
  and `f32_div.S`, `a2` here is the **final** biased exponent (it is `slli`'d by 23
  and added directly). Biased exponent 254 is the largest *finite* exponent —
  `FLT_MAX` is `0x7F7FFFFF`. Every product landing in roughly 1.7e38…3.4e38 is
  wrongly flushed to `Inf`. Compare against 255.

- [ ] **#9 — `__mulsf3` leaks a stale bit into the rounding decision.**
  After the normalising left shift, bit 23 of `a3` has already been consumed into
  the significand but reappears at position 24, because `slli a3,a3,1` is not
  masked. The subsequent `bltu a3,t0` then always decides "round up" and the tie
  check `bne a3,t0` never matches. A remainder of exactly `0x800000` pre-shift has
  a true remainder of 0 post-shift and must not round up, but does.
  Fix: `slli a3,a3,9; srli a3,a3,8` before the rounding compare.

---

## P1 — Build and test infrastructure

Do the tier-1 vector table **first** — every P0 item above is detectable with it,
and it needs no external tooling.

- [ ] **#14 — Test coverage is effectively nil.**
  `tests/main_test.c` runs 4 add vectors. `test_f32_sub`, `test_f32_mul`,
  `test_f32_div`, `test_f32_eq`, `test_f32_lt` in `tests/test_bridge.c` are never
  called, and there is no bridge at all for the conversion routines.
  Build a tier-1 table covering all routines plus edge cases: ±0, ±Inf, NaN,
  `FLT_MAX`, subnormal inputs, `INT_MIN`, 2³¹, and exponent-254 products.

- [ ] **#10 (remainder) — Decide the simulation strategy.**
  `-mabi=ilp32e` is now correct and the library objects are properly RVE-tagged
  (`Flags: 0x9, RVC, RVE`). What remains is the test link: an RVE library into a
  non-RVE rv32ic/ilp32 harness, silenced by `-Wl,--no-warn-mismatch`.
  Safe *today* only because every routine passes ≤2 words in `a0`/`a1`, touches no
  stack, and uses only `a0`–`a5`/`t0`–`t2`. Two options:
  - **Option A (recommended): bare-metal spike, no pk.** Spike runs a bare ELF
    that exports `tohost`/`fromhost`. Needs a ~20-line `_start`, HTIF
    `getchar`/`putchar`, and a linker script at `0x80000000`. Lets you build
    everything `rv32ec/ilp32e` and drop `--no-warn-mismatch`. Critically, it
    avoids needing an rv32e newlib multilib, which the stock toolchains do not ship.
  - **Option B: keep pk**, keep the justified `--no-warn-mismatch`. Least effort.

- [ ] **#13 — `testfloat-stream` target is non-functional.**
  It pipes `testfloat_gen` into the ELF, but `main_test.c` never reads stdin.
  Correct TestFloat idiom is a three-stage pipe with the target as the filter:
  `testfloat_gen f32_add | <DUT> | testfloat_ver f32_add`.
  Four things will bite when building it:
  1. **No `scanf`/`printf` in the target.** Under pk each stdio op is an HTIF trap;
     it dominates runtime and drags ~10 KB of newlib into a 16 KB-budget library.
     Hand-roll hex parse/emit over buffered `read()`/`write()`.
  2. **Exception flags.** `testfloat_ver` expects a flags byte; this library has no
     flag support. Run in a flags-ignoring mode or every case mismatches.
  3. **Subnormals mass-fail by design** (library is FTZ). Filter them or real bugs
     drown in expected failures.
  4. **`-level 2` is not feasible** — ~10⁹ cases for a binary op, and a bit-serial
     24×24 multiply is ~150–250 instructions. Use level 1 routinely.

- [ ] **#11 — Hardcoded personal path.**
  `Makefile` defaults `PK` to `/Users/ben/src/riscv-pk/build/pk`. Default to
  something discoverable on `PATH`, or fail with a clear message.

- [ ] **#12 — Object-file namespace collision.**
  Both `src/%.S` and `tests/%.c` map to `$(BUILD_DIR)/%.o`. A future
  `tests/mul.c` would silently collide with `src/mul.S`. Split into
  `$(BUILD_DIR)/src/` and `$(BUILD_DIR)/tests/`.

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

- [ ] **#19 — `f32_mul.S` is missing its license header and `.size` directive.**
  It is the only source without the GPL + Runtime Library Exception banner, and
  has no `.size __mulsf3, . - __mulsf3`. The missing banner is a real distribution
  concern for a GPL-with-exception library.

- [ ] **#20 — Copyright attribution on the newer files.**
  `f32_cmp.S` and `f32_conv.S` carry "Copyright ETH Zurich 2020 / Author: Matteo
  Perotti", but their style, label convention, and algorithms differ markedly from
  the RVfplib-derived `f32_add.S`/`f32_div.S`. If written fresh, drop the ETH
  attribution; if derived, `f32_mul.S` needs it too. Worth getting right.

- [ ] **Minor — `__subsf3` `.size` is computed at end of file**, so it spans
  `__addsf3` too. Should end where `__addsf3` begins.

- [ ] **Minor — other libgcc symbols.** RV32EC has no M extension, so GCC may emit
  `__divsi3`, `__udivsi3`, `__modsi3`, `__umodsi3` alongside the existing
  `__mulsi3`. Audit what a real CH32V003 build actually references.
