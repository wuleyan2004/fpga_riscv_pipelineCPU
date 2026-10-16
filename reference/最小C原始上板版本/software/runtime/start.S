/* RV32I 裸机启动程序。由 link.ld 把 _start 放到 CPU 复位地址 0。 */
    .section .text.startup.entry, "ax", @progbits
    .globl _start
    .type _start, @function

    .option push
    .option norvc
    .option norelax
_start:
    /* x3=gp：全局变量寻址基址；这里禁止链接器把初始化优化掉。 */
    la      gp, __global_pointer$

    /* x2=sp：栈从 RAM 顶端向低地址增长，保持 ABI 的 16 字节对齐。 */
    la      sp, __stack_top
    li      tp, 0

    /*
     * 当前 SoC 的 Load 只能读取 RAM，不能读取指令 ROM。
     * 装载程序时，必须将 .data 的内容预装到 RAM 的 __data_load_start。
     * 这里把保留区中的初始副本复制到变量/常量的运行地址。
     * 保留区不被 main 使用，所以再次复位也能恢复初始值。
     */
    la      t0, __data_load_start
    la      t1, __data_start
    la      t2, __data_end
.Lcopy_data:
    bgeu    t1, t2, .Lprepare_bss
    lw      t3, 0(t0)
    sw      t3, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    j       .Lcopy_data

    /* .bss：无初值或初值为 0 的静态/全局变量。 */
.Lprepare_bss:
    la      t0, __bss_start
    la      t1, __bss_end
.Lclear_bss:
    bgeu    t0, t1, .Lcall_main
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       .Lclear_bss

.Lcall_main:
    /* 也兼容 main(int argc, char **argv)：裸机没有命令行参数。 */
    li      a0, 0
    li      a1, 0
    call    main

    /* main 返回后停在这里，a0 保留返回值；不依赖 ECALL/WFI。 */
    .globl __boot_halt
__boot_halt:
    j       __boot_halt
    .size _start, . - _start
    .option pop

    .section .note.GNU-stack, "", @progbits
