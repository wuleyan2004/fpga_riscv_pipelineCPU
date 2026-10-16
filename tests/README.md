# 三级流水线 CPU 自动化验证

在项目根目录运行：

```sh
python3 tests/run_all_tests.py
```

需要 Python 3、Icarus Verilog（`iverilog`、`vvp`）和 `toolchains/riscv32-unknown-elf/bin/` 中的汇编工具链。运行结束后，脚本打印结果目录；其中的 `report.md`、`manifest.json` 和各项日志保留原始证据。非零退出码表示至少一项失败。统一入口在开始和结束时计算全部 `rtl/**/*.v` 的 SHA-256，并检查 RTL 未变化。

验证分三层：

| 层次 | 主要测试 |
|---|---|
| 模块级 | `verification/tb_modules.sv` 用独立 Python 向量检查 ALU、分支比较、立即数、decoder 和寄存器堆；`verification/tb_ram.sv` 检查 RAM 写掩码、边界与握手；计时器、性能计数器专项测试 |
| 指令级 | 真实 RV32I 汇编的 43 个算术结果签名；前递、六类分支、JAL/JALR、LUI/AUIPC、五类 Load、三类 Store、不同 RAM 等待；非法指令、ECALL、EBREAK、取指和访存地址错位及异常优先顺序，CSR 读写与 MRET 返回，SoC 文件 ROM 异常入口联通 |
| CPU/SoC | GPIO/UART MMIO 汇编程序、板级串口位级接收、按钮复位、C 启动和两次重启，以及 CoreMark 一次迭代的 CRC/两次启动检查 |

`verification/run_arithmetic.py` 将 `programs/day5_test.S` 的合法算术部分汇编成测试镜像，使用独立软件解释器生成 43 个结果签名；原文件后续的非法编码序列不参与这个会持续执行的程序，非法编码由异常专项测试覆盖。

历史脚本曾使用已经不存在的 `代码/` 路径，且把非法指令与错位访存当作可继续执行的指令。旧入口及其依赖已移除。当前测试针对 `rtl/cpu/cpu_core_pipeline.v` 和 `rtl/soc_top.v`。

测试为 RTL 仿真，不代表 FPGA 综合、时序收敛或实物上板验收。CoreMark 仅一次迭代，不能作为正式分数。复位默认 `mtvec=0x7ffc`，启动代码随后写入 ROM 处理程序的入口地址。`tb_csr_trap_return.sv` 验证 CSR/MRET；`tb_misaligned_ram.sv` 验证普通 RAM 内未对齐访存；`run_m_emulation.py` 验证八种 M 扩展指令的软件模拟；`run_rom_trap_handler.py` 验证 ECALL/EBREAK 返回，以及未知非法编码、取指和越界未对齐的记录后停机。当前仅支持机器态同步异常，尚无中断。RV32I FENCE 已译码，FENCE.I 属于未实现的 Zifencei 扩展。2026-10-10 的结果是修改前的历史记录，见[验证报告](验证报告_2026-10-10.md)；每次运行还会生成独立日志和报告。
