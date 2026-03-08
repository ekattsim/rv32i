import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadWrite

from memory_model import MemoryModel


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    return int(raw, 0)


@cocotb.test()
async def run_program(dut):
    program_elf = os.getenv("PROGRAM_ELF")
    if not program_elf:
        raise RuntimeError("PROGRAM_ELF environment variable is required")

    mem_size = _env_int("MEM_SIZE", 64 * 1024)
    tohost_addr = _env_int("TOHOST_ADDR", 0x10000000)
    uart_tx_addr = _env_int("UART_TX_ADDR", 0x10000004)
    max_cycles = _env_int("MAX_CYCLES", 200000)

    mem = MemoryModel(
        mem_size=mem_size,
        tohost_addr=tohost_addr,
        uart_tx_addr=uart_tx_addr,
    )
    mem.load_elf(program_elf)

    clock = Clock(dut.clock, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.reset.value = 1
    dut.inst.value = 0x00000013
    dut.dataRead.value = 0

    for _ in range(5):
        await RisingEdge(dut.clock)
    dut.reset.value = 0

    exit_code = None

    for cycle in range(1, max_cycles + 1):
        await ReadWrite()

        inst_addr = int(dut.instAddr.value)
        dut.inst.value = mem.read_inst_word(inst_addr)

        mem_en = int(dut.memEn.value)
        write_en = int(dut.writeEn.value)
        data_addr = int(dut.dataAddr.value)
        byte_en = int(dut.byteEn.value)

        if mem_en and not write_en:
            dut.dataRead.value = mem.read_data_word(data_addr, byte_en)
        else:
            dut.dataRead.value = 0

        await RisingEdge(dut.clock)

        mem_en = int(dut.memEn.value)
        write_en = int(dut.writeEn.value)
        if mem_en and write_en:
            event = mem.write_data(
                addr=int(dut.dataAddr.value),
                value=int(dut.dataWrite.value),
                byte_en=int(dut.byteEn.value),
            )
            if event.uart_byte is not None:
                dut._log.info("UART: %s", chr(event.uart_byte))
            if event.tohost_code is not None:
                exit_code = event.tohost_code
                break

    if exit_code is None:
        raise AssertionError(f"Timeout: no tohost write within {max_cycles} cycles")

    assert exit_code == 0, f"Program failed with code {exit_code}"
