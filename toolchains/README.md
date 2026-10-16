# 本项目的 RV32I 软件工具链

安装目标：原生 Apple Silicon macOS 上运行的 `riscv32-unknown-elf-gcc`。
默认指令集为 `rv32i`，ABI 为 `ilp32`，用于当前三级流水线 CPU 的裸机程序。

## 使用

在已有终端中执行：

```sh
source '/Users/wuleyan/Desktop/FPGA大赛/工程/01_RV32I三级流水线开发工程/toolchains/env.sh'
riscv32-unknown-elf-gcc --version
riscv32-unknown-elf-gcc -dumpmachine
```

编译 C 文件时仍明确指定目标：

```sh
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Os -ffreestanding -c main.c -o main.o
```

本工具链是单目标构建，因此 `--print-multi-lib` 的正常输出是 `.;`。
RV32I 对应的默认配置可以通过 `-Q --help=target` 查看。

## 组件与来源

- GCC 15.2.0：<https://gcc.gnu.org/pub/gcc/releases/gcc-15.2.0/>
- GNU Binutils 2.45：<https://sourceware.org/pub/binutils/releases/>
  源码经清华 GNU 镜像下载，并与上述官方服务器的 SHA-512 校验值核对。
- Newlib 4.5.0.20241231：<https://sourceware.org/pub/newlib/>
- RISC-V GNU 构建脚本 2026.08.27：
  <https://github.com/riscv-collab/riscv-gnu-toolchain/tree/2026.08.27>

安装路径：`toolchains/riscv32-unknown-elf/`。
下载来源和官方校验值保存在 `downloads/`；源码压缩包缓存已清理。
原始构建日志保存在 `../maintenance/历史编译与测试报告_截至20261009.zip`。
`build-rv32.sh` 记录构建配置，需要事先把对应源码解压到
`/private/tmp/fpga-rv32-build/` 的区分大小写卷中。

## 验证

执行 `bash toolchains/verify-rv32.sh` 检查真实目标、ELF32、RV32I、
C 头文件、Newlib 的 `memcpy`、软件乘除法辅助函数，以及未解析符号。
输出保存在 `verification/`。

安装已通过上述检查，并在删除临时构建卷后再次验证成功。
验证日志：`verification/verification.log`；安装记录：`installation.json`。
已在 `~/.zprofile` 添加环境加载，并备份原文件；新登录终端可以直接使用命令。
已有终端需要先执行上面的 `source` 命令。

`verification/probe.elf` 只用于验证工具链的编译与链接，不是上板程序。
运行自己的 C 程序时，还需提供适合本 SoC 的启动代码、链接脚本、
数据初始化和串口/计时移植。默认 Newlib 启动文件与系统调用接口
不能直接当成本 SoC 的启动环境。
