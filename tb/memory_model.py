from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from elftools.elf.elffile import ELFFile


@dataclass
class WriteEvent:
    tohost_code: Optional[int] = None
    uart_byte: Optional[int] = None


class MemoryModel:
    def __init__(
        self,
        mem_size: int,
        tohost_addr: int,
        uart_tx_addr: int,
    ) -> None:
        self.initial_mem_size = mem_size
        self.tohost_addr = tohost_addr
        self.uart_tx_addr = uart_tx_addr
        self.mem = bytearray(mem_size)

    def load_elf(self, elf_path: str) -> None:
        with open(elf_path, "rb") as f:
            elf = ELFFile(f)
            for segment in elf.iter_segments():
                if segment["p_type"] != "PT_LOAD":
                    continue

                paddr = int(segment["p_paddr"])
                data = segment.data()
                memsz = int(segment["p_memsz"])

                self._write_blob(paddr, data)

                if memsz > len(data):
                    self._write_blob(paddr + len(data), bytes(memsz - len(data)))

    def read_inst_word(self, addr: int) -> int:
        value = 0
        for i in range(4):
            value |= self._read_byte(addr + i) << (8 * i)
        return value & 0xFFFFFFFF

    def read_data_word(self, addr: int, byte_en: int) -> int:
        width = self._width_from_byte_en(byte_en)
        base = addr
        value = 0
        for i in range(width):
            value |= self._read_byte(base + i) << (8 * i)
        return value & 0xFFFFFFFF

    def write_data(self, addr: int, value: int, byte_en: int) -> WriteEvent:
        event = WriteEvent()
        width = self._width_from_byte_en(byte_en)

        if addr == self.tohost_addr:
            event.tohost_code = value & 0xFFFFFFFF
            return event

        if addr == self.uart_tx_addr:
            event.uart_byte = value & 0xFF
            return event

        for i in range(width):
            b = (value >> (8 * i)) & 0xFF
            self._write_byte(addr + i, b)

        return event

    def _width_from_byte_en(self, byte_en: int) -> int:
        if byte_en == 0x1:
            return 1
        if byte_en == 0x3:
            return 2
        if byte_en == 0xF:
            return 4
        return 0

    def _write_blob(self, addr: int, data: bytes) -> None:
        self._ensure_capacity(addr + len(data))
        for i, b in enumerate(data):
            self._write_byte(addr + i, b)

    def _ensure_capacity(self, size: int) -> None:
        if size <= len(self.mem):
            return
        self.mem.extend(b"\x00" * (size - len(self.mem)))

    def _read_byte(self, addr: int) -> int:
        if addr < 0 or addr >= len(self.mem):
            return 0
        return self.mem[addr]

    def _write_byte(self, addr: int, value: int) -> None:
        if addr < 0:
            return
        # ACT-generated tests may touch addresses beyond the initial ELF image.
        self._ensure_capacity(addr + 1)
        self.mem[addr] = value & 0xFF
