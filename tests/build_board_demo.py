#!/usr/bin/env python3
"""Build board_demo.S into the 256-word program.hex used by instruction_rom.v."""

import shutil
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "board_demo.S"
OUTPUT = ROOT / "program.hex"


def find_tool(suffix):
    for prefix in ("riscv32-unknown-elf-", "riscv64-unknown-elf-", "riscv64-elf-"):
        found = shutil.which(prefix + suffix)
        if found:
            return found
    raise SystemExit(f"Missing RISC-V tool: {suffix}")


with tempfile.TemporaryDirectory(prefix="board-demo-") as temporary:
    build_dir = Path(temporary)
    obj = build_dir / "board_demo.o"
    elf = build_dir / "board_demo.elf"
    binary = build_dir / "board_demo.bin"
    subprocess.run(
        [find_tool("as"), "-march=rv32i", "-mabi=ilp32", "-o", str(obj), str(SOURCE)],
        check=True,
    )
    subprocess.run(
        [find_tool("ld"), "-m", "elf32lriscv", "--no-relax", "-Ttext=0", "-e", "_start",
         "-o", str(elf), str(obj)],
        check=True,
    )
    subprocess.run(
        [find_tool("objcopy"), "-O", "binary", "--only-section=.text", str(elf), str(binary)],
        check=True,
    )
    blob = binary.read_bytes()

if len(blob) == 0 or len(blob) % 4 or len(blob) > 256 * 4:
    raise SystemExit(f"Invalid program size: {len(blob)} bytes")

words = [struct.unpack_from("<I", blob, i)[0] for i in range(0, len(blob), 4)]
OUTPUT.write_text(
    "".join(f"{word:08x}\n" for word in words)
    + "00000013\n" * (256 - len(words))
)
print(f"Built {OUTPUT}: {len(words)} RV32I instructions, padded to 256 ROM words")
