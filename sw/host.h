#ifndef RV32I_HOST_H
#define RV32I_HOST_H

#define TOHOST_ADDR 0x10000000u
#define UART_TX_ADDR 0x10000004u

static inline void write32(unsigned int addr, unsigned int value) {
    volatile unsigned int *ptr = (volatile unsigned int *)addr;
    *ptr = value;
}

static inline void putch(char c) {
    write32(UART_TX_ADDR, (unsigned int)(unsigned char)c);
}

#endif
