#!/usr/bin/env python3
"""Export a small-C diagnostic from the original 1 KiB board RTL snapshot."""
import hashlib
import json
import re
import shutil
import subprocess
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reference/最小C原始上板版本"
OUT = ROOT / "build" / ("board-c-diagnostic-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
PACKAGE = OUT / "board_c_diagnostic"
OUT.mkdir(parents=True)
shutil.copytree(BASE / "rtl", PACKAGE / "rtl")
(PACKAGE / "software").mkdir()
shutil.copy2(BASE / "board_top.fdc", PACKAGE / "board_top.fdc")
shutil.copy2(ROOT / "rtl/uart_probe_top.v", PACKAGE / "rtl/uart_probe_top.v")
source_names = [line for line in (BASE / "sources.f").read_text().splitlines() if line]
source_names.append("rtl/uart_probe_top.v")
(PACKAGE / "sources.f").write_text("\n".join(source_names) + "\n")
TOOLS = ROOT / "toolchains/riscv32-unknown-elf/bin"


def run(command, name, cwd=OUT, timeout=120, show=True):
    p = subprocess.run(list(map(str,command)), cwd=cwd, capture_output=True, text=True, timeout=timeout)
    (OUT / name).write_text(" ".join(map(str,command)) + "\n" + p.stdout + p.stderr)
    if p.returncode: raise SystemExit(f"FAIL {name}: {p.stdout}{p.stderr}")
    if show: print(p.stdout.strip(), flush=True)
    return p.stdout


def tool(name): return TOOLS / ("riscv32-unknown-elf-" + name)

# 插入 B/D/Z 阶段标记；不使用字符串、栈、RAM 初始值来输出它们。
start = (BASE / "software/runtime/start.S").read_text()
def marker(char, gpio):
    return f"    li t4, 0x10000000\n    li t5, {gpio}\n    sw t5, 0(t4)\n    li t5, {ord(char)}\n    sw t5, 16(t4)\n"
start = start.replace('_start:\n', '_start:\n' + marker('B',1), 1)
start = start.replace('.Lprepare_bss:\n', '.Lprepare_bss:\n' + marker('D',2), 1)
start = start.replace('.Lcall_main:\n', '.Lcall_main:\n' + marker('Z',4), 1)
(PACKAGE / "software/start_diag.S").write_text(start)
shutil.copy2(ROOT / "software/c_diagnostic/main.c", PACKAGE / "software/main.c")
shutil.copy2(ROOT / "software/runtime/link.ld", PACKAGE / "software/link.ld")
elf = PACKAGE / "software/main.elf"
flags = ["-march=rv32i","-mabi=ilp32","-Os","-ffreestanding","-fno-builtin",
         "-fno-delete-null-pointer-checks","-fno-pic","-fno-pie","-fno-stack-protector",
         "-mno-relax","-nostdlib","-nostartfiles","-Wl,--no-relax,-Map="+str(PACKAGE / "software/main.map")]
run([tool("gcc"),*flags,"-T",PACKAGE / "software/link.ld",PACKAGE / "software/start_diag.S",
     PACKAGE / "software/main.c","-lc","-lgcc","-o",elf],"gcc.log")
symbols = {}
for line in run([tool("nm"),"-n",elf],"nm.log",show=False).splitlines():
    m=re.match(r"^([0-9a-f]+)\s+\S\s+(.+)$",line)
    if m: symbols[m[2]]=int(m[1],16)
for section,name in ((".text","text.bin"),(".data","data.bin")):
    run([tool("objcopy"),"-O","binary","--only-section="+section,elf,OUT / name],name+".log")
(PACKAGE / "software/main.dis").write_text(run([tool("objdump"),"-d",elf],"objdump.log",show=False))
text=(OUT / "text.bin").read_bytes(); data=(OUT / "data.bin").read_bytes()
copy=symbols["__data_load_start"]
assert len(text)<=1024 and copy+len(data)<=768
rom=text+bytes.fromhex("13000000")*((1024-len(text))//4)
ram=bytearray(1024);ram[copy:copy+len(data)]=data
def words(blob): return [int.from_bytes(blob[i:i+4],"little") for i in range(0,len(blob),4)]
delay_lui = [i for i,w in enumerate(words(text)) if w == 0x000f47b7]
delay_addi = [i for i,w in enumerate(words(text)) if w == 0x24078793]
assert len(delay_lui) == len(delay_addi) == 1, "diagnostic delay instruction changed"
# 上板仍是 1,000,000 次空等；仿真仅将该立即数参数缩小为 40。
for name, old, new in (
    ("board_top.v", "    parameter C_PROGRAM = 1,", "    parameter C_PROGRAM = 1,\n    parameter integer DIAG_DELAY_COUNT = 1000000,"),
    ("soc_top.v", "    parameter BOARD_DEMO = 0,", "    parameter BOARD_DEMO = 0,\n    parameter integer DIAG_DELAY_COUNT = 1000000,"),
    ("instruction_rom.v", "    parameter C_PROGRAM = 0,", "    parameter C_PROGRAM = 0,\n    parameter integer DIAG_DELAY_COUNT = 1000000,")):
    p=PACKAGE / "rtl" / name
    source=p.read_text(); assert source.count(old)==1
    p.write_text(source.replace(old,new,1))
for name in ("board_top.v","soc_top.v"):
    p=PACKAGE / "rtl" / name
    source=p.read_text()
    match=re.search(r"(\s*\.C_PROGRAM\s*\(C_PROGRAM\),)",source)
    assert match
    p.write_text(source[:match.end()]+"\n        .DIAG_DELAY_COUNT (DIAG_DELAY_COUNT),"+source[match.end():])
p=PACKAGE / "rtl/instruction_rom.v"
p.write_text(p.read_text().replace("if (C_PROGRAM) begin : g_c_program", """if (C_PROGRAM) begin : g_c_program
        localparam [31:0] DIAG_DELAY_VALUE = DIAG_DELAY_COUNT;
        localparam [19:0] DIAG_DELAY_HI20 = (DIAG_DELAY_VALUE + 32'd2048) >> 12;
        localparam [11:0] DIAG_DELAY_LO12 = DIAG_DELAY_VALUE[11:0];""",1))
for name,blob in (("program.hex",rom),("ram.hex",ram)):
    (PACKAGE / "software" / name).write_text("".join(f"{w:08x}\n" for w in words(blob)))
def embed(filename,label,body):
    p=PACKAGE / "rtl" / filename
    s,count=re.subn(rf"(    // BEGIN GENERATED {label}\n).*?(    // END GENERATED {label})",
        lambda m:m[1]+body+m[2],p.read_text(),flags=re.S)
    assert count==1
    p.write_text(s)
rom_lines=[]
for i,w in enumerate(words(text)):
    value = "{DIAG_DELAY_HI20, 5'd15, 7'b0110111}" if i == delay_lui[0] else (
        "{DIAG_DELAY_LO12, 5'd15, 3'b000, 5'd15, 7'b0010011}" if i == delay_addi[0] else f"32'h{w:08x}")
    rom_lines.append(f"                8'd{i}: c_instruction = {value};\n")
embed("instruction_rom.v","C ROM","".join(rom_lines))
embed("sync_data_ram.v","C RAM","".join(f"            mem[{i}] = 32'h{w:08x};\n" for i,w in enumerate(words(ram)) if w))
sources=[PACKAGE / name for name in source_names]
run(["iverilog","-g2005","-s","board_top","-t","null",*sources],"board.compile.log")
for fault in (0,1):
    exe=OUT / f"test-{fault}.vvp"
    run(["iverilog","-g2012","-s","tb_c_diagnostic",f"-Ptb_c_diagnostic.FAULT={fault}",
         f"-Ptb_c_diagnostic.COPY_START={copy}",f"-Ptb_c_diagnostic.BSS_START={symbols['__bss_start']}",
         "-o",exe,*sources,ROOT / "tests/tb_c_diagnostic.sv"],f"test-{fault}.compile.log")
    run(["vvp",exe],f"test-{fault}.run.log")
run(["iverilog","-g2012","-s","tb_uart_probe","-o",OUT / "probe.vvp",*sources,ROOT / "tests/tb_uart_probe.sv"],"probe.compile.log")
run(["vvp",OUT / "probe.vvp"],"probe.run.log")
readme='''# 最小 C 串口诊断版本

这是原 1 KiB ROM/RAM 版本的独立诊断包，不是 CoreMark。
将 rtl/ 全部 14 个 .v 和 board_top.fdc 加入工程，顶层 board_top，C_PROGRAM=1，27 MHz。
保持 DIAG_DELAY_COUNT=1000000；仿真仅缩短空等时间，UART 仍按 115200 波特率检查。
串口设置 115200 8N1。打开接收窗口后按下、松开复位。
每次启动输出 B、D、Z、M，随后约每 0.1 秒重复一行状态：

| 字符 | 含义 | GPIO |
|---|---|---|
| B | CPU 开始执行启动代码，输出不依赖 RAM | 01 |
| D | 完成初始数据复制 | 02 |
| Z | 完成 BSS 清零 | 04 |
| M | 已进入 C main | 暂保持 04 |
| K（重复） | 初值、BSS、函数和栈检查成功 | 06 |
| I（重复） | initialized 不等于 5，检查 RAM 初始副本及复制 | 81 |
| Z（重复） | 零初值变量检查失败 | 82 |
| S（重复） | 栈上的加法结果不是 6 | 83 |

若串口窗口打开得晚，启动的 BDZM 可以错过，但持续的 K/I/Z/S 仍应可见。
若只有 B/D/Z/M，按最后标记定位后续阶段。D/Z 表示执行到该处，真正数据正确与否由 C 检查判断。
本包使用立即数字符，不依赖 RAM 中的字符串，即使 RAM 初值丢失也能报告 I。
如果使用原版串口完全静默、GPIO=80，可能是 RAM 初始化丢失导致失败字符串为空；尚须实物确认。

若连 B 都没有，将顶层改成 uart_probe_top（其余引脚约束相同），重新编译烧录。
它只使用时钟和 UART，每 0.5 秒发送 U，并且不依赖按钮复位或 CPU：
有 U → 检查 board_top 复位、ROM、CPU；无 U → 检查烧录文件、时钟、UART 引脚和接收设置。
切换顶层需要重新综合、布局布线及下载，不能只在串口里切换。

本地仿真验证正常初值、全零 RAM 故障、持续串口逐位接收和复位重跑，以及独立 UART 探针。
本机未进行 PDS 综合和实物验证。请反馈收到的字符、GPIO、所用包名和综合警告。
'''
(PACKAGE / "README.md").write_text(readme)
manifest={"rom_bytes":len(text),"data_bytes":len(data),"symbols":symbols,
          "normal_and_zero_ram_simulation_passed":True,"physical_board_verified":False,
          "package_sha256":{str(p.relative_to(PACKAGE)):hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in sorted(PACKAGE.rglob('*')) if p.is_file()}}
(PACKAGE / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
archive=OUT / "board_c_diagnostic.zip"
with zipfile.ZipFile(archive,"w",compression=zipfile.ZIP_DEFLATED) as z:
    for p in sorted(PACKAGE.rglob('*')):
        if p.is_file():z.write(p,Path(PACKAGE.name)/p.relative_to(PACKAGE))
print(f"PASS diagnostic: ROM={len(text)}, data={len(data)}, Package={archive}",flush=True)
