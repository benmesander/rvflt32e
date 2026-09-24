# tests/start.S - Bare-metal entry for the spike harness.
#
# Spike loads the ELF directly and communicates through the tohost/fromhost
# pair, so no proxy kernel and no C runtime are involved.
#
# This file is part of rvflt32e and is distributed under the same terms; see
# LICENSE.txt and LICENSE-EXCEPTION.txt.

    .section .text.init, "ax", @progbits
    .globl _start
_start:
    la      sp, _stack_top

    # Nothing loads .bss for a bare image, so clear it before entering C.
    la      t0, __bss_start
    la      t1, __bss_end
1:
    bgeu    t0, t1, 2f
    sw      x0, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    call    test_main

    slli    a0, a0, 1
    ori     a0, a0, 1           # HTIF exit status: (code << 1) | 1
    la      t0, tohost
    sw      a0, 0(t0)
    sw      x0, 4(t0)
3:
    j       3b
