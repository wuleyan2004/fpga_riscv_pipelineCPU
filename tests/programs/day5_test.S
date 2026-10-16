    .section .text
    .globl _start
    .option norvc
    .option norelax

    # Each result is stored as one word at byte addresses 256,260,...
    .macro save offset
    sw x3, \offset(x10)
    .endm
_start:
    addi x10, x0, 256
    addi x1, x0, 12
    addi x2, x0, 10
    and x3, x1, x2
    save 0
    or x3, x1, x2
    save 4
    xor x3, x1, x2
    save 8
    andi x3, x1, 15
    save 12
    ori x3, x1, 3
    save 16
    xori x3, x1, -1
    save 20
    andi x3, x1, -1
    save 24
    ori x3, x1, -2048
    save 28

    addi x1, x0, -8
    addi x2, x0, 2
    sll x3, x1, x2
    save 32
    srl x3, x1, x2
    save 36
    sra x3, x1, x2
    save 40
    slli x3, x1, 2
    save 44
    srli x3, x1, 2
    save 48
    srai x3, x1, 2
    save 52

    # Immediate shift boundaries: 0 and 31, bit 31 set.
    lui x1, 0x80000
    slli x3, x1, 0
    save 56
    srli x3, x1, 31
    save 60
    srai x3, x1, 31
    save 64
    addi x1, x0, 1
    slli x3, x1, 31
    save 68

    # Register shift counts use only the low five bits: 32->0,33->1.
    addi x1, x0, -8
    addi x2, x0, 32
    sll x3, x1, x2
    save 72
    srl x3, x1, x2
    save 76
    sra x3, x1, x2
    save 80
    addi x2, x0, 33
    sll x3, x1, x2
    save 84
    srl x3, x1, x2
    save 88
    sra x3, x1, x2
    save 92

    # Signed/unsigned comparison of -1 and +1.
    addi x1, x0, -1
    addi x2, x0, 1
    slt x3, x1, x2
    save 96
    sltu x3, x1, x2
    save 100
    slti x3, x1, 0
    save 104
    sltiu x3, x1, 0
    save 108
    slti x3, x0, -1
    save 112
    sltiu x3, x0, -1
    save 116
    sltiu x3, x1, -1
    save 120
    slt x3, x1, x1
    save 124
    sltu x3, x1, x1
    save 128

    # Signed extrema and unsigned ordering.
    lui x1, 0x80000
    lui x2, 0x80000
    addi x2, x2, -1
    slt x3, x1, x2
    save 132
    sltu x3, x1, x2
    save 136
    slti x3, x1, -2048
    save 140
    sltiu x3, x1, -2048
    save 144

    # Data dependency chain and ADD/SUB 32-bit wraparound.
    addi x1, x0, 5
    slli x1, x1, 3
    xori x1, x1, 15
    andi x3, x1, 31
    save 148
    lui x1, 0x80000
    addi x2, x0, -1
    add x3, x1, x2
    save 152
    sub x3, x2, x1
    save 156
    addi x3, x2, 1
    save 160

    # x0 write attempts and use of a just-loaded result.
    andi x0, x2, -1
    slli x0, x2, 31
    sltiu x0, x0, -1
    addi x3, x0, 0
    save 164
    lw x4, 0(x10)
    xori x3, x4, -1
    save 168

    # Unsupported encodings must preserve x8=77.
    addi x8, x0, 77
    .word 0x02001413 # invalid SLLI funct7
    .word 0x02005413 # invalid SRLI/SRAI funct7
    .word 0x02002433 # invalid SLT funct7
    .word 0x02003433 # invalid SLTU funct7
    addi x3, x8, 0
    save 172
    addi x9, x0, 123
