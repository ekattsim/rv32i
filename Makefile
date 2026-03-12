SHELL := /bin/zsh

MEM_SIZE ?= 64000
RAM_BASE ?= 0x00000000
TEXT_BASE ?= $(RAM_BASE)
TOHOST_ADDR ?= 0x10000000
UART_TX_ADDR ?= 0x10000004
MAX_CYCLES ?= 200000

PROG ?= sw/examples/test.c
BUILD_DIR ?= build

PROG_NAME := $(notdir $(basename $(PROG)))
ELF := $(BUILD_DIR)/$(PROG_NAME).elf
MAP := $(BUILD_DIR)/$(PROG_NAME).map

CC := riscv64-unknown-elf-gcc

MARCH := rv32i_zicsr_zicntr
MABI := ilp32

CFLAGS := -march=$(MARCH) -mabi=$(MABI) -ffreestanding -fno-builtin -Wall -Wextra
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,sw/linker.ld -Wl,-Map,$(MAP) \
	-Wl,--defsym,MEM_SIZE=$(MEM_SIZE) \
	-Wl,--defsym,RAM_BASE=$(RAM_BASE) \
	-Wl,--defsym,TEXT_BASE=$(TEXT_BASE) \
	-Wl,--defsym,TOHOST_ADDR=$(TOHOST_ADDR)

TOPLEVEL_LANG := vhdl
SIM ?= ghdl
TOPLEVEL := core
COCOTB_TEST_MODULES := test_core
VHDL_SOURCES := $(abspath hw/Core.vhd)
COMPILE_ARGS += --std=08

export PYTHONPATH := $(abspath tb)

ARCHTEST_DIR := external/riscv-arch-test
ARCHTEST_CONFIG := $(abspath archtest/config/rv32i-core/test_config.yaml)
ARCHTEST_WORKDIR := $(abspath archtest/work)
ARCHTEST_REPORT := $(ARCHTEST_WORKDIR)/reports/test_summary.json

ARCHTEST_ELF_ROOT := $(ARCHTEST_WORKDIR)/rv32i-core/elfs
ARCHTEST_JOBS := $(shell nproc)

DHRYSTONE_DIR := external/benchmark-dhrystone
DHRYSTONE_RUNTIME_DIR := sw/dhrystone
DHRYSTONE_ITERS ?= 100
DHRYSTONE_MAX_CYCLES ?= 20000000
DHRYSTONE_ELF := $(BUILD_DIR)/dhrystone.elf
DHRYSTONE_MAP := $(BUILD_DIR)/dhrystone.map
DHRYSTONE_UART_LOG := $(BUILD_DIR)/dhrystone.uart.log

DHRYSTONE_SOURCES := \
	$(DHRYSTONE_DIR)/dhry_1.c \
	$(DHRYSTONE_DIR)/dhry_2.c \
	$(DHRYSTONE_DIR)/strcmp.S \
	$(DHRYSTONE_RUNTIME_DIR)/runtime.c

DHRYSTONE_CFLAGS := $(CFLAGS) -std=gnu89 -O2 -DNOENUM -DTIME -DDHRY_ITERS=$(DHRYSTONE_ITERS) \
	-fno-common -falign-functions=4 \
	-Wno-implicit -Wno-int-conversion -Wno-return-type \
	-I$(DHRYSTONE_DIR) -I$(DHRYSTONE_RUNTIME_DIR)/include

DHRYSTONE_UPSTREAM_CFLAGS := $(DHRYSTONE_CFLAGS) -Dmain=dhrystone_main
DHRYSTONE_OBJECTS := \
	$(BUILD_DIR)/dhry_1.o \
	$(BUILD_DIR)/dhry_2.o \
	$(BUILD_DIR)/strcmp.o \
	$(BUILD_DIR)/dhrystone_runtime.o

DHRYSTONE_LDFLAGS := -nostdlib -nostartfiles -Wl,-T,sw/linker.ld -Wl,-Map,$(DHRYSTONE_MAP) \
	-Wl,--defsym,MEM_SIZE=$(MEM_SIZE) \
	-Wl,--defsym,RAM_BASE=$(RAM_BASE) \
	-Wl,--defsym,TEXT_BASE=$(TEXT_BASE) \
	-Wl,--defsym,TOHOST_ADDR=$(TOHOST_ADDR)
DHRYSTONE_LIBS := -lgcc

.PHONY: all sim sim-elf archtest-gen archtest-run archtest dhrystone-elf dhrystone-run dhrystone clean

all: sim

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ELF): sw/crt0.S sw/linker.ld $(PROG) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) sw/crt0.S $(PROG) -o $(ELF)

$(BUILD_DIR)/dhry_1.o: $(DHRYSTONE_DIR)/dhry_1.c | $(BUILD_DIR)
	$(CC) $(DHRYSTONE_UPSTREAM_CFLAGS) -c $< -o $@

$(BUILD_DIR)/dhry_2.o: $(DHRYSTONE_DIR)/dhry_2.c | $(BUILD_DIR)
	$(CC) $(DHRYSTONE_UPSTREAM_CFLAGS) -c $< -o $@

$(BUILD_DIR)/strcmp.o: $(DHRYSTONE_DIR)/strcmp.S | $(BUILD_DIR)
	$(CC) $(DHRYSTONE_CFLAGS) -c $< -o $@

$(BUILD_DIR)/dhrystone_runtime.o: $(DHRYSTONE_RUNTIME_DIR)/runtime.c | $(BUILD_DIR)
	$(CC) $(DHRYSTONE_CFLAGS) -c $< -o $@

$(DHRYSTONE_ELF): sw/crt0.S sw/linker.ld $(DHRYSTONE_OBJECTS) | $(BUILD_DIR)
	$(CC) $(DHRYSTONE_CFLAGS) $(DHRYSTONE_LDFLAGS) sw/crt0.S $(DHRYSTONE_OBJECTS) -o $(DHRYSTONE_ELF) $(DHRYSTONE_LIBS)

sim: $(ELF)
	$(MAKE) sim-elf PROGRAM_ELF=$(abspath $(ELF))

sim-elf:
	@if [ -z "$(PROGRAM_ELF)" ]; then echo "PROGRAM_ELF is required"; exit 2; fi
	PROGRAM_ELF=$(PROGRAM_ELF) \
	MEM_SIZE=$(MEM_SIZE) \
	TOHOST_ADDR=$(TOHOST_ADDR) \
	UART_TX_ADDR=$(UART_TX_ADDR) \
	MAX_CYCLES=$(MAX_CYCLES) \
	$(MAKE) -f $$(cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=$(TOPLEVEL) \
		COCOTB_TEST_MODULES=$(COCOTB_TEST_MODULES) \
		VHDL_SOURCES="$(VHDL_SOURCES)" \
		COMPILE_ARGS='$(COMPILE_ARGS)' \
		SIM_ARGS='$(SIM_ARGS)'

archtest-gen:
	CONFIG_FILES=$(ARCHTEST_CONFIG) WORKDIR=$(ARCHTEST_WORKDIR) \
	$(MAKE) -C $(ARCHTEST_DIR) --jobs $(ARCHTEST_JOBS)

archtest-run:
	uv run scripts/run_archtests.py \
		--elf-root $(ARCHTEST_ELF_ROOT) \
		--max-cycles $(MAX_CYCLES) \
		--report $(ARCHTEST_REPORT)

archtest: archtest-gen archtest-run

dhrystone-elf: $(DHRYSTONE_ELF)

dhrystone-run: $(DHRYSTONE_ELF)
	uv run --with cocotb --with pyelftools env UART_LOG_PATH=$(abspath $(DHRYSTONE_UART_LOG)) \
		$(MAKE) sim-elf PROGRAM_ELF=$(abspath $(DHRYSTONE_ELF)) MAX_CYCLES=$(DHRYSTONE_MAX_CYCLES)
	uv run scripts/dhrystone_report.py --uart-log $(DHRYSTONE_UART_LOG) --iterations $(DHRYSTONE_ITERS)

dhrystone: dhrystone-run

clean:
	rm -rf $(BUILD_DIR) sim_build __pycache__ tb/__pycache__ .pytest_cache \
		results.xml core e~core.lst e~core.o coretop e~coretop.o $(ARCHTEST_WORKDIR)
