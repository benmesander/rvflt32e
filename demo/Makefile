# Use the new xPack toolchain prefix
CROSS_COMPILE ?= riscv-none-elf-
CC            := $(CROSS_COMPILE)gcc
SIZE          := $(CROSS_COMPILE)size
OBJDUMP       := $(CROSS_COMPILE)objdump
SPIKE         := spike

ARCH          ?= rv32e_c_zicsr
ABI           ?= ilp32e
SPIKE_ISA     ?= rv32ec

CFLAGS        := -march=$(ARCH) -mabi=$(ABI) -Os -Wall -Wextra \
                 -ffunction-sections -fdata-sections -fno-builtin
LDFLAGS       := -T link.ld -nostdlib -Wl,--gc-sections -Wl,--no-warn-rwx-segments

ROOT_DIR      := ..
LIB_A         := $(ROOT_DIR)/lib/librvflt32e.a

.PHONY: all clean compare disasm run-spike

# Default target now runs the size comparison
all: compare

$(LIB_A):
	$(MAKE) -C $(ROOT_DIR)

demo_rvflt32e.elf: main.c crt0.S link.ld $(LIB_A)
	$(CC) $(CFLAGS) $(LDFLAGS) main.c crt0.S $(LIB_A) -o $@

# Standard libgcc build restored!
demo_standard.elf: main.c crt0.S link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) main.c crt0.S -o $@ -lgcc

compare: demo_rvflt32e.elf demo_standard.elf
	@echo "============================================================"
	@echo " Code Size Comparison (Standard libgcc vs. rvflt32e)"
	@echo "============================================================"
	@$(SIZE) demo_standard.elf demo_rvflt32e.elf

# run-spike now depends on compare, so it prints sizes before running
run-spike: compare
	@echo ""
	@echo ">>> RUNNING STANDARD LIBGCC ON SPIKE <<<"
	@$(SPIKE) --isa=$(SPIKE_ISA) demo_standard.elf
	@echo ""
	@echo ">>> RUNNING RVFLT32E ON SPIKE <<<"
	@$(SPIKE) --isa=$(SPIKE_ISA) demo_rvflt32e.elf

disasm: demo_standard.elf demo_rvflt32e.elf
	$(OBJDUMP) -d demo_standard.elf > demo_standard.dis
	$(OBJDUMP) -d demo_rvflt32e.elf > demo_rvflt32e.dis

clean:
	rm -f *.o *.elf *.dis
