#include <stdarg.h>

#include "../host.h"

extern char __heap_start;
extern char __stack_top;

static unsigned char *heap_ptr = (unsigned char *)&__heap_start;
static unsigned long benchmark_start_cycle;
static int time_call_count;

int dhrystone_main(void);

#ifdef main
#undef main
#endif

static unsigned long read_cycle(void) {
    unsigned long value;

    __asm__ volatile("rdcycle %0" : "=r"(value));
    return value;
}

static void uart_write_char(char c) {
    putch(c);
}

static void uart_write_string(const char *s) {
    while (*s != '\0') {
        uart_write_char(*s++);
    }
}

static int uart_write_unsigned(unsigned int value) {
    char digits[10];
    int count = 0;
    int written = 0;

    if (value == 0U) {
        uart_write_char('0');
        return 1;
    }

    while (value != 0U) {
        digits[count++] = (char)('0' + (value % 10U));
        value /= 10U;
    }

    while (count > 0) {
        uart_write_char(digits[--count]);
        written += 1;
    }

    return written;
}

static int uart_write_decimal(int value) {
    unsigned int magnitude;
    int count = 0;

    if (value < 0) {
        uart_write_char('-');
        count += 1;
        magnitude = (unsigned int)(-(value + 1)) + 1U;
    } else {
        magnitude = (unsigned int)value;
    }

    if (magnitude == 0U) {
        uart_write_char('0');
        return count + 1;
    }

    {
        char digits[10];
        int digits_count = 0;

        while (magnitude != 0U) {
            digits[digits_count++] = (char)('0' + (magnitude % 10U));
            magnitude /= 10U;
        }

        while (digits_count > 0) {
            uart_write_char(digits[--digits_count]);
            count += 1;
        }
    }

    return count;
}

int putchar(int c) {
    uart_write_char((char)c);
    return c;
}

int printf(const char *format, ...) {
    va_list args;
    int written = 0;

    va_start(args, format);

    while (*format != '\0') {
        if (*format != '%') {
            uart_write_char(*format++);
            written += 1;
            continue;
        }

        format += 1;
        while (*format >= '0' && *format <= '9') {
            format += 1;
        }

        switch (*format) {
        case 'd':
            written += uart_write_decimal(va_arg(args, int));
            break;
        case 'u':
            written += uart_write_unsigned(va_arg(args, unsigned int));
            break;
        case 'c':
            uart_write_char((char)va_arg(args, int));
            written += 1;
            break;
        case 's': {
            const char *s = va_arg(args, const char *);
            while (*s != '\0') {
                uart_write_char(*s++);
                written += 1;
            }
            break;
        }
        case '%':
            uart_write_char('%');
            written += 1;
            break;
        default:
            uart_write_char('%');
            uart_write_char(*format);
            written += 2;
            break;
        }

        if (*format != '\0') {
            format += 1;
        }
    }

    va_end(args);
    return written;
}

void *malloc(unsigned int size) {
    unsigned char *result;
    unsigned int aligned_size;
    unsigned char *next_ptr;

    aligned_size = (size + 7U) & ~7U;
    result = heap_ptr;
    next_ptr = result + aligned_size;

    if (next_ptr >= (unsigned char *)&__stack_top) {
        return 0;
    }

    heap_ptr = next_ptr;
    return result;
}

char *strcpy(char *dest, const char *src) {
    char *result = dest;

    while (*src != '\0') {
        *dest++ = *src++;
    }
    *dest = '\0';
    return result;
}

long time(long *timer) {
    unsigned long now = read_cycle();

    time_call_count += 1;
    if (time_call_count == 1) {
        benchmark_start_cycle = now;
    } else if (time_call_count == 2) {
        uart_write_string("DHRYSTONE_TOTAL_CYCLES: ");
        uart_write_unsigned((unsigned int)(now - benchmark_start_cycle));
        uart_write_char('\n');
    }

    if (timer != 0) {
        *timer = (long)now;
    }

    return (long)now;
}

int main(void) {
    dhrystone_main();
    return 0;
}
