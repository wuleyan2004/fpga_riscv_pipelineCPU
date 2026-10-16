#include <stdint.h>

#define UART_TX (*(volatile uint8_t *)0x10000010u)
#define GPIO_OUT (*(volatile uint32_t *)0x10000000u)

/* 非零初值进入 .data，未显式初始化的变量进入 .bss。 */
volatile uint32_t initialized = 5;
volatile uint32_t result;
volatile uint32_t visits;
const char success_message[] = "C OK: 6\n";
const char failure_message[] = "C FAIL\n";

/* 禁止内联，并实际访问栈上的局部数组，验证调用/返回和栈访存。 */
__attribute__((noinline)) static uint32_t add_on_stack(uint32_t a, uint32_t b)
{
    volatile uint32_t local[2];
    local[0] = a;
    local[1] = b;
    return local[0] + local[1];
}

static void uart_puts(const char *text)
{
    /* UART 忙时硬件会暂停本次 Store，直到可以接收下一个字符。 */
    while (*text != '\0')
        UART_TX = (uint8_t)*text++;
}

int main(void)
{
    if (initialized != 5 || result != 0 || visits != 0)
        goto fail;

    result = add_on_stack(initialized, 1);
    if (result != 6)
        goto fail;

    /* 刻意改变初值和 BSS；再次按复位键时必须恢复为 5、0、0。 */
    initialized = 99;
    visits = 1;
    GPIO_OUT = result;
    uart_puts(success_message);
    return 0;

fail:
    GPIO_OUT = 0x80;
    uart_puts(failure_message);
    return 1;
}
