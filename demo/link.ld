MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128K
}

ENTRY(_start)

SECTIONS
{
    .text : {
        *(.text.entry)
        *(.text*)
        *(.rodata*)
    } > RAM

    .htif : ALIGN(64) {
        *(.htif)
    } > RAM

    .data : {
        *(.data*)
    } > RAM

    .sdata : {
        __global_pointer$ = . + 0x800;
        *(.sdata*)
    } > RAM

    .sbss : {
        *(.sbss*)
    } > RAM

    .bss : {
        __bss_start = .;
        *(.bss*)
        __bss_end = .;
    } > RAM

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
