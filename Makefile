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

.PHONY: all sim sim-elf archtest-gen archtest-run archtest clean

all: sim

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ELF): sw/crt0.S sw/linker.ld $(PROG) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) sw/crt0.S $(PROG) -o $(ELF)

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

clean:
	rm -rf $(BUILD_DIR) sim_build __pycache__ tb/__pycache__ .pytest_cache \
		results.xml core e~core.lst e~core.o coretop e~coretop.o $(ARCHTEST_WORKDIR)
