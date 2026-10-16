#!/usr/bin/env python3
"""Run LUI/AUIPC pipeline checks with direct and delayed synchronous RAM."""
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests" / "results" / ("pipeline-upper-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
OUT.mkdir(parents=True)
rtl = sorted((ROOT / "rtl" / "cpu").glob("*.v"))
sources = rtl + [ROOT / "rtl" / "sync_data_ram.v",
                 ROOT / "tests" / "tb_pipeline_mem.sv", ROOT / "tests" / "tb_pipeline_upper.sv"]
results = []
for name, direct, pre, post in (("direct_ram", 1, 0, 0), ("delayed_ram", 0, 2, 5)):
    executable = OUT / f"{name}.vvp"
    command = ["iverilog", "-g2012", "-s", "tb_pipeline_upper", "-o", str(executable),
               f"-Ptb_pipeline_upper.DIRECT={direct}",
               f"-Ptb_pipeline_upper.PRE_DELAY={pre}",
               f"-Ptb_pipeline_upper.POST_DELAY={post}", *(str(p) for p in sources)]
    build = subprocess.run(command, capture_output=True, text=True, timeout=30)
    output = build.stdout + build.stderr
    code = build.returncode
    if code == 0:
        run = subprocess.run(["vvp", str(executable), f"+WAVE={name}.vcd"],
                             cwd=OUT, capture_output=True, text=True, timeout=30)
        output += run.stdout + run.stderr
        code = run.returncode
    (OUT / f"{name}.log").write_text(output)
    passed = code == 0 and "PASS pipeline_upper" in output
    results.append(passed)
    print(name, "PASS" if passed else "FAIL")
    print(output.strip())
report = ["# LUI/AUIPC 流水线验证", "", f"结果：**{'PASS' if all(results) else 'FAIL'}**", "",
          "覆盖：零/正/高位为 1 的 U 型立即数；LUI/AUIPC 后紧随 ADDI；x0；立即数字段不产生假 RAW；",
          "U 型结果用于 Store 数据、Load/Store 地址、JALR 和 BEQ；Load/Store 等待时的 AUIPC；",
          "跳转后 AUIPC 使用自身 PC；错误路径上的 LUI/AUIPC 被清除；高地址 PC 加法的 32 位回绕。", "",
          "逐条核对退休 PC、指令、写使能和写回值，并核对全部寄存器。实际数据 RAM 分别使用直接连接、接收前等待 2 拍和响应延迟 5 拍。", ""]
for name in ("direct_ram", "delayed_ram"):
    report += [f"## {name}", "", "```text", (OUT / f"{name}.log").read_text().strip(), "```", ""]
(OUT / "report.md").write_text("\n".join(report))
print("Results:", OUT)
raise SystemExit(0 if all(results) else 1)
