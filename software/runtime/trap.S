/* 机器态同步异常入口。保存全部通用寄存器，供 M 扩展软件模拟使用。 */
    .section .text.trap, "ax", @progbits
    .globl __trap_entry
    .type __trap_entry, @function
    .option push
    .option norvc
    .option norelax
    .align 2
__trap_entry:
    addi    sp, sp, -128
    sw      zero, 0(sp)
    sw      x1, 4(sp)
    sw      x5, 20(sp)
    addi    x5, sp, 128
    sw      x5, 8(sp)       /* 被打断程序原来的 sp */
    sw      x3, 12(sp)
    sw      x4, 16(sp)
    sw      x6, 24(sp)
    sw      x7, 28(sp)
    sw      x8, 32(sp)
    sw      x9, 36(sp)
    sw      x10, 40(sp)
    sw      x11, 44(sp)
    sw      x12, 48(sp)
    sw      x13, 52(sp)
    sw      x14, 56(sp)
    sw      x15, 60(sp)
    sw      x16, 64(sp)
    sw      x17, 68(sp)
    sw      x18, 72(sp)
    sw      x19, 76(sp)
    sw      x20, 80(sp)
    sw      x21, 84(sp)
    sw      x22, 88(sp)
    sw      x23, 92(sp)
    sw      x24, 96(sp)
    sw      x25, 100(sp)
    sw      x26, 104(sp)
    sw      x27, 108(sp)
    sw      x28, 112(sp)
    sw      x29, 116(sp)
    sw      x30, 120(sp)
    sw      x31, 124(sp)

    csrr    t0, mcause
    csrr    t1, mepc
    csrr    t2, mtval
    la      t3, __trap_record
    sw      t0, 0(t3)
    sw      t1, 4(t3)
    sw      t2, 8(t3)

    li      t3, 11
    beq     t0, t3, .Lresume_next
    li      t3, 3
    beq     t0, t3, .Lresume_next
    li      t3, 2
    bne     t0, t3, __trap_halt

    /* mtval 保存非法指令编码；函数只接受标准 M 扩展 R 型指令。 */
    mv      a0, t2
    mv      a1, sp
    call    trap_emulate_m
    beqz    a0, __trap_halt
    csrr    t1, mepc

.Lresume_next:
    addi    t1, t1, 4
    csrw    mepc, t1
    lw      x1, 4(sp)
    lw      x3, 12(sp)
    lw      x4, 16(sp)
    lw      x5, 20(sp)
    lw      x6, 24(sp)
    lw      x7, 28(sp)
    lw      x8, 32(sp)
    lw      x9, 36(sp)
    lw      x10, 40(sp)
    lw      x11, 44(sp)
    lw      x12, 48(sp)
    lw      x13, 52(sp)
    lw      x14, 56(sp)
    lw      x15, 60(sp)
    lw      x16, 64(sp)
    lw      x17, 68(sp)
    lw      x18, 72(sp)
    lw      x19, 76(sp)
    lw      x20, 80(sp)
    lw      x21, 84(sp)
    lw      x22, 88(sp)
    lw      x23, 92(sp)
    lw      x24, 96(sp)
    lw      x25, 100(sp)
    lw      x26, 104(sp)
    lw      x27, 108(sp)
    lw      x28, 112(sp)
    lw      x29, 116(sp)
    lw      x30, 120(sp)
    lw      x31, 124(sp)
    lw      x2, 8(sp)
    mret

    .globl __trap_halt
__trap_halt:
    j       __trap_halt
    .size __trap_entry, . - __trap_entry
    .option pop

    .section .bss.trap, "aw", @nobits
    .align 2
    .globl __trap_record
__trap_record:
    .space 12

    .section .note.GNU-stack, "", @progbits
