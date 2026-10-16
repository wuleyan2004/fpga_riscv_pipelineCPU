#!/usr/bin/env python3
"""Compile and execute the C startup on the real pipeline and synchronous RAM."""
import struct
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tests/results' / ('c-runtime-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
OUT.mkdir(parents=True)
TOOLS = ROOT / 'toolchains/riscv32-unknown-elf/bin'


def tool(name):
    return str(TOOLS / ('riscv32-unknown-elf-' + name))


def run(args, log):
    result = subprocess.run(args, cwd=OUT, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    (OUT / log).write_text(output)
    if result.returncode:
        raise RuntimeError(output or f'{args[0]} failed: {result.returncode}')
    return output


(OUT / 'main.c').write_text('''#include <stdint.h>
volatile uint32_t initialized = 5;
volatile uint32_t result;
volatile uint32_t visits;
const char message[] = "OK";
__attribute__((noinline)) static uint32_t fold(uint32_t x) {
    volatile uint32_t local[4] = {x, x + 1, x + 2, x + 3};
    return local[0] + local[1] + local[2] + local[3];
}
int main(void) {
    if (initialized != 5 || result != 0 || visits != 0 ||
        *(volatile const char *)&message[1] != 'K') return 1;
    visits = 1;
    result = fold(initialized) + *(volatile const char *)&message[1];
    initialized = 99;
    return 0;
}
''')

command = [tool('gcc'), '-march=rv32i_zicsr', '-mabi=ilp32', '-Os', '-ffreestanding',
           '-fno-builtin', '-fno-pic', '-fno-pie', '-fno-stack-protector',
           '-mno-relax', '-nostdlib', '-nostartfiles',
           # The small runtime test uses a 160-byte stack.
           '-Wl,--no-relax,-Map=main.map,--defsym=__stack_size=160',
           '-T', str(ROOT / 'software/runtime/link.ld'),
           str(ROOT / 'software/runtime/start.S'), str(ROOT / 'software/runtime/trap.S'),
           str(ROOT / 'software/runtime/trap_emulate_m.c'),
           'main.c', '-lc', '-lgcc', '-o', 'main.elf']
run(command, 'compile.log')
symbol_output = run([tool('nm'), '-n', 'main.elf'], 'symbols.log')
symbols = {parts[2]: int(parts[0], 16) for line in symbol_output.splitlines()
           if len(parts := line.split()) == 3}
run([tool('objdump'), '-h', '-d', 'main.elf'], 'disassembly.log')
for section, filename in (('.text', 'text.bin'), ('.data', 'data.bin')):
    run([tool('objcopy'), '-O', 'binary', '--only-section=' + section,
         'main.elf', filename], filename + '.log')

text = (OUT / 'text.bin').read_bytes()
data = (OUT / 'data.bin').read_bytes()
assert symbols['_start'] == 0 and len(text) <= 2048
assert symbols['__data_load_end'] <= symbols['__stack_bottom']
assert len(data) == symbols['__data_end'] - symbols['__data_start']
imem = text + struct.pack('<I', 0x00000013) * ((2048 - len(text)) // 4)
# Runtime globals/BSS are deliberately dirty, so startup must do the work.
ram = bytearray(b'\xa5' * 1024)
start = symbols['__data_load_start']
ram[start:start + len(data)] = data
for filename, blob in (('program.hex', imem), ('ram-preload.hex', ram)):
    (OUT / filename).write_text(''.join(f'{word[0]:08x}\n'
        for word in struct.iter_unpack('<I', blob)))

tb = '''module tb_c_runtime;
reg clk=0;
always #5 clk=~clk;
reg reset=1;
wire [31:0] debug_pc;
wire debug_misaligned;
soc_top #(.BOARD_DEMO(0), .UART_CLK_FREQ(27000000)) dut (
 .clk(clk), .reset(reset), .gpio_in(8'b0), .gpio_out(), .uart_tx_pin(),
 .debug_pc(debug_pc), .debug_instruction(), .debug_mem_valid(),
 .debug_mem_ready(), .debug_misaligned(debug_misaligned));
localparam [31:0] HALT = 32'h@HALT@;
integer boot, cycle, i;
reg finished;
initial begin
 #1;
 $readmemh("ram-preload.hex", dut.u_data_ram.mem);
 for (boot=0; boot<2; boot=boot+1) begin
  // On the second boot the initialized variable is still 99 and BSS nonzero.
  reset=1;
  repeat(3) @(negedge clk);
  reset=0;
  finished=0;
  for (cycle=0; cycle<5000 && !finished; cycle=cycle+1) begin
   @(posedge clk); #1;
   if (debug_misaligned) $fatal(1,"misaligned access");
   if (dut.u_cpu_core.ex_wb_valid_q &&
       dut.u_cpu_core.ex_wb_pc_q == HALT) begin
    if (dut.u_cpu_core.u_regfile.regs[10] !== 0)
     $fatal(1,"main returned an error");
    if (dut.u_data_ram.mem[@INITIALIZED@] !== 99 ||
        dut.u_data_ram.mem[@RESULT@] !== 101 ||
        dut.u_data_ram.mem[@VISITS@] !== 1)
     $fatal(1,"C globals, constant or stack calculation failed");
    if (dut.u_cpu_core.u_regfile.regs[2] !== 1024)
     $fatal(1,"main did not restore the aligned stack pointer");
    for(i=@COPY_START@; i<@COPY_END@; i=i+1)
     if (dut.u_data_ram.mem[i] !== preload_word(i))
      $fatal(1,"initial-data snapshot was overwritten");
    finished=1;
    $display("PASS C startup boot=%0d cycles=%0d result=101",boot,cycle);
   end
  end
  if (!finished) $fatal(1,"startup timed out");
  @(negedge clk);
 end
 $display("PASS c_runtime: data copy, BSS zero, rodata, stack, calls, return, reset");
 $finish;
end
reg [31:0] initial_ram [0:255];
initial $readmemh("ram-preload.hex", initial_ram);
function [31:0] preload_word;
input integer index;
begin preload_word=initial_ram[index]; end
endfunction
endmodule
'''
values = {'HALT': f"{symbols['__boot_halt']:08x}",
          'INITIALIZED': str(symbols['initialized'] // 4),
          'RESULT': str(symbols['result'] // 4), 'VISITS': str(symbols['visits'] // 4),
          'COPY_START': str(symbols['__data_load_start'] // 4),
          'COPY_END': str(symbols['__data_load_end'] // 4)}
for key, value in values.items():
    tb = tb.replace('@' + key + '@', value)
(OUT / 'tb.sv').write_text(tb)
rtl = sorted((ROOT / 'rtl/cpu').glob('*.v'))
rtl += [ROOT / 'rtl' / name for name in
        ('soc_top.v', 'instruction_rom.v', 'sync_data_ram.v', 'gpio_mmio.v',
         'uart_mmio.v', 'uart_tx.v', 'timer_mmio.v', 'perf_counter_mmio.v')]
run(['iverilog', '-g2012', '-s', 'tb_c_runtime', '-o', 'test.vvp',
     *map(str, rtl), 'tb.sv'], 'iverilog.log')
output = run(['vvp', 'test.vvp'], 'simulation.log')
assert 'PASS c_runtime:' in output
print(output.strip())
print('Results:', OUT)
