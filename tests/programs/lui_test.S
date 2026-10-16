    .section .text
    .globl _start
    .option norvc
    .option norelax

_start:
    # Basic upper-immediate load and construction of 0x12345678.
    lui  x1, 0x12345
    addi x2, x1, 0x678

    # Boundary values for bit 31 and all-one upper immediate.
    lui  x3, 0x80000
    lui  x4, 0xfffff
    addi x4, x4, -1

    # Zero, x0 protection, and the smallest nonzero U-immediate.
    lui  x5, 0x00000
    lui  x0, 0xabcde
    lui  x6, 0x00001
    addi x7, x6, -1

    # Largest positive signed 32-bit upper value.
    lui  x8, 0x7ffff

    # Completion signature. The testbench stops at the following PC.
    addi x9, x0, 123
