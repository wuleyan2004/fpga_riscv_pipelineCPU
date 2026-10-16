    .section .text
    .globl _start
    .option norvc
    .option norelax
_start:
    addi x31, x0, 0x55       # poison value: any fail-path Store is observable
    addi x1, x0, 5
    addi x2, x1, 7
    add x3, x2, x2           # both ports need the same WB result
    addi x1, x1, 1
    addi x1, x1, 1           # most recent writer wins
    add x4, x1, x1
    addi x0, x0, 99
    addi x5, x0, 2           # x0 must not receive forwarded data
    addi x0, x0, 0           # legal no-op must not write/forward x31
    addi x29, x31, 1

    # All six comparisons, with the immediately produced operand in rs1.
    # The old register value would select the wrong path in each case.
    addi x6, x0, 1
    beq x6, x0, fail
    addi x6, x0, 0
    bne x6, x0, fail
    addi x6, x0, -1
    bge x6, x0, fail
    addi x6, x0, 1
    blt x6, x0, fail
    addi x6, x0, -1
    bltu x6, x1, fail
    addi x6, x0, 0
    bgeu x6, x1, fail

    # Repeat with the immediately produced operand in rs2.
    addi x6, x0, 1
    beq x0, x6, fail
    addi x6, x0, 0
    bne x0, x6, fail
    addi x6, x0, 1
    bge x0, x6, fail
    addi x6, x0, -1
    blt x0, x6, fail
    addi x6, x0, 0
    bltu x1, x6, fail
    addi x6, x0, -1
    bgeu x1, x6, fail

    # Taken comparisons flush the Store on the wrong path.
    addi x6, x0, 0
    beq x6, x0, 1f
    sw x31, 12(x0)
    j fail
1:  addi x6, x0, 1
    bne x6, x0, 2f
    sw x31, 12(x0)
    j fail
2:  addi x6, x0, -1
    blt x6, x0, 3f
    sw x31, 12(x0)
    j fail
3:  addi x6, x0, 1
    bge x6, x0, 4f
    sw x31, 12(x0)
    j fail
4:  addi x6, x0, -1
    addi x6, x0, 0
    bltu x6, x1, 5f
    sw x31, 12(x0)
    j fail
5:  addi x6, x0, -1
    bgeu x6, x1, 6f
    sw x31, 12(x0)
    j fail

6:  addi x10, x0, 64
    sw x4, 0(x10)
    lw x11, 0(x10)
    addi x11, x11, 1         # Load -> arithmetic
    addi x12, x0, 1
    lw x12, 4(x10)          # initialized RAM word is zero
    bne x12, x0, fail        # Load -> branch rs1, old value would be taken
    addi x12, x0, 0
    lw x12, 0(x10)
    beq x0, x12, fail        # Load -> branch rs2, old value would be taken

    # AUIPC -> ADDI -> Store data -> Load -> JALR address.
    auipc x13, 0
    addi x13, x13, 24
    sw x13, 8(x10)
    lw x14, 8(x10)
    jalr x15, 0(x14)
    sw x31, 12(x10)          # flushed
load_target:
    jal x16, jump_target
    sw x31, 12(x10)          # flushed
jump_target:
    addi x17, x16, 1
    sw x15, 4(x0)
    sw x17, 8(x0)
    addi x30, x0, 123
    sw x30, 0(x0)            # success signature
done:
    j done
fail:
    sw x31, 0(x0)
    j fail
