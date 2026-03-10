import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadWrite

from memory_model import MemoryModel


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    return int(raw, 0)


def _flush_uart_line(dut, line_bytes: bytearray) -> None:
    if not line_bytes:
        return
    text = line_bytes.decode("utf-8", errors="replace")
    dut._log.info("UART: %s", text)
    line_bytes.clear()


@cocotb.test()
async def run_program(dut):
    program_elf = os.getenv("PROGRAM_ELF")
    if not program_elf:
        raise RuntimeError("PROGRAM_ELF environment variable is required")

    mem_size = _env_int("MEM_SIZE", 64 * 1024)
    tohost_addr = _env_int("TOHOST_ADDR", 0x10000000)
    uart_tx_addr = _env_int("UART_TX_ADDR", 0x10000004)
    max_cycles = _env_int("MAX_CYCLES", 200000)
    uart_log_path = os.getenv("UART_LOG_PATH")

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
    uart_line = bytearray()
    uart_bytes = bytearray()

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
                uart_byte = event.uart_byte & 0xFF
                uart_bytes.append(uart_byte)
                if uart_byte == 0x0A:
                    _flush_uart_line(dut, uart_line)
                elif uart_byte != 0x0D:
                    uart_line.append(uart_byte)
            if event.tohost_code is not None:
                exit_code = event.tohost_code
                break

    _flush_uart_line(dut, uart_line)
    uart_text = uart_bytes.decode("utf-8", errors="replace")
    if uart_log_path:
        path = Path(uart_log_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(uart_text, encoding="utf-8")

    if exit_code is None:
        msg = f"Timeout: no tohost write within {max_cycles} cycles"
        if uart_text:
            msg += f"\nUART transcript:\n{uart_text}"
        raise AssertionError(msg)

    if exit_code != 0:
        msg = f"Program failed with code {exit_code}"
        if uart_text:
            msg += f"\nUART transcript:\n{uart_text}"
        raise AssertionError(msg)
