# 当前 SoC 的 C 启动文件

`start.S` 是 CPU 从 PC=0 开始执行的程序：设置 `gp`、16 字节对齐的
`sp`，把 ROM 中 `__trap_entry` 写入 `mtvec`，复制变量/常量初始值，清零 `.bss`，调用 `main()`；返回后进入
`__boot_halt` 循环，`a0` 保留返回值。

`trap.S` 是机器态同步异常处理程序：把 `mcause/mepc/mtval` 保存到 RAM 的
`__trap_record`。ECALL/EBREAK 跳过触发指令并用 `MRET` 返回；
`trap_emulate_m.c` 模拟八条 M 扩展乘除指令，写回目的寄存器后返回。
其他非法编码及取指、外设或越界地址未对齐停在 `__trap_halt`。
普通 RAM 内的未对齐半字和字访存由硬件拆分完成。当前不处理中断。
复位默认 `mtvec=0x7ffc`，在启动代码设置新入口前发生的异常
仍使用默认入口。

`link.ld` 对应保留的小程序模式，指令 ROM 2 KiB、数据 RAM 1 KiB，两个独立
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

链接器中的 VMA 表示运行地址。小程序的 ROM/RAM 都从地址 0 开始，
ELF 的 RAM LMA 加上 0x10000 以避免与 ROM 的装载地址冲突；构建脚本仍按
`__data_load_start` 将初始副本预装到物理 RAM。CoreMark 使用独立布局。

当前 `board_top` 默认 `COREMARK_PROGRAM=1`，使用 `coremark.ld` 的
32 KiB ROM、64 KiB RAM 和 4 KiB 栈。下面的 `link.ld` 仍用于保留的
2 KiB ROM/1 KiB RAM 最小 C 模式，选择 `COREMARK_PROGRAM=0、C_PROGRAM=1`。
CoreMark 构建和上板流程见项目根目录 `上板测试说明.md`。
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
生成器更新 `rtl/instruction_rom.v` 和 `rtl/sync_data_ram.v`；
这两份 RTL 中的自动生成区域应通过脚本更新。随后重新进行 FPGA
综合、布局布线及下载，板上才会运行修改后的 C 程序。

## 编译

在项目根目录准备自己的 `main.c`，然后执行：

```sh
source '/Users/wuleyan/Desktop/FPGA大赛/工程/01_RV32I三级流水线开发工程/toolchains/env.sh'
mkdir -p build/c-program
riscv32-unknown-elf-gcc \
  -march=rv32i_zicsr -mabi=ilp32 -Os -ffreestanding -fno-builtin \
  -fno-pic -fno-pie -fno-stack-protector -mno-relax \
  -nostdlib -nostartfiles \
  -T software/runtime/link.ld \
  -Wl,--no-relax,-Map=build/c-program/main.map \
  software/runtime/start.S software/runtime/trap.S \
  software/runtime/trap_emulate_m.c main.c -lc -lgcc \
  -o build/c-program/main.elf
```

`-nostartfiles/-nostdlib` 让本项目启动代码负责入口；显式链接 `-lc`
提供 `memcpy` 等函数，`-lgcc` 提供软件乘除法等编译器辅助函数。
使用 `printf`、动态内存等功能仍需实现对应的串口/系统调用支持。
当前启动程序不执行构造函数、不初始化 TLS，链接脚本会拒绝这类程序。

ROM 镜像提取 `.text`，RAM 初始化镜像提取 `.data`，将后者放到
`__data_load_start`；不能把整个 ELF 简单当成一份通用的 `program.hex`。
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
