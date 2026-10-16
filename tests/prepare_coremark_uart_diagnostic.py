#!/usr/bin/env python3
"""Export a selected CoreMark run with real 20 ms UART gaps."""
import argparse
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
parser = argparse.ArgumentParser()
parser.add_argument("--run", choices=("performance", "validation"), default="performance")
parser.add_argument("--profile", action="store_true", help="Export hardware counter diagnostic image")
args = parser.parse_args()
title = "性能" if args.run == "performance" else "验证"
crc = {"performance": ("e9f5", "e714", "1fd7", "8e3a"),
       "validation": ("18f2", "e3c1", "0747", "8d84")}[args.run]
STAMP = datetime.now(ZoneInfo("Asia/Shanghai")).strftime("%Y%m%d-%H%M%S")
OUT = ROOT / "build" / ("board-coremark-uart-" + STAMP + ("-profile" if args.profile else ""))
PACKAGE = OUT / (f"board_coremark_{args.run}_uart20ms" + ("_profile" if args.profile else ""))
TEST = OUT / "pacing-test"
TEST.mkdir(parents=True)
(PACKAGE / "rtl").mkdir(parents=True)
sources = [ROOT / s for s in (ROOT / "board_sources.f").read_text().splitlines() if s]


def logged(command, name, cwd=ROOT, timeout=300):
    print("Running:", name, flush=True)
    result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True,
                            text=True, timeout=timeout)
    (OUT / name).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise SystemExit(f"FAIL {name}: {result.stdout}{result.stderr}")
    print(result.stdout.strip(), flush=True)
    return result.stdout


for source in sources:
    shutil.copy2(source, PACKAGE / "rtl" / source.name)
shutil.copy2(ROOT / "board_top.fdc", PACKAGE / "board_top.fdc")
(PACKAGE / "sources.f").write_text("".join(f"rtl/{p.name}\n" for p in sources))
logged([sys.executable, ROOT / "software/build_coremark.py", "--run", args.run,
        "--uart-gap-ms", "20", "--rtl-dir", PACKAGE / "rtl",
        *(["--profile"] if args.profile else [])], args.run + ".build.log")
IMAGE = ROOT / (f"build/coremark-{args.run}-0-uart20ms" + ("-profile" if args.profile else ""))
META = json.loads((IMAGE / "metadata.json").read_text())
for source in (ROOT / "software/coremark").glob("*"):
    if source.is_file():
        target = PACKAGE / "software/coremark" / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
for source in (ROOT / "software/coremark/fpga").glob("*"):
    if source.is_file():
        target = PACKAGE / "software/coremark/fpga" / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
for relative in ("software/build_coremark.py", "software/runtime/start.S",
                 "software/runtime/trap.S",
                 "software/runtime/trap_emulate_m.c",
                 "software/runtime/coremark.ld", "software/runtime/link.ld"):
    target = PACKAGE / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / relative, target)
(PACKAGE / "software/images").mkdir(parents=True)
for name in ("main.elf", "main.dis", "main.map", "metadata.json",
             "coremark_program.hex", "coremark_data.hex"):
    shutil.copy2(IMAGE / name, PACKAGE / "software/images" / name)
for filename, array, image in (("instruction_rom.v", "imem", "coremark_program.hex"),
                              ("sync_data_ram.v", "mem", "coremark_data.hex")):
    source = (PACKAGE / "rtl" / filename).read_text().split("end else if (C_PROGRAM)", 1)[0]
    entries = re.findall(rf"{array}\[(\d+)\] = 32'h([0-9a-f]{{8}});", source)
    expected = (IMAGE / image).read_text().splitlines()
    assert entries == [(str(i), word) for i, word in enumerate(expected)]
    assert not re.search(r"\bfor\s*\(", source)
logged(["iverilog", "-g2005", "-s", "board_top", "-t", "null", "-f", "sources.f"],
       "package.compile.log", PACKAGE)

# 直接编译同一份 ee_printf.c 的 uart_send_char，保留实际 540000 周期等待。
# --gc-sections 仅剔除这个测试未调用的格式化函数。
(TEST / "main.c").write_text('''#include <stdint.h>
void uart_send_char(char);
int main(void) {
    uart_send_char('A'); uart_send_char('B'); uart_send_char('\\n');
    *(volatile uint32_t *)0x10000000u = 2;
    return 0;
}
''')
BIN = ROOT / "toolchains/riscv32-unknown-elf/bin"


def tool(name):
    return BIN / ("riscv32-unknown-elf-" + name)


logged([tool("gcc"), "-march=rv32i_zicsr", "-mabi=ilp32", "-O2", "-ffreestanding",
        "-fno-builtin", "-fno-delete-null-pointer-checks", "-fno-pic", "-fno-pie",
        "-fno-stack-protector", "-mno-relax", "-ffunction-sections", "-fdata-sections",
        "-DCOREMARK_UART_GAP_CYCLES=540000", '-DFLAGS_STR="pacing-test"',
        "-I", ROOT / "software/coremark/fpga", "-I", ROOT / "software/coremark",
        "-nostdlib", "-nostartfiles", "-Wl,--gc-sections,--no-relax",
        "-T", ROOT / "software/runtime/coremark.ld", ROOT / "software/runtime/start.S",
        ROOT / "software/runtime/trap.S",
        ROOT / "software/runtime/trap_emulate_m.c",
        ROOT / "software/coremark/fpga/ee_printf.c", TEST / "main.c", "-lm", "-lc", "-lgcc",
        "-o", TEST / "main.elf"], "pacing.gcc.log", TEST)
symbols = {}
for line in logged([tool("nm"), "-n", TEST / "main.elf"], "pacing.nm.log", TEST).splitlines():
    fields = line.split()
    if len(fields) == 3:
        symbols[fields[2]] = int(fields[0], 16)
for section, name in ((".text", "text.bin"), (".data", "data.bin")):
    logged([tool("objcopy"), "-O", "binary", "--only-section=" + section,
            TEST / "main.elf", TEST / name], "pacing." + name + ".log", TEST)
text = (TEST / "text.bin").read_bytes()
rom = text + bytes.fromhex("13000000") * ((32768 - len(text)) // 4)
ram = bytearray(65536)
data = (TEST / "data.bin").read_bytes()
start = symbols["__data_load_start"]
ram[start:start+len(data)] = data
for name, image in (("coremark_program.hex", rom), ("coremark_data.hex", ram)):
    (TEST / name).write_text("".join(f"{int.from_bytes(image[i:i+4], 'little'):08x}\n"
                                   for i in range(0, len(image), 4)))
    shutil.copy2(IMAGE / name, TEST / ("actual_" + name))
rtl = [PACKAGE / "rtl" / source.name for source in sources]
logged(["iverilog", "-g2012", "-s", "tb_coremark_uart_pacing", "-o", TEST / "test.vvp",
        *rtl, ROOT / "tests/tb_coremark_uart_pacing.sv"], "pacing.compile.log", TEST)
output = logged(["vvp", TEST / "test.vvp"], "pacing.run.log", TEST)
assert "PASS UART pacing" in output and "PASS diagnostic package" in output

# 正常速度的两次短跑核对新串口函数与完整报告，不改变计数器和算法。
logged([sys.executable, ROOT / "software/build_coremark.py", "--run", args.run,
        "--iterations", "1", "--no-embed", *(["--profile"] if args.profile else [])],
       "short.build.log")
logged([sys.executable, ROOT / "tests/run_coremark_test.py", "--run", args.run,
        *(["--profile"] if args.profile else [])], "short.test.log")

(PACKAGE / "README.md").write_text(f'''# CoreMark {title}包：串口慢速输出

将 rtl/ 全部 {len(sources)} 个 .v 和 board_top.fdc 加入工程，顶层 board_top。
COREMARK_PROGRAM=1、COREMARK_FILE=0，27 MHz；ROM 32 KiB、RAM 64 KiB。
串口设置 115200、8N1、无流控，关闭 HEX 显示。先打开接收，再按下并松开复位。

每个字符发送完成后额外等待约 20 ms。报告会花二十多秒逐字打印；
请等待约一分钟，不要在途中清空或关闭接收窗口。
波特率没有降低。算法源码和引脚约束未改，串口等待位于测试计时区间之外。
{'此诊断包在 CPU 上增加了性能事件输出和计数器 MMIO。' if args.profile else '此包保持原 CPU 逻辑。'}
此包用于判断远程接收/显示是否遗漏快速连续输出，尚不能确认遗漏发生在哪一层。
开头应完整显示 CoreMark RV32I start; clock=27000000 Hz。
结束应能核对 seedcrc={crc[0]}、crclist={crc[1]}、crcmatrix={crc[2]}、crcstate={crc[3]}；
正确时应有 Correct operation validated.。
性能种子额外打印 CoreMark 1.0 : ...；验证种子没有这一行，属于正常情况。
测试时间须至少 10 秒。crcfinal 随迭代次数变化，不固定。

本地验证：实际 115200 8N1 帧、20 ms 间隔、低位计数器回绕、完整内置 ROM/RAM；
新串口函数在正常输出速度下的两次单轮{title}测试通过官方 CRC 和完整 UART 报告。
{'本包启用硬件性能计数器，报告最后追加访存等待、RAW 等待、分支和跳转空拍等统计；该诊断镜像的成绩不能直接与基线成绩比较。' if args.profile else ''}
未完成本包完整 10 秒以上 RTL 运行，未进行 PDS 综合和实物验证。
若仍缺字或没有结论，请提供完整日志、GPIO 状态以及本次综合时序报告。
''')
hashes = {str(p.relative_to(PACKAGE)): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in sorted(PACKAGE.rglob("*")) if p.is_file()}
manifest = {"date": STAMP, "top": "board_top", "clock_hz": 27000000,
            "run": args.run, "iterations": 0, "profile": args.profile, "uart_baud": 115200,
            "uart_gap_ms": 20, "rom_bytes": META["rom_bytes"],
            "rom_capacity": 32768, "ram_capacity": 65536,
            "checks": ["complete embedded ROM/RAM", "real 20 ms UART gaps and counter rollover",
                       "two unpaced short runs: official CRC and complete UART report"],
            "full_10_second_run_simulated": False, "physical_board_verified": False,
            "pds_synthesis_verified": False, "package_sha256": hashes}
(PACKAGE / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
archive = OUT / (PACKAGE.name + ".zip")
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as z:
    for p in sorted(PACKAGE.rglob("*")):
        if p.is_file():
            z.write(p, Path(PACKAGE.name) / p.relative_to(PACKAGE))
print("PASS UART diagnostic package:", archive, flush=True)
