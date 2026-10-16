# 三级流水线 RV32I CoreMark 移植

五份 CoreMark 算法及 coremark.h 不修改，移植文件集中在本目录。

- `core_portme.h`：RV32 类型、静态 2000 字节缓冲区、单线程、软件浮点报告。
- `core_portme.c`：易变种子、64 位 MMIO 计数器读取、时间转换和初始化/结束接口。
- `ee_printf.c`、`cvt.c`：从官方 barebones 复制；仅将串口发送适配至 `0x10000010`。
- 编译配置由 `software/build_coremark.py` 统一设置，输出 ELF/反汇编/独立 ROM 和 RAM 镜像。

在项目根目录执行 `python3 software/build_coremark.py`。
`--iterations 0`（默认）为上板自动标定；`--iterations 1 --no-embed` 为短仿真镜像。
`--run validation` 切换验证种子。`--no-embed` 不覆盖内置的上板程序。

当前为 32 KiB ROM、64 KiB RAM、4 KiB 预留栈，见 `software/runtime/coremark.ld`。
模板 printf 有 1 KiB 栈缓冲区，不能沿用最小 C 程序的 256 字节栈。
CPU 无需 M/F/D/CSR 指令，构建时核对全部机器指令 word。

短测试速度仅用于排查，不作为正式成绩。标准参数为总缓冲区 2000 字节，
性能和验证种子的 CRC 均成功、实际计时至少 10 秒，最终按赛题要求记录。
