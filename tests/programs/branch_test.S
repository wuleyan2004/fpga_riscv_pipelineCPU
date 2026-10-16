    .section .text
    .globl _start
    .option norvc
    .option norelax

_start:
    # Test operands.
    addi x1, x0, 5
    addi x2, x0, 5
    addi x3, x0, 7
    addi x4, x0, -1
    addi x5, x0, 1

    # Each taken branch skips the following ADDI, so its result register stays 0.
    # Each not-taken branch executes the following ADDI, so its register becomes 1.

    # BEQ: taken and not taken.
    beq  x1, x2, beq_taken_ok
    addi x10, x0, 1
beq_taken_ok:
    beq  x1, x3, beq_not_taken_done
    addi x11, x0, 1
beq_not_taken_done:

    # BNE: taken and not taken.
    bne  x1, x3, bne_taken_ok
    addi x12, x0, 1
bne_taken_ok:
    bne  x1, x2, bne_not_taken_done
    addi x13, x0, 1
bne_not_taken_done:

    # Signed comparison: -1 < 1, while 7 < 5 is false.
    blt  x4, x5, blt_taken_ok
    addi x14, x0, 1
blt_taken_ok:
    blt  x3, x1, blt_not_taken_done
    addi x15, x0, 1
blt_not_taken_done:

    # Signed comparison: 7 >= 5, while -1 >= 1 is false.
    bge  x3, x1, bge_taken_ok
    addi x16, x0, 1
bge_taken_ok:
    bge  x4, x5, bge_not_taken_done
    addi x17, x0, 1
bge_not_taken_done:

    # Unsigned: 1 < 0xffffffff, while 0xffffffff < 1 is false.
    bltu x5, x4, bltu_taken_ok
    addi x18, x0, 1
bltu_taken_ok:
    bltu x4, x5, bltu_not_taken_done
    addi x19, x0, 1
bltu_not_taken_done:

    # Unsigned: 0xffffffff >= 1, while 1 >= 0xffffffff is false.
    bgeu x4, x5, bgeu_taken_ok
    addi x20, x0, 1
bgeu_taken_ok:
    bgeu x5, x4, bgeu_not_taken_done
    addi x21, x0, 1
bgeu_not_taken_done:

    # Backward branch: BLT is taken twice, then not taken once.
    addi x22, x0, 0
    addi x23, x0, 3
backward_loop:
    addi x22, x22, 1
    blt  x22, x23, backward_loop

    # Completion signature. The testbench stops at the following PC.
    addi x24, x0, 123
