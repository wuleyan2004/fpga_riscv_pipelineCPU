    .section .text
    .globl _start
    .option norvc
    .option norelax
_start:
    # Sentinels detect GPIO/unmapped accesses aliasing RAM.
    addi x2, x0, 0x123
    sw x2, 0(x0)
    sw x2, 4(x0)
    sw x2, 1020(x0)
    lui x1, 0x10000
    lw x3, 0(x1)       # reset output = 0

    addi x4, x0, -1
    sw x4, 0(x1)       # only low byte is saved: ff
    lw x5, 0(x1)
    lb x6, 0(x1)       # sign extension -> ffffffff
    lbu x7, 0(x1)      # zero extension -> ff

    addi x4, x0, 0x5a
    sb x4, 0(x1)
    lw x8, 0(x1)       # 5a
    addi x4, x0, 0x22
    sb x4, 1(x1)       # high-byte writes must not change output
    sb x4, 2(x1)
    sb x4, 3(x1)
    sh x4, 2(x1)
    lw x9, 0(x1)       # still 5a

    addi x4, x0, 0x123
    sh x4, 0(x1)
    lw x11, 0(x1)      # 23
    lui x4, 0x12345
    addi x4, x4, 0x678
    sw x4, 0(x1)
    lw x12, 0(x1)      # 78

    lw x17, 4(x1)      # testbench initially drives input=a5
    lbu x18, 4(x1)     # testbench changes input to 3c after first read
    sw x4, 4(x1)       # read-only input: writing is ignored
    lw x19, 4(x1)      # still 3c

    lw x20, 0(x0)
    lw x21, 4(x0)
    lw x22, 1020(x0)
    lui x23, 0x20000
    sw x4, 0(x23)      # unmapped: ignore write, complete request
    lw x24, 0(x23)     # unmapped: read zero
    addi x25, x0, 0x99
    sb x25, 8(x1)      # first address beyond GPIO window
    lw x26, 8(x1)      # unmapped: read zero
    lw x27, 0(x1)      # output still 78
    addi x28, x0, 123
