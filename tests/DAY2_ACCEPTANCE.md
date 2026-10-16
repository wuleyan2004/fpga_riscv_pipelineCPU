# 第四周第二天：Load/Store 验收记录

> 历史记录：以下描述的是异常机制加入前的实现。当前错位访问会触发异常，旧变异测试脚本已移除；现行测试入口和报告见 [README.md](README.md)。

## 指令覆盖矩阵

| 指令 | Decoder | 地址/数据处理 | 指令级 | `mem_test.S` |
|---|---|---|---|---|
| LW | PASS | 4 字节对齐、32-bit 写回 | PASS | PASS |
| SW | PASS | `wstrb=1111` | PASS | PASS |
| LB | PASS | 4 byte lanes、符号扩展 | PASS | PASS |
| LBU | PASS | 4 byte lanes、零扩展 | PASS | PASS |
| LH | PASS | 低/高 halfword、符号扩展 | PASS | PASS |
| LHU | PASS | 低/高 halfword、零扩展 | PASS | PASS |
| SB | PASS | `0001/0010/0100/1000` | PASS | PASS |
| SH | PASS | `0011/1100` | PASS | PASS |

## 对齐策略

- LB/LBU/SB 允许任意 byte address。
- LH/LHU/SH 要求 `addr[0]==0`。
- LW/SW 要求 `addr[1:0]==00`。
- 当前不实现 Trap；错位访问仍完成总线握手，但 Load 不写回寄存器，Store 使用零写掩码，不修改 RAM。
- `debug_misaligned` 在 CPU 发现错位 Load/Store 时拉高一个时钟周期。

## 自动验收

以下是当时的验收描述。当前可运行的统一入口为：

```sh
python3 tests/run_all_tests.py
```

一键回归覆盖模块级、SoC 指令级、RAM 额外等待 2/5 拍和真实汇编程序级。仿真同时检查：

- `mem_ready` 之前 PC 保持；
- 请求等待期间 `mem_write/mem_wstrb/mem_addr/mem_wdata` 稳定；
- Load 只写回一次，Store 物理接收次数与指令数一致；
- 错位 debug 脉冲只出现一次，且无架构状态副作用；
- 全部寄存器和被触及 RAM 的最终值；
- 测试前后 RTL SHA-256 一致。

当时使用的 `run_mutation_check.py` 已随旧 CPU 验证入口移除；现行回归直接检查 LB 符号扩展及 RTL 哈希。

## 波形检查链

保存的 VCD 中包含 `cpu_state/pc/mem_valid/mem_ready/mem_addr/mem_wstrb/mem_rdata/rd_we/debug_misaligned`。对应的时序断言已自动化，不依赖人工看波形判定 PASS。

## 范围限制

- 错位访问目前只禁止副作用并输出 debug 脉冲，尚未实现 RISC-V 异常/Trap。
- RAM 未初始化位置读出 X；地址越界保护不在第二天范围内。
- 项目目录当前不是独立 Git 仓库，而是落在用户主目录的上层仓库中；为避免提交无关文件，本次不自动创建 Git commit，结果目录中保存 RTL 哈希作为可复现快照。
