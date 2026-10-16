#!/usr/bin/env python3
"""Verify the linked ROM handler for ECALL, EBREAK, illegal and misaligned traps."""
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "build/rom-trap-test"
OUT.mkdir(parents=True, exist_ok=True)
TOOLS = ROOT / "toolchains/riscv32-unknown-elf/bin"
SOURCES = [ROOT / line for line in (ROOT / "board_sources.f").read_text().splitlines() if line]


def tool(name):
    return TOOLS / ("riscv32-unknown-elf-" + name)


def run(command, cwd):
    result = subprocess.run(list(map(str, command)), cwd=cwd,
                            capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError(" ".join(map(str, command)) + "\n" + result.stdout + result.stderr)
    return result.stdout


bench = OUT / "tb_rom_trap_handler.vvp"
run(["iverilog", "-g2012", "-s", "tb_rom_trap_handler", "-o", bench,
     *SOURCES, ROOT / "tests/verification/tb_rom_trap_handler.sv"], OUT)

cases = (
    ("ecall", "ecall", 11, 0),
    ("ebreak", "ebreak", 3, 0),
    ("illegal", ".word 0xffffffff", 2, 0xffffffff),
    ("load_misaligned", "lw t0, 1023(zero)", 4, 1023),
    ("store_misaligned", "sw zero, 1023(zero)", 6, 1023),
    ("instruction_misaligned", ".word 0x0020006f", 0, None),
)

for case_id, (name, fault, cause, tval) in enumerate(cases):
    case_dir = OUT / name
    case_dir.mkdir(exist_ok=True)
    (case_dir / "main.c").write_text(
        "volatile unsigned progress;\n"
        "int main(void) {\n"
        f'  __asm__ volatile(".globl __fault_site\\n__fault_site:\\n{fault}");\n'
        "  progress = 1;\n"
        "  for (;;) {}\n"
        "}\n"
    )
    elf = case_dir / "main.elf"
    run([tool("gcc"), "-march=rv32i_zicsr", "-mabi=ilp32", "-Os",
         "-ffreestanding", "-fno-builtin", "-fno-pic", "-fno-pie",
         "-fno-stack-protector", "-mno-relax", "-nostdlib", "-nostartfiles",
         "-Wl,--no-relax", "-T", ROOT / "software/runtime/link.ld",
         ROOT / "software/runtime/start.S", ROOT / "software/runtime/trap.S",
         ROOT / "software/runtime/trap_emulate_m.c",
         case_dir / "main.c", "-lc", "-lgcc", "-o", elf], case_dir)
    symbols = {}
    for line in run([tool("nm"), "-n", elf], case_dir).splitlines():
        fields = line.split()
        if len(fields) == 3:
            symbols[fields[2]] = int(fields[0], 16)
    binary = case_dir / "text.bin"
    run([tool("objcopy"), "-O", "binary", "--only-section=.text", elf, binary], case_dir)
    code = binary.read_bytes()
    if len(code) > 2048 or len(code) % 4:
        raise RuntimeError(f"trap test does not fit ROM: {name}")
    image = code + struct.pack("<I", 0x00000013) * ((2048 - len(code)) // 4)
    (case_dir / "program.hex").write_text("".join(
        f"{word[0]:08x}\n" for word in struct.iter_unpack("<I", image)))
    (case_dir / "ram-preload.hex").write_text("00000000\n" * 256)
    fault_pc = symbols["__fault_site"]
    expected_tval = fault_pc + 2 if tval is None else tval
    output = run(["vvp", bench, f"+CASE={case_id}", f"+CAUSE={cause}",
                  f"+FAULT_PC={fault_pc:08x}", f"+TVAL={expected_tval:08x}",
                  f"+ENTRY={symbols['__trap_entry']:08x}",
                  f"+HALT={symbols['__trap_halt']:08x}",
                  f"+RECORD={symbols['__trap_record']:08x}",
                  f"+PROGRESS={symbols['progress']:08x}"], case_dir)
    if f"PASS ROM trap case={case_id}" not in output:
        raise RuntimeError(output)
    print(output.splitlines()[0])

print("PASS ROM trap handler six scenarios")
