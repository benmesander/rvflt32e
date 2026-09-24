# rvflt32e — Outstanding Work

Items from the 2026-09-24 code review. Numbering matches the original review.

Already resolved: #1–#9 and #23–#24 (all P0 correctness), #10 (partial —
`-mabi=ilp32e`), #21 (stray `f32_conv.S~`), #22 (naming).

Verified under spike against 249,859 host-generated IEEE-754 reference checks:
**0 failures**. The same suite reports 58,029 failures on the pre-fix sources.
Strict `-march=rv32ec -mabi=ilp32e` build is 1182 bytes of `.text`.

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

- [ ] **#14 — Test coverage is effectively nil.**
  `tests/main_test.c` runs 4 add vectors. `test_f32_sub`, `test_f32_mul`,
  `test_f32_div`, `test_f32_eq`, `test_f32_lt` in `tests/test_bridge.c` are never
  called, and there is no bridge at all for the conversion routines.
  A working bare-metal spike harness already exists in `/tmp/rvtest` (host-side
  reference generator, HTIF console, linker script, `_start`) and is what proved
  #1–#9. It needs no pk and no newlib. Landing it in `tests/` is the single
  highest-value remaining task.

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
    Confirmed: `riscv64-unknown-elf-gcc -print-multi-lib` on the installed
    Homebrew toolchain offers only rv32i/rv32im/rv32iac/rv32imac with ilp32.
    Note spike's HTIF console does not acknowledge via `fromhost`; poll `tohost`
    for drain instead, or output hangs after the first character.
  - **Option B: keep pk**, keep the justified `--no-warn-mismatch`. Least effort.
    Note `riscv-pk` is not currently installed.

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
