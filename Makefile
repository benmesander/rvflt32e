# ==============================================================================
# Makefile for rvflt32e (Compact RV32EC Single-Precision Soft-Float Library)
# Target: CH32V003 and related RV32EC / ilp32e microcontrollers
# ==============================================================================

# Toolchain configuration
CROSS_COMPILE ?= riscv64-unknown-elf-
CC            := $(CROSS_COMPILE)gcc
AR            := $(CROSS_COMPILE)ar
SIZE          := $(CROSS_COMPILE)size

# Simulator configuration - XXX fix this
SPIKE         ?= spike
PK	      ?= $(if $(PK_PATH),$(PK_PATH),/Users/ben/src/riscv-pk/build/pk)

# Assembly Library Flags (Strict RV32EC architecture & register enforcement)
# rv32e supports only the ilp32e ABI; gcc errors and clang ignores anything else.
ARCH_FLAGS    := -march=rv32ec -mabi=ilp32e
CFLAGS        := $(ARCH_FLAGS) -Os -Wall -Wextra -ffunction-sections -fdata-sections -fno-builtin -Iinclude

# Test Runner C Flags (Standard ilp32 multilib for toolchain compatibility)
TEST_CFLAGS   := -march=rv32ic -mabi=ilp32 -Os -Wall -Wextra -Iinclude
# The library is RVE-tagged, the pk-hosted harness is not. Safe only because every
# routine passes <=2 words in a0/a1, touches no stack, and uses only a0-a5/t0-t2.
LDFLAGS       := -Wl,--no-warn-mismatch

# Directories
SRC_DIR       := src
INC_DIR       := include
TEST_DIR      := tests
BUILD_DIR     := build
LIB_DIR       := lib

# Target Library Name
LIB_NAME      := librvflt32e.a
TARGET_LIB    := $(LIB_DIR)/$(LIB_NAME)

# Source and Object Files
SRCS          := $(wildcard $(SRC_DIR)/*.S)
OBJS          := $(patsubst $(SRC_DIR)/%.S, $(BUILD_DIR)/%.o, $(SRCS))

# Test Sources and Executable
TEST_SRCS     := $(wildcard $(TEST_DIR)/*.c)
TEST_OBJS     := $(patsubst $(TEST_DIR)/%.c, $(BUILD_DIR)/%.o, $(TEST_SRCS))
TEST_ELF      := $(BUILD_DIR)/test_runner.elf

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

# Compile assembly sources (.S -> .o) strictly as RV32EC
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.S | $(BUILD_DIR)
	@echo "  AS      $<"
	@$(CC) $(CFLAGS) -c $< -o $@

# Compile test C sources (.c -> .o) using standard rv32ic/ilp32
$(BUILD_DIR)/%.o: $(TEST_DIR)/%.c | $(BUILD_DIR)
	@echo "  CC      $<"
	@$(CC) $(TEST_CFLAGS) -c $< -o $@

# Link test runner executable with --no-warn-mismatch
$(TEST_ELF): $(TEST_OBJS) $(TARGET_LIB)
	@echo "  LINK    $@"
	@$(CC) $(TEST_CFLAGS) $(LDFLAGS) $^ -o $@

# Create required output directories
$(BUILD_DIR) $(LIB_DIR):
	@mkdir -p $@

# Run tests in Spike using standard RV32IC architecture
.PHONY: test
test: $(TEST_ELF)
	@echo "=== Running Spike Simulation ==="
	$(SPIKE) --isa=rv32ic $(PK) $(TEST_ELF)

# Stream host-generated TestFloat vectors into Spike stdin
OP ?= f32_add
FLAGS ?= -level 2
.PHONY: testfloat-stream
testfloat-stream: $(TEST_ELF)
	@echo "=== Streaming TestFloat ($(OP)) into Spike ==="
	testfloat_gen $(OP) $(FLAGS) | $(SPIKE) --isa=rv32ic $(PK) $(TEST_ELF)

# Disassemble built library objects for inspection
.PHONY: disasm
disasm: $(TARGET_LIB)
	$(CROSS_COMPILE)objdump -d $(TARGET_LIB) > $(BUILD_DIR)/librvflt32e.dis

# Clean build artifacts
.PHONY: clean
clean:
	@echo "  CLEAN"
	@rm -rf $(BUILD_DIR) $(LIB_DIR)

# Prevent auto-deletion of intermediate files
.PRECIOUS: $(BUILD_DIR)/%.o
