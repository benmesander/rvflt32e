# ==============================================================================
# Makefile for rvflt32e (Compact RV32EC Single-Precision Soft-Float Library)
# Target: CH32V003 and related RV32EC / ilp32e microcontrollers
# ==============================================================================

# Toolchain configuration
CROSS_COMPILE ?= riscv64-unknown-elf-
CC            := $(CROSS_COMPILE)gcc
AR            := $(CROSS_COMPILE)ar
SIZE          := $(CROSS_COMPILE)size
HOSTCC        ?= cc

# Simulator configuration. The harness is freestanding and talks to spike over
# HTIF directly, so no proxy kernel is required.
SPIKE         ?= spike

# Assembly Library Flags (Strict RV32EC architecture & register enforcement)
# rv32e supports only the ilp32e ABI; gcc errors and clang ignores anything else.
ARCH_FLAGS    := -march=rv32ec -mabi=ilp32e
CFLAGS        := $(ARCH_FLAGS) -Os -Wall -Wextra -ffunction-sections -fdata-sections -fno-builtin -Iinclude

# Number of randomised cases per operation in the generated reference vectors.
VEC_RANDOM    ?= 20000

# Berkeley TestFloat. Point TESTFLOAT_BIN at the directory holding
# testfloat_gen and testfloat_ver, or put them on PATH.
TESTFLOAT_BIN ?=
TF_GEN        := $(if $(TESTFLOAT_BIN),$(TESTFLOAT_BIN)/,)testfloat_gen
TF_VER        := $(if $(TESTFLOAT_BIN),$(TESTFLOAT_BIN)/,)testfloat_ver

# Operation to exercise, and the rounding mode it needs. The library truncates
# toward zero on float to integer conversion, which TestFloat calls minMag.
OP            ?= f32_mul
TF_ROUND      := $(if $(filter f32_to_i32 f32_to_ui32,$(OP)),-rminMag,)
TF_LEVEL      ?= 1
TF_VERFLAGS   ?=

# Directories
SRC_DIR       := src
INC_DIR       := include
TEST_DIR      := tests
BUILD_DIR     := build
TEST_BUILD    := $(BUILD_DIR)/tests
LIB_DIR       := lib

# Target Library Name
LIB_NAME      := librvflt32e.a
TARGET_LIB    := $(LIB_DIR)/$(LIB_NAME)

# Source and Object Files
SRCS          := $(wildcard $(SRC_DIR)/*.S)
OBJS          := $(patsubst $(SRC_DIR)/%.S, $(BUILD_DIR)/%.o, $(SRCS))

# Test harness. Freestanding and linked without libc or libgcc, which lets it
# run at the library's real rv32ec/ilp32e target rather than a compatible one.
#
# Every generated artifact lives under a directory named for VEC_RANDOM. That
# makes a change of vector count a change of path rather than a timestamp
# comparison, which make cannot get wrong.
VEC_DIR       := $(TEST_BUILD)/vec-$(VEC_RANDOM)
TEST_CFLAGS   := $(ARCH_FLAGS) -Os -Wall -Wextra -ffreestanding \
                 -I$(VEC_DIR) -I$(INC_DIR)
TEST_LDFLAGS  := -nostdlib -nostartfiles -T $(TEST_DIR)/spike.ld \
                 -Wl,--no-warn-rwx-segments
GEN           := $(TEST_BUILD)/gen
VECTORS       := $(VEC_DIR)/vectors.h
TEST_OBJS     := $(VEC_DIR)/start.o $(VEC_DIR)/spike_main.o
TEST_ELF      := $(VEC_DIR)/spike_test.elf

# The TestFloat filter stage embeds no vectors, so it is independent of
# VEC_RANDOM and lives directly under the test build directory.
TF_ELF        := $(TEST_BUILD)/tf_test.elf

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

# Build and run the host-side reference vector generator
$(GEN): $(TEST_DIR)/gen.c | $(TEST_BUILD)
	@echo "  HOSTCC  $<"
	@$(HOSTCC) -O2 -Wall -o $@ $<

$(VECTORS): $(GEN) | $(VEC_DIR)
	@echo "  GEN     $@ ($(VEC_RANDOM) random cases/op)"
	@$(GEN) $@ $(VEC_RANDOM)

# Compile the target-side harness
$(VEC_DIR)/spike_main.o: $(TEST_DIR)/spike_main.c $(VECTORS) | $(VEC_DIR)
	@echo "  CC      $<"
	@$(CC) $(TEST_CFLAGS) -c $< -o $@

$(VEC_DIR)/start.o: $(TEST_DIR)/start.S | $(VEC_DIR)
	@echo "  AS      $<"
	@$(CC) $(ARCH_FLAGS) -c $< -o $@

$(TEST_ELF): $(TEST_OBJS) $(TARGET_LIB)
	@echo "  LINK    $@"
	@$(CC) $(ARCH_FLAGS) $(TEST_LDFLAGS) $^ -o $@

# Create required output directories
$(BUILD_DIR) $(TEST_BUILD) $(VEC_DIR) $(LIB_DIR):
	@mkdir -p $@

# Run the conformance suite under spike
.PHONY: test
test: $(TEST_ELF)
	@echo "=== Running conformance suite (spike, rv32ec) ==="
	@$(SPIKE) --isa=rv32ec $(TEST_ELF)

# Berkeley TestFloat pipeline. The filter stage runs under spike and talks to
# the host through the HTIF syscall proxy, so stdin and stdout are buffered.
$(TEST_BUILD)/tf_main.o: $(TEST_DIR)/tf_main.c | $(TEST_BUILD)
	@echo "  CC      $<"
	@$(CC) $(ARCH_FLAGS) -Os -Wall -Wextra -ffreestanding -I$(INC_DIR) -c $< -o $@

$(TF_ELF): $(TEST_BUILD)/start.o $(TEST_BUILD)/tf_main.o $(TARGET_LIB)
	@echo "  LINK    $@"
	@$(CC) $(ARCH_FLAGS) $(TEST_LDFLAGS) $^ -o $@

$(TEST_BUILD)/start.o: $(TEST_DIR)/start.S | $(TEST_BUILD)
	@echo "  AS      $<"
	@$(CC) $(ARCH_FLAGS) -c $< -o $@

.PHONY: testfloat
testfloat: $(TF_ELF)
	@echo "=== TestFloat: $(OP) (level $(TF_LEVEL)) ==="
	@$(TF_GEN) -level $(TF_LEVEL) $(TF_ROUND) -prefix $(OP) $(OP) > $(TEST_BUILD)/tf_in.txt
	@$(SPIKE) --isa=rv32ec $(TF_ELF) < $(TEST_BUILD)/tf_in.txt > $(TEST_BUILD)/tf_out.txt \
	  || { echo "$(OP): filter stage failed (unsupported operation?)"; exit 1; }
	@gen=`wc -l < $(TEST_BUILD)/tf_in.txt`; out=`wc -l < $(TEST_BUILD)/tf_out.txt`; \
	 echo "  $$out cases checked, `expr $$gen - 1 - $$out` skipped as subnormal (out of contract)"
	@$(TF_VER) $(TF_ROUND) $(TF_VERFLAGS) $(OP) < $(TEST_BUILD)/tf_out.txt

# Every operation the filter stage knows about.
TF_OPS        := f32_add f32_sub f32_mul f32_div f32_eq f32_lt f32_le \
                 i32_to_f32 ui32_to_f32 f32_to_i32 f32_to_ui32

.PHONY: testfloat-all
testfloat-all: $(TF_ELF)
	@rc=0; for op in $(TF_OPS); do \
	  $(MAKE) --no-print-directory testfloat OP=$$op TF_LEVEL=$(TF_LEVEL) || rc=1; \
	 done; exit $$rc

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
