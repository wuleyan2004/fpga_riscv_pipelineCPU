# 三级流水线 CPU 上板测试

本版本包含已有整数指令、访存、分支跳转、WB → EX 数据前递、GPIO 和 UART TX。默认执行最小 C 程序，验证 C 启动环境；CPU 指令功能未增加。板级输入经过同步，C 指令和 RAM 初始副本已内置于 RTL。

## 在 PDS 中建立工程

1. 器件选择沿用现有远程板工程的 PG2L200H / 676 引脚配置，具体封装和速度等级按平台实际器件选择。
2. 将 `board_sources.f` 列出的 13 个 Verilog 文件加入工程，顶层模块设置为 **board_top**。使用导出的 ZIP 时，添加 `rtl/` 下全部 `.v` 文件，文件清单是 `sources.f`。
3. 将 **board_top.fdc** 加入约束文件。该文件包含引脚、电气标准、27 MHz 时钟和异步外部 I/O 例外。
4. 保持顶层默认参数 **C_PROGRAM=1**。无需向 PDS 添加 hex、C 或汇编文件；本次编译后的指令和数据已在 RTL 中。`BOARD_DEMO_DELAY_COUNT` 仅用于旧汇编演示模式，对 C 模式无影响。
5. 执行综合、布局布线，确认无未解析模块、组合环路或意外锁存器；检查约束对象全部匹配、内部建立/保持时间通过。同步寄存器间及前递路径仍必须满足 27 MHz。
6. 检查复位同步器初始值和 RAM 初始化内容被综合保留、同步器两级均存在，并尽量相邻放置。RTL 的 `syn_preserve` 是保留提示，最终以 PDS 综合结果为准。
7. 生成配置文件并下载，按下、松开复位按钮，然后观察串口和 GPIO。

本机未安装 PDS；源码包通过的是本地 RTL 仿真和文件一致性检查，不包含 PDS 工程、配置流或时序通过报告。

## 引脚

沿用原 `board_top.fdc` 的映射，所有 I/O 使用 LVCMOS33 / 3.3 V。

| 端口 | 引脚 | 含义 |
|---|---|---|
| clk | D18 | 27 MHz，周期 37.037 ns |
| reset_button_n | C22 | 低有效复位按钮 |
| gpio_button_n[0] | C23 | 输入按钮 0，低有效 |
| gpio_button_n[1] | B22 | 输入按钮 1，低有效 |
| gpio_button_n[2] | A22 | 输入按钮 2，低有效 |
| gpio_button_n[3] | B20 | 输入按钮 3，低有效 |
| gpio_out[0] | A20 | GPIO 输出 bit 0 |
| gpio_out[1] | C18 | GPIO 输出 bit 1 |
| gpio_out[2] | C19 | GPIO 输出 bit 2 |
| gpio_out[3] | E18 | GPIO 输出 bit 3 |
| gpio_out[4] | A17 | GPIO 输出 bit 4 |
| gpio_out[5] | A18 | GPIO 输出 bit 5 |
| gpio_out[6] | C17 | GPIO 输出 bit 6 |
| gpio_out[7] | B17 | GPIO 输出 bit 7 |
| uart_tx_pin | AB26 | 远程 FPGA LAB 串口接收链路 |

UART 使用原工程的 AB26；约束依据是已有文件，远程板上 GPIO/LED 的实际对应关系仍需本次观察确认。

`set_false_path` 仅用于外部按钮/复位输入，以及无同步接收时钟的 LED/UART 引脚。按钮原始输入只进入同步器第一级，内部寄存器之间没有被排除时序分析。

## 下载后的预期现象

- 串口设置 **115200、8 数据位、无校验、1 停止位、无硬件流控**。
- GPIO 输出为 `0x06`，bit1、bit2 为高电平，具体灯的亮灭按板上电路极性观察。
- 每次启动串口收到一行 **`C OK: 6`** 加换行，字节为 `43 20 4F 4B 3A 20 36 0A`。程序随后进入停止循环，不连续打印。
- 打开串口后按下、松开复位按钮，应再次收到同样一行；这是验证初值恢复和 BSS 清零的重要步骤。
- 如果 C 程序检查失败，输出 `C FAIL`，GPIO 为 `0x80`。记录现象后检查 RAM 初始化和最新 RTL 是否都已加入工程。
- GPIO 按钮有两级时钟同步延迟；当前 C 程序不读取按钮，也不实现按键计数/消抖。

复位会清空 PC、流水线有效位和外设状态；通用寄存器及 RAM 保留内容。`start.S` 设置 `gp/sp`，从 RAM 保留副本恢复全局变量和字符串，清零 BSS，然后调用 `main()`。C 程序检查初值 5、零初值变量、函数调用和栈上数组，计算 5+1=6；再刻意修改全局变量。第二次复位仍须输出成功，不能依赖重新配置 FPGA 来恢复 RAM。

## C 程序和存储布局

- C 源文件：`software/c_demo/main.c`；启动和链接文件：`software/runtime/start.S`、`link.ld`。
- 指令 ROM 1 KiB，本程序使用 392 字节；RAM 1 KiB，初始化数据/字符串 24 字节，BSS 8 字节。
- RAM 运行数据在 `0x000..0x017`，BSS 在 `0x018..0x01f`，不可修改的初始副本在 `0x190..0x1a7`。
- 栈预留 `0x300..0x3ff`，初始 SP 为 `0x400`，仿真观察到最大使用 32 字节。运行地址与副本地址来自 ELF，修改 C 后以新生成的 `metadata.json` 为准。
- `software/images/`（导出包中）保存 ELF、反汇编、镜像和布局信息，便于核对；它们无需加入 PDS。

这一步是最小 C 程序验证，尚未接入 CoreMark。旧汇编程序保留为 `C_PROGRAM=0` 模式，默认上板使用 C 模式。

## 本地验证和导出

在项目根目录执行：

```sh
python3 tests/prepare_board_test.py
```

需要 Python 3、Icarus Verilog（iverilog/vvp）及本项目安装的 `riscv32-unknown-elf-gcc` 工具链。脚本先编译 C 并更新 RTL，再检查源码清单与约束端口，运行 C 串口逐位接收、全部 256 个 ROM/RAM 镜像 word、两次 C 启动、栈和全局变量、按钮同步/短复位脉冲/UART 忙时复位、旧汇编模式和前递测试。导出包中的实际 RTL 会再次运行 C 板级仿真。
全部通过后，在 `build/board-pipeline-时间戳/` 中生成带 SHA-256 清单的 `board_pipeline.zip`，以及编译、仿真日志和 `report.md`。ZIP 中使用英文路径，包含 `rtl/`、`board_top.fdc`、`sources.f`、`software/` 和此说明的副本 `README.md`。
