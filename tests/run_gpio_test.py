#!/usr/bin/env python3
"""Run a real RV32I GPIO/MMIO program and preserve simulation evidence."""
import hashlib
import json
import shutil
import struct
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tests/programs/gpio_test.S'
RTL = sorted((ROOT / 'rtl').rglob('*.v'))
OUT = ROOT / 'tests/results' / ('gpio-test-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
OUT.mkdir(parents=True)

def hashes():
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in RTL}

def tool(suffix):
    for prefix in ('riscv32-unknown-elf-', 'riscv64-unknown-elf-', 'riscv64-elf-'):
        found = shutil.which(prefix + suffix)
        if found:
            return found
    raise SystemExit('Missing RISC-V tool: ' + suffix)

def logged(command, log, cwd=ROOT):
    try:
        completed = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        (OUT / log).write_text('FAIL process timeout\n')
        raise SystemExit(f'FAIL timeout; results: {OUT}')
    (OUT / log).write_text(' '.join(command) + '\n' + completed.stdout + completed.stderr)
    return completed

before = hashes()
obj, elf, binary = [OUT / ('gpio_test.' + ext) for ext in ('o','elf','bin')]
commands = [
    ([tool('as'), '-march=rv32i', '-mabi=ilp32', '-o', str(obj), str(SOURCE)], 'assemble.log'),
    ([tool('ld'), '-m', 'elf32lriscv', '--no-relax', '-Ttext=0', '-e', '_start',
      '-o', str(elf), str(obj)], 'link.log'),
    ([tool('objcopy'), '-O', 'binary', '--only-section=.text', str(elf), str(binary)], 'objcopy.log'),
]
for command, log in commands:
    if logged(command,log).returncode:
        raise SystemExit(f'FAIL build; see {OUT / log}')
logged([tool('objdump'), '-d', '-M', 'no-aliases', str(elf)], 'disassembly.txt')
(OUT / 'gpio_test.S').write_text(SOURCE.read_text())
blob = binary.read_bytes()
if len(blob) % 4 or len(blob) > 1024:
    raise SystemExit('Invalid instruction ROM size')
words = [struct.unpack_from('<I', blob, i)[0] for i in range(0,len(blob),4)]
(OUT / 'program.hex').write_text(''.join(f'{w:08x}\n' for w in words) +
                                 '00000013\n' * (256-len(words)))
exe = OUT / 'gpio_test.vvp'
compiled = logged(['iverilog','-g2012','-Wall','-s','tb_gpio_test','-o',str(exe),
                   str(ROOT / 'tests/tb_gpio_test.sv'), *map(str,RTL)], 'compile.log')
passed = False
if compiled.returncode == 0:
    run = logged(['vvp',str(exe),f'+N={len(words)}','+WAVE=gpio_test.vcd'], 'run.log',cwd=OUT)
    passed = run.returncode == 0 and 'PASS gpio_test.S' in run.stdout and 'FAIL' not in run.stdout
after = hashes()
passed = passed and before == after
(OUT / 'manifest.json').write_text(json.dumps(
    {'passed':passed,'instruction_count':len(words),'rtl_unchanged':before==after,
     'before':before,'after':after},indent=2))
(OUT / 'report.md').write_text(
    '# GPIO专项测试\n\n' + f'结果：{"PASS" if passed else "FAIL"}\n\n'
    + f'真实汇编程序：{len(words)}条指令；GPIO请求21次、输入读取3次。\n\n'
    + '覆盖SW/SB/SH输出更新、LW/LB/LBU读回、输入a5→3c变化、输入只读、'
      '高字节写入忽略、请求稳定和PC等待、握手不重复、RAM边界哨兵、'
      '未映射地址读零/写忽略，以及输出非零后的复位清零。\n\n'
    + '范围：数字逻辑仿真，不包含实际引脚电平、输入时钟域同步或按钮消抖。\n'
    + f'\nRTL在测试期间未变化：{before==after}\n')
print('gpio_test', 'PASS' if passed else 'FAIL')
print('Results:',OUT)
raise SystemExit(0 if passed else 1)
