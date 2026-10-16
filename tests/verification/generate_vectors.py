"""Independent RV32I combinational reference vectors for tb_modules.sv."""
from pathlib import Path
import random
import sys

MASK = 0xffffffff


def signed(v, bits=32):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def alu(a, b, op):
    shift = b & 31
    return {
        0: lambda: a + b, 1: lambda: a - b, 2: lambda: a & b,
        3: lambda: a | b, 4: lambda: a ^ b, 5: lambda: a << shift,
        6: lambda: a >> shift, 7: lambda: signed(a) >> shift,
        8: lambda: int(signed(a) < signed(b)),
        9: lambda: int(a < b),
    }.get(op, lambda: 0)() & MASK


def decoder(ins):
    op, f3, f7 = ins & 127, (ins >> 12) & 7, ins >> 25
    rw = src = aop = mr = mw = br = jal = jalr = lui = auipc = ecall = ebreak = 0
    mret = csr_en = csr_cmd = 0
    imm = 7
    bad = 1
    if op == 0x13:
        imm = 0
        plain = {0: 0, 2: 8, 3: 9, 4: 4, 6: 3, 7: 2}
        if f3 in plain:
            rw = src = 1; aop = plain[f3]; bad = 0
        elif f3 == 1 and f7 == 0:
            rw = src = 1; aop = 5; bad = 0
        elif f3 == 5 and f7 in (0, 32):
            rw = src = 1; aop = 6 if f7 == 0 else 7; bad = 0
    elif op == 0x33:
        regular = {0: 0, 1: 5, 2: 8, 3: 9, 4: 4, 5: 6, 6: 3, 7: 2}
        if f7 == 0:
            rw = 1; aop = regular[f3]; bad = 0
        elif f7 == 32 and f3 in (0, 5):
            rw = 1; aop = 1 if f3 == 0 else 7; bad = 0
    elif op == 0x03:
        imm = 0
        if f3 in (0, 1, 2, 4, 5):
            src = mr = 1; bad = 0
    elif op == 0x23:
        imm = 1
        if f3 in (0, 1, 2):
            src = mw = 1; bad = 0
    elif op == 0x63:
        if f3 in (0, 1, 4, 5, 6, 7):
            br = 1; imm = 2; bad = 0
    elif op == 0x37:
        rw = lui = 1; imm = 3; bad = 0
    elif op == 0x17:
        rw = auipc = 1; imm = 3; bad = 0
    elif op == 0x6f:
        rw = jal = 1; imm = 4; bad = 0
    elif op == 0x67 and f3 == 0:
        rw = jalr = 1; imm = 0; bad = 0
    elif op == 0x0f and f3 == 0:
        bad = 0
    elif ins == 0x00000073:
        ecall = 1; bad = 0
    elif ins == 0x00100073:
        ebreak = 1; bad = 0
    elif ins == 0x30200073:
        mret = 1; bad = 0
    elif op == 0x73 and f3 in (1, 2, 3, 5, 6, 7):
        rw = csr_en = 1; csr_cmd = f3; bad = 0
    parts = [(rw, 1), (src, 1), (aop, 4), (mr, 1), (mw, 1),
             (imm, 3), (br, 1), (jal, 1), (jalr, 1), (lui, 1),
             (auipc, 1), (bad, 1), (ecall, 1), (ebreak, 1),
             (mret, 1), (csr_en, 1), (csr_cmd, 3)]
    value = 0
    for field, width in parts:
        value = (value << width) | field
    return value


def generate(out):
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(0x52495343)
    edges = [0, 1, 2, 31, 32, 33, 0x7fffffff, 0x80000000,
             0xfffffffe, 0xffffffff, 0xaaaaaaaa, 0x55555555]
    pairs = [(a, b) for a in edges for b in edges]
    pairs += [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(160)]
    with (out / 'alu.txt').open('w') as f:
        for op in range(16):
            for a, b in pairs:
                f.write(f'{a:08x} {b:08x} {op:x} {alu(a,b,op):08x}\n')
    with (out / 'branch.txt').open('w') as f:
        for a, b in pairs:
            result = (int(a == b) << 2) | (int(signed(a) < signed(b)) << 1) | int(a < b)
            f.write(f'{a:08x} {b:08x} {result:x}\n')
        for _ in range(800):
            a = rng.getrandbits(32)
            result = 4
            f.write(f'{a:08x} {a:08x} {result:x}\n')
    with (out / 'imm.txt').open('w') as f:
        for raw in range(4096):
            i = raw << 20
            s = ((raw >> 5) << 25) | ((raw & 31) << 7)
            branch_raw = raw << 1
            b = (((branch_raw >> 12) & 1) << 31) | (((branch_raw >> 11) & 1) << 7) | (((branch_raw >> 5) & 63) << 25) | (((branch_raw >> 1) & 15) << 8)
            for ins, typ, imm in ((i, 0, signed(raw, 12)),
                                  (s, 1, signed(raw, 12)),
                                  (b, 2, signed(branch_raw, 13))):
                f.write(f'{ins:08x} {typ:x} {imm&MASK:08x}\n')
        for _ in range(512):
            raw = rng.getrandbits(20)
            f.write(f'{raw<<12:08x} 3 {raw<<12:08x}\n')
            offset = rng.randrange(0, 1 << 21, 2)
            ins = (((offset >> 20) & 1) << 31) | (((offset >> 1) & 1023) << 21) | (((offset >> 11) & 1) << 20) | (((offset >> 12) & 255) << 12)
            f.write(f'{ins:08x} 4 {signed(offset,21)&MASK:08x}\n')
        for typ in (5, 6, 7):
            f.write(f'ffffffff {typ:x} 00000000\n')
    with (out / 'decode.txt').open('w') as f:
        for op in range(128):
            for f3 in range(8):
                for f7 in range(128):
                    ins = (f7 << 25) | (3 << 20) | (2 << 15) | (f3 << 12) | (1 << 7) | op
                    f.write(f'{ins:08x} {decoder(ins):06x}\n')
        for ins in (0x00000073, 0x00100073, 0x000000f3, 0x001000f3,
                    0x00200073, 0x30200073, 0x00001073, 0xffffffff,
                    0x0ff0000f, 0x0330000f, 0x8330000f,
                    0x0000000f, 0x0000100f, 0x0ff0100f):
            f.write(f'{ins:08x} {decoder(ins):06x}\n')
    print('generated ALU=4864 branch=1104 immediate=13315 decoder=131086')


if __name__ == '__main__':
    generate(sys.argv[1])
