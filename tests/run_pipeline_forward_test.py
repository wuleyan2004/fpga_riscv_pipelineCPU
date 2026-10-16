#!/usr/bin/env python3
"""Assemble and check WB -> EX forwarding with the real synchronous RAM."""
import shutil
import struct
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests" / "results" / ("pipeline-forward-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
OUT.mkdir(parents=True)


def tool(suffix):
    for prefix in ("riscv32-unknown-elf-", "riscv64-unknown-elf-", "riscv64-elf-"):
        found = shutil.which(prefix + suffix)
        if found:
            return found
    raise SystemExit(f"Missing RISC-V tool: {suffix}")


def logged(command, name, cwd=ROOT):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=30)
    (OUT / name).write_text(" ".join(command) + "\n" + result.stdout + result.stderr)
    return result


source = ROOT / "tests" / "programs" / "forward_test.S"
obj, elf, binary = [OUT / ("forward_test." + suffix) for suffix in ("o", "elf", "bin")]
builds = [([tool("as"), "-march=rv32i", "-mabi=ilp32", "-o", str(obj), str(source)], "assemble.log"),
          ([tool("ld"), "-m", "elf32lriscv", "--no-relax", "-Ttext=0", "-e", "_start",
            "-o", str(elf), str(obj)], "link.log"),
          ([tool("objcopy"), "-O", "binary", "--only-section=.text", str(elf), str(binary)], "objcopy.log")]
for command, name in builds:
    if logged(command, name).returncode:
        raise SystemExit(f"Build failed: {OUT / name}")
logged([tool("objdump"), "-d", "-M", "no-aliases", str(elf)], "disassembly.txt")
(OUT / "forward_test.S").write_text(source.read_text())
blob = binary.read_bytes()
if not blob or len(blob) % 4 or len(blob) > 1024:
    raise SystemExit("Invalid instruction ROM size")
words = [struct.unpack_from("<I", blob, i)[0] for i in range(0, len(blob), 4)]
(OUT / "program.hex").write_text("".join(f"{word:08x}\n" for word in words) + "00000013\n" * (256 - len(words)))
rtl = sorted((ROOT / "rtl" / "cpu").glob("*.v"))
sources = rtl + [ROOT / "rtl" / "sync_data_ram.v", ROOT / "tests" / "tb_pipeline_mem.sv",
                 ROOT / "tests" / "tb_pipeline_forward.sv", ROOT / "tests" / "tb_pipeline_raw_stall.sv"]
results = []
cases = [("arithmetic", "tb_pipeline_raw_stall", []),
         ("direct_ram", "tb_pipeline_forward", ["-Ptb_pipeline_forward.DIRECT=1"]),
         ("delayed_ram", "tb_pipeline_forward", ["-Ptb_pipeline_forward.DIRECT=0",
          "-Ptb_pipeline_forward.PRE_DELAY=2", "-Ptb_pipeline_forward.POST_DELAY=5"])]
for name, top, parameters in cases:
    executable = OUT / f"{name}.vvp"
    build = logged(["iverilog", "-g2012", "-s", top, "-o", str(executable),
                    *parameters, *(str(p) for p in sources)], f"{name}.compile.log")
    passed = False
    if build.returncode == 0:
        run = logged(["vvp", str(executable), f"+WAVE={name}.vcd"], f"{name}.run.log", cwd=OUT)
        passed = run.returncode == 0 and "PASS pipeline" in run.stdout
        print(run.stdout.strip())
    results.append(passed)
report = ["# WB → EX 数据前递验证", "", f"结果：**{'PASS' if all(results) else 'FAIL'}**", "",
          "覆盖连续算术依赖、两个源同时依赖、同一寄存器连续写入、x0 与合法空操作；",
          "全部六类分支的源操作数前递和 taken/not-taken，Load → 分支、Load → JALR；",
          "错误路径 Store 清除、Store 实际写入次数、Load 数据返回前禁止前递、等待时请求与 PC 稳定。", "",
          "实际 sync_data_ram 使用直接连接和接收前等待 2 拍/响应延迟 5 拍两种配置。", ""]
for name, _, _ in cases:
    log = OUT / f"{name}.run.log"
    report += [f"## {name}", "", "```text", log.read_text().strip() if log.exists() else "compile failed", "```", ""]
(OUT / "report.md").write_text("\n".join(report))
print("Results:", OUT)
raise SystemExit(0 if all(results) else 1)
