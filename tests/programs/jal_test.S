    .section .text
    .globl _start
    .option norvc
    .option norelax

_start:
    # PC=0: ordinary instruction before the first jump.
    addi x1, x0, 11

    # PC=4: forward JAL. It must write PC+4=8 to x5 and skip x10.
    jal  x5, forward_target
    addi x10, x0, 1
forward_target:
    addi x11, x0, 1

    # PC=16: jal x0 is a pure jump. It must skip x12 and keep x0 at zero.
    jal  x0, x0_target
    addi x12, x0, 1
x0_target:
    addi x13, x0, 1

    # A finite loop that executes a backward JAL twice.
    addi x14, x0, 0
    addi x15, x0, 3
backward_loop:
    addi x14, x14, 1
    beq  x14, x15, loop_done

    # PC=44: each execution writes PC+4=48 to x6, then jumps back to PC=36.
    jal  x6, backward_loop

loop_done:
    # Completion signature. The testbench stops at the following PC.
    addi x16, x0, 123
