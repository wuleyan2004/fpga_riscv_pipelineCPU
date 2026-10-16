#!/usr/bin/env python3
"""One-command module, instruction, trap, and whole-system RTL verification."""
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / 'tests'
OUT = TESTS / 'results' / ('verification-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
OUT.mkdir(parents=True)
RTL = sorted((ROOT / 'rtl').rglob('*.v'))
RTL_ARGS = [str(p) for p in RTL]
results = []


def hashes():
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in RTL}


def run(name, command, cwd=ROOT, marker=None, timeout=120):
    try:
        p = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True,
                           text=True, errors='replace', timeout=timeout)
        output = p.stdout + p.stderr
        code = p.returncode
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or b'').decode(errors='replace') if isinstance(exc.stdout, bytes) else (exc.stdout or '')
        output += (exc.stderr or b'').decode(errors='replace') if isinstance(exc.stderr, bytes) else (exc.stderr or '')
        output += f'\nTIMEOUT after {timeout}s\n'
        code = None
    except OSError as exc:
        output = f'COMMAND ERROR: {exc}\n'
        code = None
    passed = code == 0 and (marker is None or marker in output)
    log = OUT / (name + '.log')
    log.write_text('$ ' + ' '.join(map(str, command)) + '\n' + output)
    match = re.search(r'^Results:\s*(.+)$', output, re.MULTILINE)
    result = {'name': name, 'passed': passed, 'returncode': code,
              'log': str(log.relative_to(ROOT)),
              'child_results': match.group(1).strip() if match else None,
              'summary': [line.strip() for line in output.splitlines() if 'PASS' in line and 'FAIL' not in line][:5]}
    results.append(result)
    print(f'{name:<24} {"PASS" if passed else "FAIL"}', flush=True)
    if not passed:
        print(output[-1800:], flush=True)
    return passed


before = hashes()
V = TESTS / 'verification'
vectors = OUT / 'vectors'
if run('generate_vectors', [sys.executable, V/'generate_vectors.py', vectors], marker='generated ALU='):
    exe = OUT / 'tb_modules.vvp'
    if run('compile_modules', ['iverilog', '-g2012', '-s', 'tb_modules', '-o', exe,
                               *RTL_ARGS, V/'tb_modules.sv']):
        vector_arg_dir = vectors.relative_to(ROOT)
        run('modules', ['vvp', exe, f'+ALU={vector_arg_dir/"alu.txt"}',
                        f'+BRANCH={vector_arg_dir/"branch.txt"}',
                        f'+IMM={vector_arg_dir/"imm.txt"}',
                        f'+DECODE={vector_arg_dir/"decode.txt"}'], marker='PASS modules')

for name, bench, marker in (
    ('ram', V/'tb_ram.sv', 'PASS RAM'),
    ('timer', TESTS/'tb_timer_mmio.sv', 'PASS timer_mmio'),
    ('performance_counters', TESTS/'tb_perf_counter_mmio.sv', 'PASS perf_counter_mmio'),
):
    exe = OUT / (name + '.vvp')
    if run('compile_' + name, ['iverilog', '-g2012', '-s', bench.stem, '-o', exe,
                              *RTL_ARGS, bench]):
        run(name, ['vvp', exe], marker=marker)

run('arithmetic', [sys.executable, V/'run_arithmetic.py', OUT/'arithmetic'],
    marker='PASS arithmetic 43 signatures')

misaligned_exe = OUT/'tb_misaligned_ram.vvp'
if run('compile_misaligned_ram', ['iverilog', '-g2012', '-s', 'tb_misaligned_ram',
                                  '-o', misaligned_exe, *RTL_ARGS,
                                  V/'tb_misaligned_ram.sv']):
    run('misaligned_ram', ['vvp', misaligned_exe],
        marker='PASS misaligned RAM loads/stores')

trap_exe = OUT/'tb_traps.vvp'
if run('compile_traps', ['iverilog', '-g2012', '-s', 'tb_traps', '-o', trap_exe,
                         *RTL_ARGS, V/'tb_traps.sv']):
    for case in range(12):
        run(f'trap_{case:02d}', ['vvp', trap_exe, f'+CASE={case}'],
            marker=f'PASS trap case={case} ')

stall_exe = OUT/'tb_trap_stall.vvp'
if run('compile_trap_stall', ['iverilog', '-g2012', '-s', 'tb_trap_stall', '-o', stall_exe,
                              *RTL_ARGS, V/'tb_trap_stall.sv']):
    run('trap_pending_store', ['vvp', stall_exe], marker='PASS trap after pending Store')

csr_exe = OUT/'tb_csr_trap_return.vvp'
if run('compile_csr_trap_return', ['iverilog', '-g2012', '-s', 'tb_csr_trap_return',
                                   '-o', csr_exe, *RTL_ARGS, V/'tb_csr_trap_return.sv']):
    run('csr_trap_return', ['vvp', csr_exe],
        marker='PASS CSR trap return and six CSR operations')

run('rom_trap_handler', [sys.executable, V/'run_rom_trap_handler.py', OUT/'rom_trap'],
    marker='PASS ROM trap handler six scenarios')
run('m_emulation', [sys.executable, V/'run_m_emulation.py', OUT/'m_emulation'],
    marker='PASS RV32M software emulation')

soc_trap_dir = OUT/'soc_trap'
soc_trap_dir.mkdir()
(soc_trap_dir/'program.hex').write_text('00000073\n' + '00000013\n'*510 + '0000006f\n')
soc_trap_exe = soc_trap_dir/'tb_soc_trap_vector.vvp'
if run('compile_soc_trap_vector', ['iverilog', '-g2012', '-s', 'tb_soc_trap_vector',
                                   '-o', soc_trap_exe, *RTL_ARGS, V/'tb_soc_trap_vector.sv']):
    run('soc_trap_vector', ['vvp', soc_trap_exe], cwd=soc_trap_dir,
        marker='PASS SoC ECALL to file-ROM trap vector')

for name, script, marker in (
    ('forwarding_branches_jumps', 'run_pipeline_forward_test.py', 'PASS pipeline_forward'),
    ('loads_stores_wait_states', 'run_pipeline_mem_test.py', 'PASS pipeline_mem'),
    ('lui_auipc', 'run_pipeline_upper_test.py', 'PASS pipeline_upper'),
    ('gpio_mmio', 'run_gpio_test.py', 'gpio_test PASS'),
    ('uart_mmio', 'run_uart_test.py', 'uart_test PASS'),
    ('c_runtime', 'run_c_runtime_test.py', 'PASS c_runtime'),
):
    run(name, [sys.executable, TESTS/script], marker=marker)

if run('build_coremark_image', [sys.executable, ROOT/'software/build_coremark.py',
                                '--run', 'performance', '--iterations', '1',
                                '--profile', '--no-embed'], marker='PASS CoreMark', timeout=120):
    run('coremark_soc', [sys.executable, TESTS/'run_coremark_test.py',
                         '--run', 'performance', '--iterations', '1', '--profile'],
        marker='PASS performance official CRCs=', timeout=420)

for name, bench, marker in (
    ('board_demo', TESTS/'tb_board_demo.sv', 'PASS board_demo.S'),
    ('board_inputs_reset', TESTS/'tb_board_inputs.sv', 'PASS board_inputs'),
):
    exe = OUT/(name + '.vvp')
    if run('compile_' + name, ['iverilog', '-g2012', '-s', bench.stem, '-o', exe,
                              *RTL_ARGS, bench]):
        run(name, ['vvp', exe], marker=marker)

after = hashes()
unchanged = before == after
passed = unchanged and all(item['passed'] for item in results)
manifest = {'passed': passed, 'rtl_unchanged': unchanged,
            'rtl_sha256_before': before, 'rtl_sha256_after': after,
            'results': results}
(OUT/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')

rows = '\n'.join(f'| {item["name"]} | {"PASS" if item["passed"] else "FAIL"} | '
                 f'[{item["log"]}](../{Path(item["log"]).relative_to("tests/results")}) |'
                 for item in results)
report = f'''# CPU 自动化验证报告

结果：**{'PASS' if passed else 'FAIL'}**。RTL SHA-256 前后{'一致' if unchanged else '不一致'}。

运行命令：`python3 tests/run_all_tests.py`。

## 覆盖范围

- 模块级：ALU 4864 向量、分支比较 1104 向量、立即数 13315 向量、译码 131086 向量，寄存器堆写入/x0，RAM 的 16 种字节掩码及边界，计时器和性能计数器。
- 指令级：真实汇编的 43 个算术/移位/比较结果签名；LB/LBU/LH/LHU/LW、SB/SH/SW 的字节选择与符号扩展；RAM 内未对齐半字和字访存的单次及双次访问；六类分支、JAL/JALR、LUI/AUIPC、前递及不同访存等待；12 个异常场景（非法指令、ECALL、EBREAK、取指及越界 Load/Store 地址错位），旧 Store 等待期间出现 EBREAK 的顺序检查，以及 CSR 读写、非法 CSR、异常处理程序和 MRET 返回。
- 异常入口集成：默认入口与 CSR/MRET 返回测试；链接后的 ROM 处理程序验证 ECALL、EBREAK 返回、八种 M 扩展指令的异常模拟，以及未知非法编码、取指和越界访存地址未对齐记录后停机。
- CPU/SoC：GPIO 与 UART MMIO 汇编程序、板级 `OK\\n` 串口位级接收、按钮同步与复位、C 程序启动与两次重启、CoreMark 一次迭代和两次启动的 CRC/串口检查。

| 指令组 | 已验证的已实现指令 | 主要证据 |
|---|---|---|
| U/J | LUI、AUIPC、JAL、JALR | `lui_auipc`、`forwarding_branches_jumps` |
| Branch | BEQ、BNE、BLT、BGE、BLTU、BGEU | `forwarding_branches_jumps` |
| Load | LB、LH、LW、LBU、LHU | `loads_stores_wait_states` |
| Store | SB、SH、SW | `loads_stores_wait_states`、`arithmetic` |
| OP-IMM | ADDI、SLTI、SLTIU、XORI、ORI、ANDI、SLLI、SRLI、SRAI | `arithmetic` |
| OP | ADD、SUB、SLL、SLT、SLTU、XOR、SRL、SRA、OR、AND | `arithmetic` |
| MISC-MEM | FENCE | `modules` |
| SYSTEM | ECALL、EBREAK、CSR 读写、MRET | `trap_01`、`trap_02`、`trap_pending_store`、`csr_trap_return` |

## 结果明细

| 测试 | 结果 | 日志 |
|---|---|---|
{rows}

## 已知限制

- 本轮是 RTL 仿真，未覆盖 FPGA 综合、时序收敛与实物板测试。
- CoreMark 是一次迭代短跑，CRC 检查通过，但不构成有效 CoreMark 分数。
- 复位默认异常入口为 `0x7ffc`；启动代码初始化栈后把 ROM 内的 `__trap_entry` 写入 `mtvec`。若更早发生异常，仍会到默认入口。ECALL/EBREAK 记录后跳过并返回；M 扩展乘除指令由软件模拟；RAM 未对齐访存由硬件拆分；其余非法编码和不可恢复的未对齐仍停机。
- 当前仅实现机器态同步异常所需的 CSR 子集和 MRET，尚无中断、权限级切换或未映射地址访问错误。
- 当前 decoder 支持 RV32I FENCE；FENCE.I 属于 Zifencei 扩展，仍按非法指令处理。
- 未进行形式验证或所有程序状态的穷举；组合模块的译码控制组合已穷举，动态流水线使用定向程序和独立参考值。
'''
(OUT/'report.md').write_text(report)
print('RTL unchanged:', 'PASS' if unchanged else 'FAIL')
print('ALL TESTS:', 'PASS' if passed else 'FAIL')
print('Results:', OUT)
raise SystemExit(0 if passed else 1)
