OUTPUT_ARCH(riscv)
ENTRY(_start)

TEXT_BASE = DEFINED(TEXT_BASE) ? TEXT_BASE : 0x00000000;
RAM_BASE = DEFINED(RAM_BASE) ? RAM_BASE : TEXT_BASE;
RAM_LENGTH = DEFINED(RAM_LENGTH) ? RAM_LENGTH : 64K;
TOHOST_ADDR = DEFINED(TOHOST_ADDR) ? TOHOST_ADDR : 0x10000000;

MEMORY
{
  ram (rwx) : ORIGIN = RAM_BASE, LENGTH = RAM_LENGTH
}

SECTIONS
{
  . = TEXT_BASE;
  __text_start = .;

  .text : ALIGN(4)
  {
    KEEP(*(.init))
    *(.text .text.*)
    *(.rodata .rodata.*)
  } > ram

  __text_end = .;

  .data : ALIGN(4)
  {
    __data_start = .;
    *(.sdata .sdata.*)
    *(.data .data.*)
    __data_end = .;
  } > ram

  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > ram

  . = ALIGN(16);
  __heap_start = .;

  .stack (NOLOAD) : ALIGN(16)
  {
    . = ORIGIN(ram) + LENGTH(ram);
    __stack_top = .;
  } > ram

  __tohost_addr = TOHOST_ADDR;

  /DISCARD/ :
  {
    *(.comment)
    *(.eh_frame)
    *(.riscv.attributes)
  }
}
