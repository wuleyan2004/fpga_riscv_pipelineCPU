#!/usr/bin/env python3
"""Run RV32M operations through the actual illegal-instruction ROM handler."""
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "build/m-emulation-test"
OUT.mkdir(parents=True, exist_ok=True)
BIN = ROOT / "toolchains/riscv32-unknown-elf/bin"
SOURCES = [ROOT / line for line in (ROOT / "board_sources.f").read_text().splitlines() if line]


def run(command):
    process = subprocess.run(list(map(str, command)), cwd=OUT, capture_output=True,
                             text=True, timeout=60)
    if process.returncode:
        raise RuntimeError(" ".join(map(str, command)) + "\n" + process.stdout + process.stderr)
    return process.stdout


def tool(name):
    return BIN / ("riscv32-unknown-elf-" + name)


cases = [
    ("MUL", 0, -7, 3),
    ("MULH", 1, 0x80000000, 2),
    ("MULHSU", 2, -7, 0xffffffff),
    ("MULHU", 3, 0xffffffff, 0xffffffff),
    ("DIV", 4, -7, 3),
    ("DIVU", 5, 0xffffffff, 3),
    ("REM", 6, -7, 3),
    ("REMU", 7, 0xffffffff, 3),
    ("DIV_ZERO", 4, -7, 0),
    ("REM_ZERO", 6, -7, 0),
    ("DIV_OVERFLOW", 4, 0x80000000, -1),
    ("REM_OVERFLOW", 6, 0x80000000, -1),
]
lines = [".section .text", ".globl main", "main:", "la s0, results"]
last_instruction = 0
for i, (name, funct3, a, b) in enumerate(cases):
    last_instruction = 0x02000033 | (6 << 20) | (5 << 15) | (funct3 << 12) | (7 << 7)
    lines.extend((f"li t0, {a}", f"li t1, {b}",
                  "__last_fault:" if i == len(cases) - 1 else f".Lcase_{i}:",
                  f".word 0x{last_instruction:08x}  /* {name} */",
                  f"sw t2, {i * 4}(s0)"))
lines.extend(("li t3, 1", "sw t3, 48(s0)", ".Ldone:", "j .Ldone",
              ".section .bss", ".align 2", ".globl results", "results: .space 52"))
(OUT / "main.S").write_text("\n".join(lines) + "\n")
run([tool("gcc"), "-march=rv32i_zicsr", "-mabi=ilp32", "-Os",
     "-ffreestanding", "-fno-builtin", "-fno-pic", "-fno-pie",
     "-mno-relax", "-nostdlib", "-nostartfiles", "-Wl,--no-relax",
     "-T", ROOT / "software/runtime/link.ld", ROOT / "software/runtime/start.S",
     ROOT / "software/runtime/trap.S", ROOT / "software/runtime/trap_emulate_m.c",
     OUT / "main.S", "-lc", "-lgcc", "-o", OUT / "main.elf"])
symbols = {}
for line in run([tool("nm"), "-n", OUT / "main.elf"]).splitlines():
    fields = line.split()
    if len(fields) == 3:
        symbols[fields[2]] = int(fields[0], 16)
run([tool("objcopy"), "-O", "binary", "--only-section=.text",
     OUT / "main.elf", OUT / "text.bin"])
code = (OUT / "text.bin").read_bytes()
if len(code) > 2048 or len(code) % 4:
    raise RuntimeError(f"M emulation test exceeds ROM: {len(code)} bytes")
image = code + struct.pack("<I", 0x00000013) * ((2048 - len(code)) // 4)
(OUT / "program.hex").write_text("".join(
    f"{word[0]:08x}\n" for word in struct.iter_unpack("<I", image)))
(OUT / "ram-preload.hex").write_text("00000000\n" * 256)
bench = OUT / "tb_m_emulation.vvp"
run(["iverilog", "-g2012", "-s", "tb_m_emulation", "-o", bench,
     *SOURCES, ROOT / "tests/verification/tb_m_emulation.sv"])
output = run(["vvp", bench, f"+RESULTS={symbols['results']:08x}",
              f"+LAST_PC={symbols['__last_fault']:08x}",
              f"+LAST_INS={last_instruction:08x}"])
if "PASS RV32M software emulation" not in output:
    raise RuntimeError(output)
print(output.splitlines()[0])
