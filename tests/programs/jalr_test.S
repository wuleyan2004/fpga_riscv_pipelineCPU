    .section .text
    .globl _start
    .option norvc
    .option norelax

_start:
    # Function call: JAL stores return PC=8 in x1.
    addi x10, x0, 0
    jal  x1, function_call

return_from_function:
    addi x10, x10, 1
    jal  x0, after_function_call

function_call:
    addi x11, x0, 42
    # Standard return: PC = x1, with rd=x0.
    jalr x0, 0(x1)

after_function_call:
    addi x12, x0, 1

    # x2=45 is odd. JALR must clear bit 0 and jump to PC=44.
    addi x2, x0, 45
    jalr x5, 0(x2)
    addi x13, x0, 1
    addi x14, x0, 1

odd_target:
    addi x15, x0, 1

    # Positive I-type offset: 60 + 4 = PC 64.
    addi x3, x0, 60
    jalr x6, 4(x3)
    addi x16, x0, 1
    addi x17, x0, 1

positive_offset_target:
    addi x18, x0, 1

    # Negative I-type offset: 84 - 4 = PC 80.
    addi x4, x0, 84
    jalr x7, -4(x4)
    addi x19, x0, 1

negative_offset_target:
    addi x20, x0, 1

    # Completion signature. The testbench stops at the following PC.
    addi x21, x0, 123
