"""Assemble a legal OP/OP-IMM program and compare 43 RAM signatures to a software ISA model."""
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / 'toolchains/riscv32-unknown-elf/bin'
MASK = 0xffffffff


def signed(v, bits=32):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def execute(words):
    regs = [0] * 32
    memory = {}
    coverage = set()
    for pc, ins in enumerate(words):
        op, rd, f3 = ins & 127, (ins >> 7) & 31, (ins >> 12) & 7
        rs1, rs2, f7 = (ins >> 15) & 31, (ins >> 20) & 31, ins >> 25
        a, b = regs[rs1], regs[rs2]
        value = None
        if ins == 0x00100073:
            if pc != len(words)-1:
                raise ValueError('EBREAK before end')
            break
        if op == 0x37:
            value = ins & 0xfffff000
            coverage.add('LUI')
        elif op in (0x13, 0x33):
            immediate = op == 0x13
            if immediate:
                if f3 in (1, 5) and not (f7 == 0 or (f3 == 5 and f7 == 32)):
                    raise ValueError(f'bad immediate shift {ins:08x}')
                b = signed(ins >> 20, 12) & MASK
            elif not (f7 == 0 or (f7 == 32 and f3 in (0, 5))):
                raise ValueError(f'bad register ALU {ins:08x}')
            shift = b & 31
            if f3 == 0:
                value = a - b if not immediate and f7 == 32 else a + b
                name = 'SUB' if not immediate and f7 == 32 else 'ADD'
            elif f3 == 1:
                value = a << shift; name = 'SLL'
            elif f3 == 2:
                value = int(signed(a) < signed(b)); name = 'SLT'
            elif f3 == 3:
                value = int(a < b); name = 'SLTU'
            elif f3 == 4:
                value = a ^ b; name = 'XOR'
            elif f3 == 5:
                value = signed(a) >> shift if f7 == 32 else a >> shift
                name = 'SRA' if f7 == 32 else 'SRL'
            elif f3 == 6:
                value = a | b; name = 'OR'
            else:
                value = a & b; name = 'AND'
            if immediate:
                name = {'ADD': 'ADDI', 'SLL': 'SLLI', 'SLT': 'SLTI',
                        'SLTU': 'SLTIU', 'XOR': 'XORI', 'SRL': 'SRLI',
                        'SRA': 'SRAI', 'OR': 'ORI', 'AND': 'ANDI'}[name]
            coverage.add(name)
        elif op == 0x23 and f3 == 2:
            off = signed(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
            addr = (a + off) & MASK
            if addr & 3:
                raise ValueError('misaligned store in arithmetic program')
            memory[addr] = b
            coverage.add('SW')
        elif op == 0x03 and f3 == 2:
            addr = (a + signed(ins >> 20, 12)) & MASK
            value = memory[addr]
            coverage.add('LW')
        else:
            raise ValueError(f'unmodelled instruction {ins:08x}')
        if value is not None and rd:
            regs[rd] = value & MASK
        regs[0] = 0
    required = {'ADD', 'SUB', 'AND', 'OR', 'XOR', 'SLL', 'SRL', 'SRA', 'SLT', 'SLTU',
                'ADDI', 'ANDI', 'ORI', 'XORI', 'SLLI', 'SRLI', 'SRAI', 'SLTI', 'SLTIU',
                'SW', 'LW', 'LUI'}
    if not required <= coverage or len(memory) != 43:
        raise ValueError(f'incomplete arithmetic coverage: missing={required-coverage}, stores={len(memory)}')
    return [memory[256 + 4*i] for i in range(43)], sorted(coverage)


def run(out):
    out = Path(out).resolve(); out.mkdir(parents=True, exist_ok=True)
    source = (ROOT / 'tests/programs/day5_test.S').read_text()
    source = source.split('    # Unsupported encodings must preserve x8=77.')[0] + '    ebreak\n'
    (out / 'arithmetic.S').write_text(source)
    def tool(name):
        return str(TOOLS / ('riscv32-unknown-elf-' + name))
    commands = [
        [tool('as'), '-march=rv32i', '-mabi=ilp32', '-o', 'arithmetic.o', 'arithmetic.S'],
        [tool('ld'), '-m', 'elf32lriscv', '--no-relax', '-Ttext=0', '-e', '_start', '-o', 'arithmetic.elf', 'arithmetic.o'],
        [tool('objcopy'), '-O', 'binary', '--only-section=.text', 'arithmetic.elf', 'arithmetic.bin'],
    ]
    for i, command in enumerate(commands):
        result = subprocess.run(command, cwd=out, capture_output=True, text=True, timeout=30)
        (out / f'build-{i}.log').write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f'assembler step {i} failed: {result.stderr}')
    blob = (out / 'arithmetic.bin').read_bytes()
    if len(blob) % 4 or len(blob) >= 1020:
        raise ValueError(f'invalid ROM length {len(blob)}')
    words = list(struct.unpack('<' + 'I' * (len(blob)//4), blob))
    expected, coverage = execute(words)
    image = words + [0x00000013] * (255-len(words)) + [0x0000006f]
    (out / 'program.hex').write_text(''.join(f'{w:08x}\n' for w in image))
    (out / 'expected.hex').write_text(''.join(f'{w:08x}\n' for w in expected))
    rtl = [str(p) for p in (ROOT / 'rtl').glob('*.v')]
    rtl += [str(p) for p in (ROOT / 'rtl/cpu').glob('*.v')]
    tb = ROOT / 'tests/verification/tb_arithmetic.sv'
    compile_cmd = ['iverilog', '-g2012', '-s', 'tb_arithmetic', '-o', str(out/'sim.vvp'), *rtl, str(tb)]
    result = subprocess.run(compile_cmd, cwd=out, capture_output=True, text=True, timeout=30)
    (out / 'compile.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError('iverilog compile failed: ' + result.stderr)
    result = subprocess.run(['vvp', str(out/'sim.vvp')], cwd=out, capture_output=True, text=True, timeout=30)
    (out / 'simulation.log').write_text(result.stdout + result.stderr)
    if result.returncode or 'PASS arithmetic' not in result.stdout:
        raise RuntimeError('arithmetic simulation failed: ' + result.stdout + result.stderr)
    print(result.stdout.strip())
    print('coverage:', ', '.join(coverage))


if __name__ == '__main__':
    run(sys.argv[1])
