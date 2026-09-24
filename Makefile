# ==============================================================================
# Makefile for rvfp32e (Compact RV32EC Single-Precision Soft-Float Library)
# Target: CH32V003 and related RV32EC / ilp32e microcontrollers
# ==============================================================================

# Toolchain configuration
CROSS_COMPILE ?= riscv64-unknown-elf-
CC            := $(CROSS_COMPILE)gcc
AR            := $(CROSS_COMPILE)ar
SIZE          := $(CROSS_COMPILE)size

# Target Architecture Flags (RV32EC with 16-register ABI)
ARCH_FLAGS    := -march=rv32ec -mabi=ilp32e

# Optimization and Build Flags
# -Os                     : Optimize aggressively for code size
# -ffunction-sections     : Place each function in its own section (enables ld --gc-sections)
# -fdata-sections         : Place each data item in its own section
# -fno-builtin            : Prevent compiler from replacing calls with builtins
CFLAGS        := $(ARCH_FLAGS) -Os -Wall -Wextra -ffunction-sections -fdata-sections -fno-builtin -Iinclude

# Directories
SRC_DIR       := src
INC_DIR       := include
BUILD_DIR     := build
LIB_DIR       := lib

# Target Library Name
LIB_NAME      := librvfp32e.a
TARGET_LIB    := $(LIB_DIR)/$(LIB_NAME)

# Source and Object Files
SRCS          := $(wildcard $(SRC_DIR)/*.S)
OBJS          := $(patsubst $(SRC_DIR)/%.S, $(BUILD_DIR)/%.o, $(SRCS))

# Default Rule
.PHONY: all
all: $(TARGET_LIB)

# Create output directories and archive static library
$(TARGET_LIB): $(OBJS) | $(LIB_DIR)
	@echo "  AR      $@"
	@$(AR) rcs $@ $(OBJS)
	@echo ""
	@echo "=== Build Complete ==="
	@echo "Library: $@"
	@$(SIZE) -t $@

# Compile assembly sources (.S -> .o)
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.S | $(BUILD_DIR)
	@echo "  AS      $<"
	@$(CC) $(CFLAGS) -c $< -o $@

# Create required output directories
$(BUILD_DIR) $(LIB_DIR):
	@mkdir -p $@

# Disassemble built library objects for inspection
.PHONY: disasm
disasm: $(TARGET_LIB)
	$(CROSS_COMPILE)objdump -d $(TARGET_LIB) > $(BUILD_DIR)/librvfp32e.dis

# Clean build artifacts
.PHONY: clean
clean:
	@echo "  CLEAN"
	@rm -rf $(BUILD_DIR) $(LIB_DIR)

# Prevent auto-deletion of intermediate files
.PRECIOUS: $(BUILD_DIR)/%.o
