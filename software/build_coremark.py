#!/usr/bin/env python3
"""Build unchanged CoreMark algorithms for this RV32I board and emit images."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "software/coremark"
BIN = ROOT / "toolchains/riscv32-unknown-elf/bin"
parser = argparse.ArgumentParser()
parser.add_argument("--iterations", type=int, default=0, help="0: official automatic 10+ second run")
parser.add_argument("--run", choices=("performance", "validation"), default="performance")
parser.add_argument("--no-embed", action="store_true", help="Emit simulation images without replacing board image")
parser.add_argument("--profile", action="store_true", help="Enable diagnostic counters and UART report")
parser.add_argument("--measure", action="store_true", help="Link with provisional large memories, do not modify RTL")
parser.add_argument("--uart-gap-ms", type=int, default=0,
                    help="Idle time after each UART character; 20 for remote receiver diagnosis")
parser.add_argument("--rtl-dir", type=Path, help="Embed into an independent package RTL directory")
args = parser.parse_args()
if not 0 <= args.iterations < 2**31:
    parser.error("iterations must fit a nonnegative signed 32-bit value")
if not 0 <= args.uart_gap_ms <= 1000:
    parser.error("uart-gap-ms must be between 0 and 1000")
OUT = ROOT / "build" / (f"coremark-{args.run}-{args.iterations}"
                       + (f"-uart{args.uart_gap_ms}ms" if args.uart_gap_ms else "")
                       + ("-profile" if args.profile else ""))
OUT.mkdir(parents=True, exist_ok=True)

# CoreMark 算法和头文件严格核对上游清单，移植代码独立存放。
source_hashes = {}
for line in (CORE / "coremark.md5").read_text().splitlines():
    digest, name = line.split()
    path = CORE / name
    actual = hashlib.md5(path.read_bytes()).hexdigest()
    # 上游 1f483d5 的 coremark.h 与仓库 HEAD 完全一致，但上游 md5 清单未同步。
    # 头文件用该提交实际 SHA-256 固定校验，五份算法仍按官方 MD5 校验。
    pinned_header = (name == "coremark.h" and hashlib.sha256(path.read_bytes()).hexdigest()
                     == "42642b9a06c7ed2b3bd9eda971b7c3868c4f5d27bf7ef6c4bba11291a0c2598a")
    if actual != digest and not pinned_header:
        raise SystemExit(f"Upstream CoreMark source changed: {name}")
    source_hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()


def run(tool, *arguments):
    executable = BIN / ("riscv32-unknown-elf-" + tool)
    if not executable.exists():
        executable = shutil.which("riscv32-unknown-elf-" + tool)
    if not executable:
        raise SystemExit("Missing riscv32-unknown-elf toolchain; source toolchains/env.sh first")
    command = [str(executable), *map(str, arguments)]
    p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
    (OUT / (tool + ".log")).write_text(" ".join(command) + "\n" + p.stdout + p.stderr)
    if p.returncode:
        raise SystemExit(p.stderr or p.stdout)
    return p.stdout


link = ROOT / "software/runtime/coremark.ld"
if args.measure:
    # 容量探测用临时脚本，硬件与正式布局在测量后决定。
    link = OUT / "measure.ld"
    link.write_text((ROOT / "software/runtime/link.ld").read_text()
                    .replace("LENGTH = 1K", "LENGTH = 128K")
                    .replace("__stack_size : 256", "__stack_size : 4096"))
    rom_bytes = ram_bytes = 128 * 1024
else:
    rom_bytes, ram_bytes = 32 * 1024, 64 * 1024
flags = ["-march=rv32i_zicsr", "-mabi=ilp32", "-O2", "-ffreestanding", "-fno-builtin",
         "-fno-delete-null-pointer-checks",
         "-fno-pic", "-fno-pie", "-fno-stack-protector", "-mno-relax",
         "-ffunction-sections", "-fdata-sections", "-fstack-usage",
         "-DTOTAL_DATA_SIZE=2000", f"-DITERATIONS={args.iterations}",
         "-D" + args.run.upper() + "_RUN=1"]
if args.uart_gap_ms:
    flags.append(f"-DCOREMARK_UART_GAP_CYCLES={27000 * args.uart_gap_ms}")
if args.profile:
    flags.append("-DCOREMARK_PROFILE=1")
flag_string = " ".join(flags)
objects = []
sources = [CORE / name for name in ("core_list_join.c", "core_main.c", "core_matrix.c",
                                   "core_state.c", "core_util.c")]
sources += [CORE / "fpga" / name for name in ("core_portme.c", "ee_printf.c", "cvt.c")]
for source in sources:
    obj = OUT / (source.stem + ".o")
    run("gcc", *flags, '-DFLAGS_STR="' + flag_string + '"',
        "-I", CORE / "fpga", "-I", CORE, "-c", source, "-o", obj)
    objects.append(obj)
elf = OUT / "main.elf"
run("gcc", *flags, "-nostdlib", "-nostartfiles", "-Wl,--gc-sections,--no-relax,-Map=" + str(OUT / "main.map"),
    "-T", link, ROOT / "software/runtime/start.S", ROOT / "software/runtime/trap.S",
    ROOT / "software/runtime/trap_emulate_m.c",
    *objects, "-lm", "-lc", "-lgcc", "-o", elf)
symbols = {}
for line in run("nm", "-n", elf).splitlines():
    match = re.match(r"^([0-9a-fA-F]+)\s+\S\s+(.+)$", line)
    if match:
        symbols[match[2]] = int(match[1], 16)
for section, name in ((".text", "text.bin"), (".data", "data.bin")):
    run("objcopy", "-O", "binary", "--only-section=" + section, elf, OUT / name)
(OUT / "main.dis").write_text(run("objdump", "-d", elf))
(OUT / "sections.txt").write_text(run("objdump", "-h", elf))
# 用同一 RV32 ABI 提取结果结构体偏移，供 RTL 测试观察自动标定的首轮 CRC。
layout_c = OUT / "layout.c"
layout_c.write_text('#include "coremark.h"\nconst unsigned offsets[] = {'
    'offsetof(core_results, crclist), offsetof(core_results, crcmatrix), '
    'offsetof(core_results, crcstate)};\n')
run("gcc", *flags, '-DFLAGS_STR="layout"', "-I", CORE / "fpga", "-I", CORE,
    "-c", layout_c, "-o", OUT / "layout.o")
run("objcopy", "-O", "binary", "--only-section=.rodata.offsets", OUT / "layout.o", OUT / "layout.bin")
layout = (OUT / "layout.bin").read_bytes()
crc_offsets = [int.from_bytes(layout[i:i+4], "little") for i in (0, 4, 8)]
if len(layout) != 12:
    raise SystemExit("Unexpected CoreMark result layout")
text, data = (OUT / "text.bin").read_bytes(), (OUT / "data.bin").read_bytes()
start = symbols["__data_load_start"]
if len(text) > rom_bytes or len(text) % 4 or start + len(data) > symbols["__stack_bottom"]:
    raise SystemExit("CoreMark image exceeds memory layout")

# 校验每个可执行 word 的指令族；只允许处理程序实际使用的 SYSTEM 指令。
allowed = {0x03, 0x23, 0x13, 0x33, 0x37, 0x17, 0x63, 0x6f, 0x67}
for offset in range(0, len(text), 4):
    word = int.from_bytes(text[offset:offset + 4], "little")
    opcode = word & 0x7f
    if opcode == 0x0f and ((word >> 12) & 7) == 0:  # RV32I FENCE
        continue
    if opcode == 0x73:
        csr_addr = (word >> 20) & 0xfff
        funct3 = (word >> 12) & 7
        if word == 0x30200073 or (funct3 in (1, 2) and
                                   csr_addr in (0x305, 0x341, 0x342, 0x343)):
            continue
    if opcode not in allowed or (opcode == 0x33 and (word >> 25) == 1):
        raise SystemExit(f"Unsupported instruction at 0x{offset:x}: {word:08x}")
rom = text + bytes.fromhex("13000000") * ((rom_bytes - len(text)) // 4)
ram = bytearray(ram_bytes)
ram[start:start + len(data)] = data


def words(image):
    return [int.from_bytes(image[i:i+4], "little") for i in range(0, len(image), 4)]


for name, image in (("coremark_program.hex", rom), ("coremark_data.hex", ram)):
    (OUT / name).write_text("".join(f"{word:08x}\n" for word in words(image)))


def embed(filename, label, body):
    rtl_dir = args.rtl_dir or (ROOT / "rtl")
    path = rtl_dir / filename
    source = path.read_text()
    pattern = rf"(    // BEGIN GENERATED {label}\n).*?(    // END GENERATED {label})"
    updated, count = re.subn(pattern, lambda m: m[1] + body + m[2], source, flags=re.S)
    if count != 1:
        raise SystemExit(f"Missing generated region: {filename}")
    if updated != source:
        path.write_text(updated)


if not args.no_embed and not args.measure:
    # PDS 初始化循环展开上限为 2000。直接生成完整镜像，零值/NOP 也写入。
    # 保留同一数组与单一 initial 块，避免改变 RAM 推断结构。
    embed("instruction_rom.v", "COREMARK ROM", "".join(
        f"                imem[{i}] = 32'h{w:08x};\n" for i, w in enumerate(words(rom))))
    embed("sync_data_ram.v", "COREMARK RAM", "".join(
        f"                mem[{i}] = 32'h{w:08x};\n" for i, w in enumerate(words(ram))))
metadata = {"run": args.run, "iterations": args.iterations, "flags": flag_string,
            "profile": args.profile,
            "uart_gap_ms": args.uart_gap_ms,
            "crc_offsets": crc_offsets,
            "rom_capacity": rom_bytes, "ram_capacity": ram_bytes, "rom_bytes": len(text),
            "data_bytes": len(data), "bss_bytes": symbols["__bss_end"] - symbols["__bss_start"],
            "snapshot_start": start, "snapshot_end": start + len(data), "symbols": symbols,
            "algorithm_sha256": source_hashes, "clock_hz": 27000000,
            "timer_cycles_per_tick": 1024, "rv32i_instruction_check": True}
(OUT / "metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
print(f"PASS CoreMark {args.run} iterations={args.iterations}: text={len(text)}, data={len(data)}, "
      f"bss={metadata['bss_bytes']}, snapshot_end={start + len(data)}, stack={symbols['__stack_size']}")
print("Artifacts:", OUT)
