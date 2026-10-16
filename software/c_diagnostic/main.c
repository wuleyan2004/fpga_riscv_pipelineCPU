#include <stdint.h>

#define UART_TX (*(volatile uint8_t *)0x10000010u)
#define GPIO_OUT (*(volatile uint32_t *)0x10000000u)
volatile uint32_t initialized = 5;
volatile uint32_t result;
volatile uint32_t visits;

__attribute__((noinline)) static uint32_t add_on_stack(uint32_t a)
{
    volatile uint32_t local[2];
    local[0] = a;
    local[1] = 1;
    return local[0] + local[1];
}

int main(void)
{
    uint8_t status;
    /* 字符为立即数，不依赖 RAM 中的字符串是否正确初始化。 */
    UART_TX = 'M';
    if (initialized != 5) {
        GPIO_OUT = 0x81;
        status = 'I';
    } else if (result != 0 || visits != 0) {
        GPIO_OUT = 0x82;
        status = 'Z';
    } else {
        result = add_on_stack(initialized);
        if (result == 6) {
            initialized = 99;
            visits = 1;
            GPIO_OUT = 6;
            status = 'K';
        } else {
            GPIO_OUT = 0x83;
            status = 'S';
        }
    }
    /* 持续发送，接收窗口打开得晚也能看到。每次复位重新做完整检查。 */
    for (;;) {
        UART_TX = status;
        UART_TX = '\n';
        for (uint32_t delay = 0; delay < 1000000; ++delay)
            __asm__ volatile ("" ::: "memory");
    }
}
