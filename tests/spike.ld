/* tests/spike.ld - Bare-metal layout for the spike harness.
 *
 * Spike's default DRAM base is 0x80000000 and it locates the HTIF mailbox by
 * looking up the tohost/fromhost symbols, which must therefore be unconditional
 * definitions rather than PROVIDE.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;

  .text : { *(.text.init) *(.text .text.*) }
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) }
  .data : { *(.data .data.* .sdata .sdata.*) }

  . = ALIGN(4);
  __bss_start = .;
  .bss : { *(.bss .bss.* .sbss .sbss.* COMMON) }
  . = ALIGN(4);
  __bss_end = .;

  . = ALIGN(8);
  .htif : { tohost = .; . += 8; fromhost = .; . += 8; }

  . = ALIGN(16);
  . += 0x10000;
  _stack_top = .;
}
