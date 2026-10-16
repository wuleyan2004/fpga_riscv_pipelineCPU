#!/usr/bin/env python3
"""Build, validate and export performance/validation CoreMark FPGA packages."""
import fnmatch
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
STAMP = datetime.now(ZoneInfo("Asia/Shanghai")).strftime("%Y%m%d-%H%M%S")
OUT = ROOT / "build" / ("board-coremark-" + STAMP)
OUT.mkdir(parents=True, exist_ok=False)
sources = [ROOT / line for line in (ROOT / "board_sources.f").read_text().splitlines() if line]
fdc_path = ROOT / "board_top.fdc"
checks = []


def logged(command, name, cwd=ROOT):
    print("Running:", name, flush=True)
    result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True, text=True, timeout=600)
    (OUT / name).write_text(" ".join(map(str, command)) + "\n" + result.stdout + result.stderr)
    print(result.stdout.strip(), flush=True)
    if result.returncode:
        raise SystemExit(f"FAIL {name}: {OUT / name}\n{result.stderr}")
    return result.stdout


def check_initialization(package, image_dir):
    """Check complete static images and prevent the observed PDS loop-limit error."""
    for filename, label, array, hexfile, count in (
            ("instruction_rom.v", "ROM", "imem", "coremark_program.hex", 8192),
            ("sync_data_ram.v", "RAM", "mem", "coremark_data.hex", 16384)):
        source = (package / "rtl" / filename).read_text()
        branch = source.split("end else if (C_PROGRAM)", 1)[0]
        if re.search(r"\bfor\s*\(", branch):
            raise SystemExit(f"CoreMark initialization must not use loops: {filename}")
        region = re.search(rf"// BEGIN GENERATED COREMARK {label}\n(.*?)"
                           rf"// END GENERATED COREMARK {label}", source, re.S)
        if not region:
            raise SystemExit(f"Missing initialization image: {filename}")
        entries = re.findall(rf"{array}\[(\d+)\] = 32'h([0-9a-f]{{8}});", region[1])
        expected = (image_dir / hexfile).read_text().splitlines()
        if len(expected) != count or entries != [(str(i), w) for i, w in enumerate(expected)]:
            raise SystemExit(f"Incomplete or incorrect static initialization: {filename}")


if len(sources) != 16 or len(set(p.name for p in sources)) != 16:
    raise SystemExit("Invalid board source list")
board = (ROOT / "rtl/board_top.v").read_text()
ports = {}
for direction, high, low, name in re.findall(
        r"\b(input|output)\s+wire\s*(?:\[(\d+):(\d+)\])?\s*(\w+)", board):
    if high:
        ports.update({f"{name}[{i}]": direction.upper() for i in range(int(low), int(high)+1)})
    else:
        ports[name] = direction.upper()
fdc = fdc_path.read_text()
attributes = {}
for port, attr, value in re.findall(r"define_attribute\s+\{p:([^}]+)\}\s+\{([^}]+)\}\s+\{([^}]+)\}", fdc):
    if attr in attributes.setdefault(port, {}):
        raise SystemExit("Duplicate pin constraint")
    attributes[port][attr] = value
pins = {"clk": "D18", "reset_button_n": "C22", "uart_tx_pin": "AB26"}
pins.update({f"gpio_button_n[{i}]": p for i,p in enumerate(("C23","B22","A22","B20"))})
pins.update({f"gpio_out[{i}]": p for i,p in enumerate(("A20","C18","C19","E18","A17","A18","C17","B17"))})
if set(ports) != set(attributes) or set(ports) != set(pins) or len(set(pins.values())) != 15:
    raise SystemExit("Pin mapping mismatch")
for port, direction in ports.items():
    if attributes[port] != {"PAP_IO_DIRECTION": direction, "PAP_IO_LOC": pins[port],
                            "PAP_IO_VCCIO": "3.3", "PAP_IO_STANDARD": "LVCMOS33"}:
        raise SystemExit(f"Pin attribute mismatch: {port}")
if "create_clock -name {clk} -period {37.037} [get_ports {clk}]" not in fdc:
    raise SystemExit("Missing 27 MHz clock")
exceptions = re.findall(r"^set_false_path -(from|to) \[get_ports \{([^}]+)\}\]$", fdc, re.M)
if exceptions != [("from","reset_button_n"),("from","gpio_button_n*"),("to","gpio_out*"),("to","uart_tx_pin")]:
    raise SystemExit("Unexpected timing exceptions")
if any(not any(fnmatch.fnmatchcase(p, pattern) for p in ports) for _,pattern in exceptions):
    raise SystemExit("Empty constraint pattern")
checks.append("16 sources and 15 pin assignments; structural constraints")

logged([sys.executable, ROOT / "software/build_c_demo.py"], "c.build.log")
for script in ("run_board_c_test.py", "run_c_runtime_test.py", "run_pipeline_forward_test.py"):
    logged([sys.executable, ROOT / "tests" / script], script + ".log")
    checks.append(script)
for top in ("tb_board_inputs", "tb_board_demo", "tb_board_rom_consistency", "tb_timer_mmio"):
    exe = OUT / (top + ".vvp")
    logged(["iverilog","-g2012","-s",top,"-o",exe,*sources,ROOT / "tests" / (top+".sv")], top+".compile.log")
    logged(["vvp",exe], top+".run.log")
    checks.append(top)

for mode in ("performance", "validation"):
    logged([sys.executable, ROOT / "software/build_coremark.py", "--run",mode,"--iterations","1","--no-embed"], mode+".short.build.log")
    logged([sys.executable, ROOT / "tests/run_coremark_test.py", "--run",mode], mode+".short.test.log")
    checks.append(mode+" official CRC / UART / warm reset; one iteration, not score")

archives = []
for mode in ("performance", "validation"):
    logged([sys.executable, ROOT / "software/build_coremark.py", "--run",mode], mode+".board.build.log")
    image_dir = ROOT / "build" / ("coremark-"+mode+"-0")
    package = OUT / ("board_coremark_"+mode)
    (package / "rtl").mkdir(parents=True)
    for source in sources:
        shutil.copy2(source, package / "rtl" / source.name)
    shutil.copy2(fdc_path, package / "board_top.fdc")
    shutil.copy2(ROOT / "上板测试说明.md", package / "README.md")
    (package / "sources.f").write_text("".join(f"rtl/{p.name}\n" for p in sources))
    source_files = list((ROOT / "software/coremark/fpga").glob("*"))
    source_files += [ROOT / "software/coremark" / name for name in
                    ("core_list_join.c","core_main.c","core_matrix.c","core_state.c","core_util.c",
                     "coremark.h","coremark.md5","LICENSE.md","README.md")]
    source_files += [ROOT / "software/runtime" / name for name in
                     ("start.S", "trap.S", "trap_emulate_m.c", "coremark.ld", "link.ld")]
    source_files += [ROOT / "software/build_coremark.py"]
    for source in source_files:
        if source.is_file():
            target = package / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source,target)
    (package / "software/images").mkdir(parents=True)
    for name in ("main.elf","main.map","main.dis","metadata.json","coremark_program.hex","coremark_data.hex"):
        shutil.copy2(image_dir / name, package / "software/images" / name)
    metadata = json.loads((image_dir / "metadata.json").read_text())
    check_initialization(package, image_dir)
    checks.append(mode + " loop-free complete static ROM/RAM initialization")
    logged(["iverilog","-g2005","-s","board_top","-t","null","-f","sources.f"], mode+".package.compile.log", cwd=package)
    # 验证实际内置的 ITERATIONS=0 镜像：上电复制/清零、UART、首轮自动标定 CRC。
    # 完整 10 秒以上运行留给实物；不伪造计时，也不加速板级时钟。
    logged([sys.executable, ROOT / "tests/run_coremark_test.py", "--run",mode,"--iterations","0","--package",package], mode+".package.calibration.log")
    package_hashes = {str(p.relative_to(package)):hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in sorted(package.rglob("*")) if p.is_file()}
    manifest = {"date":STAMP,"run":mode,"top":"board_top","clock_hz":27000000,
                "iterations":0,"rom_bytes":metadata["rom_bytes"],"rom_capacity":32768,"ram_capacity":65536,
                "checks":checks + ["embedded automatic image first calibration CRC"],
                "package_sha256":package_hashes,"full_10_second_run_simulated":False,
                "pds_synthesis_verified":False,"pds_timing_verified":False,"physical_board_verified":False}
    (package / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    archive = OUT / (package.name+".zip")
    with zipfile.ZipFile(archive,"w",compression=zipfile.ZIP_DEFLATED) as z:
        for p in sorted(package.rglob("*")):
            if p.is_file(): z.write(p,Path(package.name)/p.relative_to(package))
    archives.append(archive)

# 源目录默认恢复性能测试镜像，避免最后生成的验证种子成为默认上板程序。
logged([sys.executable, ROOT / "software/build_coremark.py"], "restore.performance.log")
report = ["# CoreMark 上板准备", "", "本地验证 PASS。", "",
          "CPU 指令集保持 RV32I；ROM 32 KiB、RAM 64 KiB；新增只读 64 位周期计数器。", "",
          "性能和验证种子的一轮测试均通过官方 CRC、实际 UART 逐位接收和两次保留 RAM 的启动；栈使用 1632 字节（预留 4096）。", "",
          "两个上板包均内置 ITERATIONS=0 自动标定镜像，已用导出的实际 RTL 检查首轮标定 CRC、全部 ROM/RAM word 和启动串口；完整 10 秒以上测试尚未在本地仿真或实物完成，未给出正式成绩。", "",
          "引脚约束做结构检查；PDS 综合、布局布线、时序和实物烧录需在远程平台完成。", "",
          *[f"- [{p.name}]({p})" for p in archives], ""]
(OUT / "report.md").write_text("\n".join(report))
print("Report:", OUT / "report.md", flush=True)
for p in archives: print("Package:",p,flush=True)
