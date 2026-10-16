#include <stdint.h>
#include <string.h>

/* Compilation/linking probe; this is not a board firmware image. */
__attribute__((noinline))
uint32_t arithmetic_probe(uint32_t a, uint32_t b)
{
    return a * b + a / b + a % b;
}

__attribute__((noinline))
uint32_t toolchain_probe(uint32_t a, uint32_t b, void *dst,
                         const void *src, unsigned count)
{
    memcpy(dst, src, count);
    return arithmetic_probe(a, b);
}
