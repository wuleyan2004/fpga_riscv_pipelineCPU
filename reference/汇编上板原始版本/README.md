# 三级流水线 CPU 上板测试

本版本包含已有整数指令、访存、分支跳转、WB → EX 数据前递、GPIO 和 UART TX。板级输入经过同步；演示程序内置于指令 ROM。

## 在 PDS 中建立工程

1. 器件选择沿用现有远程板工程的 PG2L200H / 676 引脚配置，具体封装和速度等级按平台实际器件选择。
2. 将 `board_sources.f` 列出的 13 个 Verilog 文件加入工程，顶层模块设置为 **board_top**。使用导出的 ZIP 时，添加 `rtl/` 下全部 `.v` 文件，文件清单是 `sources.f`。
3. 将 **board_top.fdc** 加入约束文件。该文件包含引脚、电气标准、27 MHz 时钟和异步外部 I/O 例外。
4. 保持 `BOARD_DEMO_DELAY_COUNT=6750000`。上板模式已设置 `BOARD_DEMO=1`，无需向工程添加 `program.hex` 或汇编文件。
5. 执行综合、布局布线，确认无未解析模块、组合环路或意外锁存器；检查约束对象全部匹配、内部建立/保持时间通过。同步寄存器间及前递路径仍必须满足 27 MHz。
6. 检查复位同步器初始值被综合保留、同步器两级均存在，并尽量相邻放置。RTL 的 `syn_preserve` 是保留提示，最终以 PDS 综合结果为准。
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
- GPIO 输出为 `0x01`，按原约束应对应 LED0 点亮。
- 串口反复收到 `4F 4B 0A`，即 `OK` 加换行。当前流水线的循环约为 0.75 秒，加上发送开销。
- 复位按下后，GPIO 清零、UART 回到空闲高电平；松开后重新执行并继续输出 `OK`。
- GPIO 按钮有两级时钟同步延迟；当前演示程序不读取按钮，也不实现按键计数/消抖。

复位会清空 PC、流水线有效位和外设状态；通用寄存器及 RAM 保留内容。演示程序会重新初始化自己使用的寄存器，复位后重启已在仿真中检查。

## 本地验证和导出

在项目根目录执行：

```sh
python3 tests/prepare_board_test.py
```

需要 Python 3、Icarus Verilog（iverilog/vvp）及 GNU RISC-V 汇编工具链。脚本检查源码清单与约束端口，运行启动/按钮同步/短复位脉冲/UART 忙时复位、完整演示重启、ROM 一致性和前递测试。
全部通过后，在 `build/board-pipeline-时间戳/` 中生成带 SHA-256 清单的 `board_pipeline.zip`，以及编译、仿真日志和 `report.md`。ZIP 中使用英文路径，包含 `rtl/`、`board_top.fdc`、`sources.f` 和此说明的副本 `README.md`。
