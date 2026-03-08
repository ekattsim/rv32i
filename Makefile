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

.PHONY: all sim clean

all: sim

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ELF): sw/crt0.S sw/linker.ld $(PROG) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) sw/crt0.S $(PROG) -o $(ELF)

sim: $(ELF)
	PROGRAM_ELF=$(abspath $(ELF)) \
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

clean:
	rm -rf $(BUILD_DIR) sim_build __pycache__ tb/__pycache__ .pytest_cache \
		results.xml core e~core.lst e~core.o coretop e~coretop.o
