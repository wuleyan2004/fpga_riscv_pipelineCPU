# 当前 SoC 的 C 启动文件

`start.S` 是 CPU 从 PC=0 开始执行的程序：设置 `gp`、16 字节对齐的
`sp`，复制变量/常量初始值，清零 `.bss`，调用 `main()`；返回后进入
`__boot_halt` 循环，`a0` 保留返回值。

`link.ld` 对应当前硬件，指令 ROM 与数据 RAM 各 1 KiB，两个独立
接口都从地址 0 开始。RAM 顶部 `0x300..0x3ff` 预留为 256 字节栈，
初始 `sp=0x400`，栈向低地址增长。

## 初始化方式

本 SoC 的数据接口只能读取 RAM/GPIO/UART，不能读取指令 ROM。
因此 `.rodata`（字符串和常量表）与 `.data`（非零初值变量）合并放在
RAM 中。加载程序时，必须将它们的初始副本装到 RAM 的
`__data_load_start..__data_load_end`，启动程序再复制到
`__data_start..__data_end` 的运行位置。

副本所在的 `.ram_init` 区域不供 C 变量或栈使用，因此 CPU 再次复位
也能重新恢复初值。`.bss` 每次启动都会清零。

链接器中的 VMA 表示运行地址，LMA 表示预装地址。初始副本安排在
运行数据与指令 ELF 装载地址范围之后；这个最小布局会占用额外的
RAM 空隙。容量不足会导致链接报错，不能直接用当前 1 KiB 配置
运行 CoreMark。以后调整布局/容量时，需同时修改硬件与镜像生成逻辑。

当前 `board_top` 默认 `C_PROGRAM=1`，已经接入最小 C 程序。
`software/build_c_demo.py` 分别生成 ROM/RAM 镜像，并把指令和 RAM
初始副本写入 RTL 的标记区域。RAM 初始化只在 FPGA 配置时执行，
按钮复位后的复制与清零仍由 `start.S` 完成。

修改 `software/c_demo/main.c` 后，在项目根目录运行：

```sh
python3 software/build_c_demo.py
python3 tests/run_board_c_test.py
```

输出在 `build/c-demo/`：`main.elf`、`main.map`、`main.dis`、
`c_program.hex`、`c_data.hex` 和布局信息 `metadata.json`。
生成器更新 `源代码/instruction_rom.v` 和 `源代码/sync_data_ram.v`；
这两份 RTL 中的自动生成区域应通过脚本更新。随后重新进行 FPGA
综合、布局布线及下载，板上才会运行修改后的 C 程序。

## 编译

在项目根目录准备自己的 `main.c`，然后执行：

```sh
source '/Users/wuleyan/Desktop/FPGA大赛/toolchains/env.sh'
mkdir -p build/c-program
riscv32-unknown-elf-gcc \
  -march=rv32i -mabi=ilp32 -Os -ffreestanding -fno-builtin \
  -fno-pic -fno-pie -fno-stack-protector -mno-relax \
  -nostdlib -nostartfiles \
  -T software/runtime/link.ld \
  -Wl,--no-relax,-Map=build/c-program/main.map \
  software/runtime/start.S main.c -lc -lgcc \
  -o build/c-program/main.elf
```

`-nostartfiles/-nostdlib` 让本项目启动代码负责入口；显式链接 `-lc`
提供 `memcpy` 等函数，`-lgcc` 提供软件乘除法等编译器辅助函数。
使用 `printf`、动态内存等功能仍需实现对应的串口/系统调用支持。
当前启动程序不执行构造函数、不初始化 TLS，链接脚本会拒绝这类程序。

ROM 镜像提取 `.text`，RAM 初始化镜像提取 `.data`，按其 LMA 地址
放入 RAM；不能把整个 ELF 简单当成一份通用的 `program.hex`。
示例提取命令如下，提取后的二进制仍需转换为 32 位小端字的 hex 文件：

```sh
riscv32-unknown-elf-objcopy -O binary --only-section=.text \
  build/c-program/main.elf build/c-program/text.bin
riscv32-unknown-elf-objcopy -O binary --only-section=.data \
  build/c-program/main.elf build/c-program/data.bin
riscv32-unknown-elf-objdump -h build/c-program/main.elf
```

## 验证

在项目根目录运行 `python3 tests/run_c_runtime_test.py`。
该检查编译一个实际 C 程序，在现有 `soc_top`、三级流水线核和同步
RAM 上执行，检查初值恢复、BSS 清零、字符串读取、局部数组、函数
调用/返回、栈指针和复位后的再次启动。RAM 运行区预置非零垃圾值，
初始副本区域预装 ELF 数据；验证程序会修改初值变量，再直接复位，
确认第二次启动能恢复初值，同时副本保持不变。
