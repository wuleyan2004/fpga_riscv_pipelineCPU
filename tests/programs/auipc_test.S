    .section .text
    .globl _start
    .option norvc
    .option norelax

_start:
    # Zero immediate proves that AUIPC uses the current instruction PC.
    auipc x1, 0x00000
    auipc x2, 0x00000

    # Nonzero and boundary U-type immediates at known PCs.
    auipc x3, 0x00001
    auipc x4, 0x12345
    auipc x5, 0x80000
    auipc x6, 0xfffff

    # Writing x0 must still leave it equal to zero.
    auipc x0, 0xabcde

    # Completion signature. The testbench stops at the following PC.
    addi x7, x0, 123
