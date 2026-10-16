#!/usr/bin/env python3
"""Check the real board UART, C startup, image consistency and warm reset."""
import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--package", type=Path, help="Validate exported rtl instead of source RTL")
args = parser.parse_args()
OUT = ROOT / "build/c-demo"
metadata = json.loads((OUT / "metadata.json").read_text())
symbols = metadata["symbols"]
names = {"INITIALIZED_ADDR": "initialized", "RESULT_ADDR": "result", "VISITS_ADDR": "visits",
         "BSS_END": "__bss_end", "COPY_START": "__data_load_start",
         "COPY_END": "__data_load_end", "HALT_PC": "__boot_halt"}
params = [f"-Ptb_board_c.{param}={symbols[name]}" for param, name in names.items()]
if args.package:
    sources = [args.package / line.strip() for line in (args.package / "sources.f").read_text().splitlines()
               if line.strip()]
    image_dir = args.package / "software/images"
    executable = OUT / "exported-board-c.vvp"
    log = OUT / "exported-board-c.log"
else:
    sources = [ROOT / line.strip() for line in (ROOT / "board_sources.f").read_text().splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
    image_dir = OUT
    executable = OUT / "board-c.vvp"
    log = OUT / "board-c.log"
command = ["iverilog", "-g2012", "-s", "tb_board_c", *params, "-o", str(executable),
           *map(str, sources), str(ROOT / "tests/tb_board_c.sv")]
build = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
output = " ".join(command) + "\n" + build.stdout + build.stderr
if build.returncode == 0:
    # Icarus 的 SV string/plusargs 不可靠地处理 UTF-8 中文绝对路径；使用英文文件名。
    run = subprocess.run(["vvp", str(executable), "+ROM=c_program.hex", "+RAM=c_data.hex"], cwd=image_dir,
                         capture_output=True, text=True, timeout=60)
    output += run.stdout + run.stderr
    print(run.stdout, end="")
    passed = run.returncode == 0 and "PASS board_c" in run.stdout
else:
    print(build.stderr)
    passed = False
log.write_text(output)
if not passed:
    raise SystemExit(f"FAIL C board test: {log}")
