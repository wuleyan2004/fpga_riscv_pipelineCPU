#!/usr/bin/env python3
"""Assemble and simulate an RV32I UART MMIO program with pin-level checks."""

import hashlib
import json
import shutil
import struct
import subprocess
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tests/programs/uart_test.S"
RTL = sorted((ROOT / "rtl").rglob("*.v"))
OUT = ROOT / "tests/results" / ("uart-test-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
OUT.mkdir(parents=True)


def hashes():
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in RTL}


def tool(suffix):
    for prefix in ("riscv32-unknown-elf-", "riscv64-unknown-elf-", "riscv64-elf-"):
        found = shutil.which(prefix + suffix)
        if found:
            return found
    raise SystemExit("Missing RISC-V tool: " + suffix)


def logged(command, filename, cwd=ROOT):
    try:
        completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        (OUT / filename).write_text("FAIL process timeout\n")
        raise SystemExit(f"FAIL timeout; results: {OUT}")
    (OUT / filename).write_text(" ".join(command) + "\n" + completed.stdout + completed.stderr)
    return completed


before = hashes()
obj, elf, binary = [OUT / ("uart_test." + ext) for ext in ("o", "elf", "bin")]
commands = [
    ([tool("as"), "-march=rv32i", "-mabi=ilp32", "-o", str(obj), str(SOURCE)], "assemble.log"),
    ([tool("ld"), "-m", "elf32lriscv", "--no-relax", "-Ttext=0", "-e", "_start",
      "-o", str(elf), str(obj)], "link.log"),
    ([tool("objcopy"), "-O", "binary", "--only-section=.text", str(elf), str(binary)],
     "objcopy.log"),
]
for command, filename in commands:
    if logged(command, filename).returncode:
        raise SystemExit(f"FAIL build; see {OUT / filename}")
logged([tool("objdump"), "-d", "-M", "no-aliases", str(elf)], "disassembly.txt")
(OUT / "uart_test.S").write_text(SOURCE.read_text())
blob = binary.read_bytes()
if len(blob) % 4 or len(blob) > 1024:
    raise SystemExit("Invalid instruction ROM size")
words = [struct.unpack_from("<I", blob, i)[0] for i in range(0, len(blob), 4)]
(OUT / "program.hex").write_text(
    "".join(f"{word:08x}\n" for word in words) + "00000013\n" * (256 - len(words))
)

exe = OUT / "uart_test.vvp"
compiled = logged(
    ["iverilog", "-g2012", "-Wall", "-s", "tb_uart_test", "-o", str(exe),
     str(ROOT / "tests/tb_uart_test.sv"), *map(str, RTL)],
    "compile.log",
)
passed = False
if compiled.returncode == 0:
    run = logged(["vvp", str(exe), f"+N={len(words)}", "+WAVE=uart_test.vcd"],
                 "run.log", cwd=OUT)
    passed = run.returncode == 0 and "PASS uart_test.S" in run.stdout and "FAIL" not in run.stdout

after = hashes()
passed = passed and before == after
(OUT / "manifest.json").write_text(json.dumps({
    "passed": passed,
    "instruction_count": len(words),
    "rtl_unchanged": before == after,
    "before": before,
    "after": after,
}, indent=2))
(OUT / "report.md").write_text(
    "# UART 专项测试\n\n"
    + f"结果：{'PASS' if passed else 'FAIL'}\n\n"
    + f"真实 RV32I 汇编程序：{len(words)} 条指令。\n\n"
    + "覆盖发送 0x41/0xA5/0x5A 三帧（TX 引脚逐位采样）、忙时等待、"
      "STATUS 忙/闲读回、无效字节写和只读状态写忽略、请求与 PC 保持、"
      "RAM/GPIO 地址隔离以及复位。\n\n"
    + "范围：RTL 仿真，不包含实际板级串口引脚或外部串口接收器。\n\n"
    + f"RTL 在测试期间未变化：{before == after}\n"
)
print("uart_test", "PASS" if passed else "FAIL")
print("Results:", OUT)
raise SystemExit(0 if passed else 1)
