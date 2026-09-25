.section .text.entry
.global _start
.type _start, @function

_start:
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, __stack_top

    /* Zero-initialize .bss */
    la a0, __bss_start
    la a1, __bss_end
1:  bgeu a0, a1, 2f
    sw zero, 0(a0)
    addi a0, a0, 4
    j 1b

2:  jal main
3:  j 3b

.size _start, . - _start
	
