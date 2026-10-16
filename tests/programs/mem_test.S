    .section .text
    .globl _start
    .option norvc
    .option norelax

_start:
    # Base address for the data RAM test area.
    addi x1, x0, 64

    # SW/LW and x0 protection.
    addi x2, x0, -1
    sw   x2, 0(x1)
    lw   x10, 0(x1)

    # Build 0x44332211 one byte at a time and read it back.
    sw   x0, 4(x1)
    addi x3, x0, 0x11
    addi x4, x0, 0x22
    addi x5, x0, 0x33
    addi x6, x0, 0x44
    sb   x3, 4(x1)
    sb   x4, 5(x1)
    sb   x5, 6(x1)
    sb   x6, 7(x1)
    lw   x11, 4(x1)
    lb   x12, 7(x1)
    lbu  x13, 7(x1)

    # Signed and unsigned byte boundary: 0x80.
    addi x7, x0, -128
    sb   x7, 5(x1)
    lb   x14, 5(x1)
    lbu  x15, 5(x1)

    # Build 0xf8000123 using the two halfword lanes.
    sw   x0, 8(x1)
    addi x8, x0, 0x123
    addi x9, x0, -2048
    sh   x8, 8(x1)
    sh   x9, 10(x1)
    lw   x16, 8(x1)
    lh   x17, 8(x1)
    lhu  x18, 8(x1)
    lh   x19, 10(x1)
    lhu  x20, 10(x1)

    # Negative S/I-type offsets and a final memory signature.
    addi x21, x1, 16
    sw   x11, -4(x21)
    lw   x22, -4(x21)

    # These instructions must leave x0 unchanged.
    lw   x0, 0(x1)
    addi x0, x0, 1

    # The testbench stops when PC reaches the byte after this instruction.
    addi x23, x0, 123

