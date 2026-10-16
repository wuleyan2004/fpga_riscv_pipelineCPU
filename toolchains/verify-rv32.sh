#!/bin/bash
set -euo pipefail
toolchains_dir=$(cd "$(dirname "$0")" && pwd)
export LC_ALL=C
export PATH="$toolchains_dir/riscv32-unknown-elf/bin:$PATH"
cd "$toolchains_dir/verification"

test "$(riscv32-unknown-elf-gcc -dumpmachine)" = riscv32-unknown-elf
riscv32-unknown-elf-gcc --version
riscv32-unknown-elf-gcc -Q --help=target > defaults.txt
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -print-libgcc-file-name
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -print-file-name=libc.a
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Os -ffreestanding \
    -fno-builtin -fno-stack-protector -mno-relax -c probe.c -o probe.o
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
    -Wl,--no-relax,-e,toolchain_probe,-Ttext=0,-Map=probe.map \
    probe.o -lc -lgcc -o probe.elf
riscv32-unknown-elf-readelf -h -A probe.elf > elf-info.txt
riscv32-unknown-elf-objdump -d -M no-aliases probe.elf > probe.dis
riscv32-unknown-elf-nm --defined-only probe.elf > symbols.txt
riscv32-unknown-elf-nm -u probe.elf > unresolved.txt
test ! -s unresolved.txt
python3 - <<'PY'
from pathlib import Path
import re

info = Path('elf-info.txt').read_text()
assert 'ELF32' in info and 'RISC-V' in info
arch = re.search(r'Tag_RISCV_arch:\s*"([^"]+)"', info).group(1)
assert re.fullmatch(r'rv32i[0-9]+p[0-9]+', arch), arch
dis = Path('probe.dis').read_text()
symbols = Path('symbols.txt').read_text()
for symbol in ('__mulsi3', '__udivsi3', '__umodsi3', 'memcpy'):
    # objdump may choose an alias for a function with several symbol names.
    assert re.search(rf'^\S+ T {symbol}$', symbols, re.MULTILINE), symbol
allowed = set('lui auipc jal jalr beq bne blt bge bltu bgeu lb lh lw lbu lhu '
              'sb sh sw addi slti sltiu xori ori andi slli srli srai '
              'add sub sll slt sltu xor srl sra or and'.split())
instructions = re.findall(r'^\s*[0-9a-f]+:\s+[0-9a-f]{8}\s+(\S+)', dis,
                          re.MULTILINE)
assert instructions and set(instructions) <= allowed, set(instructions) - allowed
print('PASS: true riscv32-unknown-elf target, ELF32 RV32I, C headers,')
print('      Newlib memcpy, software multiply/divide, no unresolved symbols.')
PY
riscv32-unknown-elf-size probe.elf
