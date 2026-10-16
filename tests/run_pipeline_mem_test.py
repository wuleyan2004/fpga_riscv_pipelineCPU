#!/usr/bin/env python3
"""Check pipeline memory behavior against a byte-addressed software oracle."""
import hashlib
import json
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RTL = sorted((ROOT / "rtl" / "cpu").glob("*.v")) + [ROOT / "rtl" / "sync_data_ram.v"]
OUT = ROOT / "tests" / "results" / ("pipeline-mem-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
OUT.mkdir(parents=True)


def hashes():
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in RTL}


def encode(op, rd_or_data, rs1, imm_or_rs2):
    if op == "ADD":
        return imm_or_rs2 << 20 | rs1 << 15 | rd_or_data << 7 | 0x33
    f3 = {"ADDI": 0, "LB": 0, "LH": 1, "LW": 2, "LBU": 4,
          "LHU": 5, "SB": 0, "SH": 1, "SW": 2}[op]
    imm = imm_or_rs2 & 0xFFF
    if op in ("SB", "SH", "SW"):
        return (imm >> 5) << 25 | rd_or_data << 20 | rs1 << 15 | f3 << 12 | (imm & 31) << 7 | 0x23
    return imm << 20 | rs1 << 15 | f3 << 12 | rd_or_data << 7 | (0x13 if op == "ADDI" else 0x03)


program = []


def emit(op, rd_or_data, rs1, imm_or_rs2):
    program.append((op, rd_or_data, rs1, imm_or_rs2))


emit("ADDI", 1, 0, 64)
for op in ("LB", "LBU"):
    for lane in range(4):
        emit(op, 5, 1, lane)
        emit("ADDI", 6, 5, 1)  # adjacent Load -> ALU dependency
for op in ("LH", "LHU"):
    for lane in (0, 2):
        emit(op, 7, 1, lane)
        emit("ADD", 8, 7, 7)  # both source ports depend on Load
emit("LW", 9, 1, 0)
emit("ADDI", 9, 9, 1)
emit("LW", 0, 1, 0)  # x0 must stay zero, but the read still occurs

# Byte and halfword stores in every legal lane, and immediately dependent data.
emit("ADDI", 3, 0, -128)
for lane in range(4):
    emit("SB", 3, 1, 64 + lane)
emit("ADDI", 3, 0, -1)
for lane in (0, 2):
    emit("SH", 3, 1, 68 + lane)
emit("LW", 4, 1, 8)
emit("SW", 4, 1, 72)  # Load -> Store data
emit("LW", 10, 1, 32)
emit("SW", 4, 10, 0)  # Load -> Store address
emit("LW", 11, 1, 8)
emit("ADD", 12, 11, 11)
emit("LW", 13, 1, 8)
emit("ADDI", 13, 13, 1)
emit("LW", 14, 1, 32)
emit("LW", 14, 14, 0)  # Load -> Load base, rd == rs1
for op, offset in (("LB", 64), ("LBU", 67), ("LH", 68), ("LHU", 70), ("LW", 72)):
    emit(op, 15, 1, offset)
    emit("ADDI", 16, 15, 1)

# RAM 内未对齐访问由 verification/tb_misaligned_ram.sv 单独覆盖；
# 本参考程序保留对齐访问，便于逐笔比对原有总线请求。

# Negative offsets and memory boundary lanes, including Store -> Load order.
emit("ADDI", 18, 0, 128)
for op in ("LB", "LBU", "LH", "LHU", "LW"):
    emit(op, 23, 18, -64)
emit("ADDI", 19, 0, 1020)
for op, offset in (("LB", 3), ("LBU", 3), ("LH", 2), ("LHU", 2), ("LW", 0)):
    emit(op, 24, 19, offset)
emit("SB", 3, 19, 3)
emit("SH", 4, 19, 2)
emit("LW", 25, 19, 0)
emit("SW", 4, 0, 0)
emit("LW", 26, 0, 0)
emit("SB", 0, 0, 1)
emit("LBU", 27, 0, 1)
emit("ADDI", 28, 27, 42)

initial = bytearray((i * 37 + 11) & 255 for i in range(1024))
initial[64:68] = bytes.fromhex("7f ff 00 80")
initial[72:76] = bytes.fromhex("78 56 34 12")
initial[96:100] = (160).to_bytes(4, "little")
initial[1020:1024] = bytes.fromhex("12 34 fe 80")
memory = bytearray(initial)
registers = [0] * 32
retire, requests = [], []
bad_count = stores = effective_stores = 0
source_lines = []

for index, (op, rd_or_data, rs1, operand) in enumerate(program):
    ins = encode(op, rd_or_data, rs1, operand)
    we, value = False, 0
    if op == "ADDI":
        value = (registers[rs1] + operand) & 0xFFFFFFFF
        we = True
        text = f"addi x{rd_or_data}, x{rs1}, {operand}"
    elif op == "ADD":
        value = (registers[rs1] + registers[operand]) & 0xFFFFFFFF
        we = True
        text = f"add x{rd_or_data}, x{rs1}, x{operand}"
    else:
        width = {"LB": 1, "LBU": 1, "LH": 2, "LHU": 2, "LW": 4,
                 "SB": 1, "SH": 2, "SW": 4}[op]
        address = (registers[rs1] + operand) & 0xFFFFFFFF
        assert address < 1024 and address + width <= 1027
        bad = address % width != 0
        bad_count += bad
        write = op in ("SB", "SH", "SW")
        mask, data = 0, 0
        if write:
            stores += 1
            if not bad:
                effective_stores += 1
                payload = registers[rd_or_data].to_bytes(4, "little")[:width]
                memory[address:address + width] = payload
                bus_bytes = bytearray(4)
                for k, byte in enumerate(payload):
                    lane = (address % 4) + k
                    bus_bytes[lane] = byte
                    mask |= 1 << lane
                data = int.from_bytes(bus_bytes, "little")
        elif not bad:
            value = int.from_bytes(memory[address:address + width], "little",
                                   signed=op in ("LB", "LH")) & 0xFFFFFFFF
            we = True
        requests.append((int(write), address, mask, data, int(bad)))
        text = f"{op.lower()} x{rd_or_data}, {operand}(x{rs1})"
    retire.append((index * 4, ins, int(we), rd_or_data, value))
    if we and rd_or_data:
        registers[rd_or_data] = value
    source_lines.append(text)


def words(data):
    return [int.from_bytes(data[i:i + 4], "little") for i in range(0, 1024, 4)]


def hex_words(path, values):
    path.write_text("".join(f"{v:08x}\n" for v in values))


hex_words(OUT / "program.hex", [row[1] for row in retire] + [0x13] * (256 - len(program)))
hex_words(OUT / "initial.hex", words(initial))
hex_words(OUT / "final.hex", words(memory))
(OUT / "program.S").write_text("\n".join(source_lines) + "\n")
(OUT / "retire.txt").write_text("".join(" ".join(f"{v:x}" for v in row) + "\n" for row in retire))
(OUT / "requests.txt").write_text("".join(" ".join(f"{v:x}" for v in row) + "\n" for row in requests))

cases = [("direct_ram", 1, 0, 0, 0), ("buffered", 0, 0, 0, 0),
         ("accept_wait2", 0, 2, 0, 0), ("response_wait5", 0, 0, 5, 0),
         ("variable_wait", 0, 2, 5, 1)]
before = hashes()
results = []
for name, direct, pre, post, vary in cases:
    executable = OUT / f"{name}.vvp"
    compile_cmd = ["iverilog", "-g2012", "-s", "tb_pipeline_mem", "-o", str(executable),
                   f"-Ptb_pipeline_mem.DIRECT={direct}", f"-Ptb_pipeline_mem.PRE_DELAY={pre}",
                   f"-Ptb_pipeline_mem.POST_DELAY={post}", f"-Ptb_pipeline_mem.VARY={vary}",
                   *(str(p) for p in RTL), str(ROOT / "tests" / "tb_pipeline_mem.sv")]
    build = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=30)
    output = build.stdout + build.stderr
    code = build.returncode
    if code == 0:
        run = subprocess.run(["vvp", str(executable), f"+N={len(retire)}", f"+REQUESTS={len(requests)}",
                              f"+BAD={bad_count}", f"+STORES={stores}",
                              f"+EFFECTIVE_STORES={effective_stores}", f"+WAVE={name}.vcd"],
                             cwd=OUT, capture_output=True, text=True, timeout=30)
        output += run.stdout + run.stderr
        code = run.returncode
    (OUT / f"{name}.log").write_text(output)
    passed = code == 0 and "PASS pipeline_mem" in output
    results.append({"name": name, "passed": passed, "direct": direct,
                    "pre_delay": pre, "post_delay": post, "vary": vary})
    print(name, "PASS" if passed else "FAIL")
    print(output.strip())

after = hashes()
passed = all(r["passed"] for r in results) and before == after
manifest = {"passed": passed, "cases": results, "instructions": len(program),
            "requests": len(requests), "stores": stores, "effective_stores": effective_stores,
            "misaligned": bad_count, "rtl_unchanged": before == after,
            "rtl_sha256": before, "final_registers": registers}
(OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
report = ["# 流水线访存验证", "", f"总结果：**{'PASS' if passed else 'FAIL'}**", "",
          f"程序 {len(program)} 条；访存 {len(requests)} 次；Store {stores} 次（有效写入 {effective_stores} 次）；预期错位访问 {bad_count} 次。", "",
          "预期由按字节内存软件模型生成；仿真连接实际 sync_data_ram。", "",
          "| 场景 | RAM 接收前额外等待 | 响应延迟 | 结果 |", "|---|---:|---:|---|"]
for result in results:
    report.append(f"| {result['name']} | {result['pre_delay']} | {result['post_delay']} | {'PASS' if result['passed'] else 'FAIL'} |")
report += ["", "variable_wait 在基准延迟上分别增加 0—2、0—3 拍。", "",
           "检查：全部退休指令/写回顺序、全寄存器值、全 1 KiB RAM、请求稳定、等待时整条流水线保持、实际 RAM 接收/写次数。", "",
           "覆盖：LB/LBU 四字节位置、LH/LHU 两半字、LW，SB 四位置、SH 两位置、SW；负偏移与首尾边界；Load→算术/Store 数据/Store 地址/Load 地址；x0。错位异常在独立测试中验证。", "",
           "本验证范围为流水线核与数据 RAM，不包含 MMIO、整机接线、FPGA 综合或实物验证。", "",
           f"RTL 在测试期间{'未修改' if before == after else '发生变化'}；哈希见 manifest.json。"]
(OUT / "report.md").write_text("\n".join(report) + "\n")
print("Results:", OUT)
raise SystemExit(0 if passed else 1)
