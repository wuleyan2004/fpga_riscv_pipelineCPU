# RV32I 三级流水线开发工程

这是继续修改 CPU、编译 C/CoreMark 和执行本地仿真的主工程。请从本文件所在目录运行命令。

| 路径 | 用途 |
|---|---|
| rtl/ | CPU、ROM/RAM、GPIO、UART、计时器、性能计数器和板级顶层 |
| software/ | 启动代码、链接脚本、最小 C、CoreMark 和编译脚本 |
| tests/ | 流水线、访存、前递、板级和 CoreMark 测试 |
| toolchains/ | 已安装的 riscv32-unknown-elf 工具链 |
| build/ | 当前软件 ELF、HEX、映射和反汇编，可由脚本重新生成 |
| reference/ | 仍被诊断生成脚本使用的最小 C 原始版本和汇编参考版本 |
| maintenance/ | 历史报告、整理记录、整理后检查结果 |
| board_sources.f | 本工程 16 个板级 Verilog 文件清单 |
| board_top.fdc | 27 MHz 时钟和开发板引脚约束 |

## 常用命令

```sh
source toolchains/env.sh
python3 tests/run_pipeline_forward_test.py
python3 software/build_coremark.py
python3 tests/prepare_coremark_uart_diagnostic.py --run performance
python3 tests/prepare_coremark_uart_diagnostic.py --run validation
```

后两条命令会生成带 20 ms 字符间隔的独立上板 ZIP，适合当前远程平台接收。
当前 rtl 的默认内置镜像为 CoreMark 性能诊断版（自动标定、20 ms 串口字符间隔）。
`build/coremark-performance-0-uart20ms-profile/` 保存对应 ELF、HEX 和编译参数；
重新生成命令：`python3 software/build_coremark.py --run performance --iterations 0 --uart-gap-ms 20 --profile`。
建议用 `python3 tests/prepare_coremark_uart_diagnostic.py --run performance --profile` 导出独立上板包，加入包内全部 .v、约束文件，顶层为 `board_top`。
这份镜像尚须重新执行 PDS 综合、时序检查和实物测试；原已上板包仍是基线。
修改后新包存于 build/，请核对包内 README 和 manifest，不要直接覆盖已经验证的工程。

tests/README.md 区分了已适配流水线的套件和早期单周期套件。

流水线支持机器态同步异常的 CSR 现场记录与 `MRET` 返回。复位默认 `mtvec=0x00007ffc`；启动代码初始化栈后把 ROM 内的 `__trap_entry` 写入 `mtvec`。处理程序把 `mcause/mepc/mtval` 存入 RAM 中的 `__trap_record`：ECALL/EBREAK 跳过并返回；M 扩展的八条乘除指令触发非法指令异常后由软件模拟并返回；其他非法编码、取指未对齐、外设或越界访存未对齐会记录后停机。普通 RAM 内的未对齐半字与字访存由流水线拆成一至两笔对齐访问并继续执行。
`decoder.v` 已识别 RV32I `FENCE`。当前顺序流水线会等待前一笔访存完成，因此 `FENCE` 不需要额外的数据通路操作；`FENCE.I` 属于尚未实现的 Zifencei 扩展。
`python3 tests/run_all_tests.py` 是当前流水线工程的完整 RTL 回归入口。
历史报告 ZIP 中的绝对路径是整理前的记录，保留用于追溯；新的运行日志使用本工程路径。

工程外根目录的 toolchains 是兼容符号链接，用来保持已有终端配置和 GCC 安装前缀有效；工具链实体只保存在本工程中。

## 性能计数器

`COREMARK_PROFILE=1` 时，`start_time()` 在读计时器后写 `0x10000030=1` 清零并开始计数；
`stop_time()` 写 `0x10000030=0` 停止，然后读取计时器。自动标定的每次调用都会清零，最终串口打印正式迭代区间的最后一组数。
诊断统计区间与 CoreMark 的计时器读数边界相差少量 MMIO 指令，因此两种周期数不应要求完全相等。打印发生在计时区间外。

| 地址 | 串口字段 | 含义 |
|---|---|---|
| 0x10000034 | Profile cycles | 计数器运行的时钟周期 |
| 0x10000038 | Retired instructions | 已完成的指令数 |
| 0x1000003c | Memory wait cycles | EX/WB 正等待数据存储器响应的周期 |
| 0x10000040 | RAW wait cycles | 访存未阻塞时，因数据相关而停顿的周期 |
| 0x10000044 | Branch instructions | 实际执行的条件分支数 |
| 0x10000048 | Taken branches | 条件成立的分支数 |
| 0x1000004c | Branch bubble cycles | 条件分支预测错误造成的空拍数，每次错误 1 拍 |
| 0x10000050 | Jump bubble cycles | JAL/JALR 重定向造成的空拍数，每次 1 拍 |

以上计数器为 32 位，溢出后回绕；在 27 MHz 下连续计时约 159 秒时 `Profile cycles` 首次回绕。
分支空拍和访存等待是瓶颈线索，不能简单把所有字段相加当作总周期。
诊断版增加了硬件和测量控制指令，其 CoreMark 成绩只用于分析，不应直接与之前的实物基线作正式性能比较。
