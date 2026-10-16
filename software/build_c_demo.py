#!/usr/bin/env python3
"""Compile the C smoke test and embed separate ROM/RAM images in board RTL."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "c-demo"
BIN = ROOT / "toolchains" / "riscv32-unknown-elf" / "bin"
OUT.mkdir(parents=True, exist_ok=True)


def run(name, *args):
    command = [str(BIN / ("riscv32-unknown-elf-" + name)), *map(str, args)]
    process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
    (OUT / (name + ".log")).write_text(" ".join(command) + "\n" + process.stdout + process.stderr)
    if process.returncode:
        raise SystemExit(process.stderr or process.stdout)
    return process.stdout


elf = OUT / "main.elf"
flags = ["-march=rv32i_zicsr", "-mabi=ilp32", "-Os", "-ffreestanding", "-fno-builtin",
         "-fno-pic", "-fno-pie", "-fno-stack-protector", "-mno-relax",
         "-nostdlib", "-nostartfiles", "-Wl,--no-relax,-Map=" + str(OUT / "main.map")]
run("gcc", *flags, "-T", ROOT / "software/runtime/link.ld",
    ROOT / "software/runtime/start.S", ROOT / "software/runtime/trap.S",
    ROOT / "software/runtime/trap_emulate_m.c",
    ROOT / "software/c_demo/main.c",
    "-lc", "-lgcc", "-o", elf)
symbols = {}
for line in run("nm", "-n", elf).splitlines():
    match = re.match(r"^([0-9a-fA-F]+)\s+\S\s+(.+)$", line)
    if match:
        symbols[match[2]] = int(match[1], 16)
for section, filename in ((".text", "text.bin"), (".data", "data.bin")):
    run("objcopy", "-O", "binary", "--only-section=" + section, elf, OUT / filename)
(OUT / "main.dis").write_text(run("objdump", "-d", elf))
(OUT / "sections.txt").write_text(run("objdump", "-h", elf))
text = (OUT / "text.bin").read_bytes()
data = (OUT / "data.bin").read_bytes()
load_start = symbols["__data_load_start"]
if len(text) > 2048 or len(text) % 4 or load_start + len(data) > symbols["__stack_bottom"]:
    raise SystemExit("C demo does not fit current ROM/RAM layout")
rom = text + bytes.fromhex("13000000") * ((2048 - len(text)) // 4)
ram = bytearray(1024)
ram[load_start:load_start + len(data)] = data


def words(image):
    return [int.from_bytes(image[i:i + 4], "little") for i in range(0, len(image), 4)]


for filename, image in (("c_program.hex", rom), ("c_data.hex", ram)):
    (OUT / filename).write_text("".join(f"{word:08x}\n" for word in words(image)))


def embed(filename, label, body):
    path = ROOT / "rtl" / filename
    source = path.read_text()
    pattern = rf"(    // BEGIN GENERATED {label}\n).*?(    // END GENERATED {label})"
    updated, count = re.subn(pattern, lambda m: m[1] + body + m[2], source, flags=re.S)
    if count != 1:
        raise SystemExit(f"Missing unique generated region in {path}")
    if updated != source:
        path.write_text(updated)


rom_body = "".join(f"                9'd{i}: c_instruction = 32'h{word:08x};\n"
                   for i, word in enumerate(words(rom)[:len(text) // 4]))
ram_body = "".join(f"            mem[{i}] = 32'h{word:08x};\n"
                   for i, word in enumerate(words(ram)) if word != 0)
embed("instruction_rom.v", "C ROM", rom_body)
embed("sync_data_ram.v", "C RAM", ram_body)
metadata = {"compiler": run("gcc", "-dumpmachine").strip(), "flags": flags,
            "rom_bytes": len(text), "data_bytes": len(data),
            "bss_bytes": symbols["__bss_end"] - symbols["__bss_start"],
            "ram_initial_copy_start": load_start, "ram_initial_copy_end": load_start + len(data),
            "stack_bottom": symbols["__stack_bottom"], "stack_top": symbols["__stack_top"],
            "symbols": symbols,
            "image_sha256": {name: hashlib.sha256((OUT / name).read_bytes()).hexdigest()
                             for name in ("c_program.hex", "c_data.hex")}}
(OUT / "metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
print(f"PASS C demo compiled: ROM={len(text)}/2048 bytes, data={len(data)}, "
      f"BSS={metadata['bss_bytes']}, RAM snapshot=0x{load_start:x}..0x{load_start + len(data):x}, stack=256")
print("Images and ELF:", OUT)
