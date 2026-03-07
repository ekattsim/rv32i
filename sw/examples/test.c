#include "../host.h"

static volatile unsigned int buf[2];

int main(void) {
    buf[0] = 11u;
    buf[1] = 31u;

    unsigned int sum = buf[0] + buf[1];
    if (sum != 42u) {
        putch('E');
        return 1;
    }

    putch('O');
    putch('K');
    return 0;
}
