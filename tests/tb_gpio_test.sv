`timescale 1ns/1ps
module tb_gpio_test;
reg clk=0, reset=1;
always #5 clk=~clk;
reg [7:0] gpio_in=8'ha5;
wire [7:0] gpio_out;
wire [31:0] pc, instruction;
wire valid, ready, misaligned;
soc_top dut(.clk(clk),.reset(reset),.gpio_in(gpio_in),.gpio_out(gpio_out),
 .debug_pc(pc),.debug_instruction(instruction),.debug_mem_valid(valid),
 .debug_mem_ready(ready),.debug_misaligned(misaligned));
integer n, cycles=0, gpio_accepts=0, gpio_completions=0, ram_stores=0;
integer unmapped_completions=0, input_reads=0;
reg [7:0] expected_out=0;
reg [31:0] old_pc;
reg hold_pc, holding=0;
reg [68:0] request;
reg change_input=0, finished=0, program_done=0;
string wave;
task check_reg(input integer index,input [31:0] expected);
begin
 if(dut.u_cpu_core.u_regfile.regs[index] !== expected)
  $fatal(1,"FAIL x%0d expected=%h actual=%h pc=%h",index,expected,
    dut.u_cpu_core.u_regfile.regs[index],pc);
end
endtask
initial begin
 if(!$value$plusargs("N=%d",n)) $fatal(1,"FAIL missing N");
 if(!$value$plusargs("WAVE=%s",wave)) wave="gpio.vcd";
 $dumpfile(wave); $dumpvars(0,tb_gpio_test);
 repeat(3) @(negedge clk);
 if(gpio_out !== 0 || ready !== 0 || pc !== 0) $fatal(1,"FAIL initial reset");
 reset=0;
end
always @(posedge clk) if(!reset) begin
 cycles=cycles+1;
 if(cycles>400) $fatal(1,"FAIL timeout pc=%h",pc);
 if(misaligned) $fatal(1,"FAIL unexpected misaligned access");
 // Fetch can reach the end before WB. Wait for the final instruction to retire.
 if(dut.u_cpu_core.ex_wb_valid_q &&
    (!dut.u_cpu_core.ex_wb_mem_access_q || ready) &&
    dut.u_cpu_core.ex_wb_pc_q == (n-1)*4) program_done=1;
 old_pc=pc;
 hold_pc=valid && !ready;
 if(valid) begin
  if(holding && request !== {dut.mem_write,dut.mem_wstrb,dut.mem_addr,dut.mem_wdata})
   $fatal(1,"FAIL unstable memory request pc=%h",pc);
  request={dut.mem_write,dut.mem_wstrb,dut.mem_addr,dut.mem_wdata};
  // Verify exactly one selected endpoint, or neither for an unmapped address.
  if(dut.mem_addr < 32'd1024) begin
   if(dut.u_data_ram.mem_valid !== 1 || dut.u_gpio.mem_valid !== 0)
    $fatal(1,"FAIL RAM request routing");
  end else if(dut.mem_addr >= 32'h10000000 && dut.mem_addr < 32'h10000008) begin
   if(dut.u_gpio.mem_valid !== 1 || dut.u_data_ram.mem_valid !== 0)
    $fatal(1,"FAIL GPIO request routing");
   if(ready) begin
    gpio_completions=gpio_completions+1;
    if(!dut.mem_write && dut.mem_addr==32'h10000004) begin
     input_reads=input_reads+1;
     if(input_reads==1) change_input=1;
    end
   end
  end else begin
   if(dut.u_gpio.mem_valid !== 0 || dut.u_data_ram.mem_valid !== 0)
    $fatal(1,"FAIL unmapped request routed to hardware");
   if(ready !== 1 || dut.mem_rdata !== 0) $fatal(1,"FAIL unmapped response");
   unmapped_completions=unmapped_completions+1;
  end
 end
 holding=valid && !ready;
 if(dut.u_data_ram.state==0 && dut.u_data_ram.mem_valid && dut.mem_write)
  ram_stores=ram_stores+1;
 if(dut.u_gpio.state==0 && dut.u_gpio.mem_valid) begin
  gpio_accepts=gpio_accepts+1;
  if(dut.mem_write && dut.mem_addr[31:2]==(32'h10000000>>2) && dut.mem_wstrb[0])
   expected_out=dut.mem_wdata[7:0];
 end
 #1;
 if(gpio_out !== expected_out) $fatal(1,"FAIL GPIO output expected=%h actual=%h",expected_out,gpio_out);
 if(hold_pc && pc !== old_pc) $fatal(1,"FAIL PC changed before ready");
end
always @(negedge clk) if(!reset) begin
 if(change_input) begin
  gpio_in=8'h3c;
  change_input=0;
 end
 if(program_done && !finished) begin
  finished=1;
  check_reg(0,0); check_reg(3,0); check_reg(5,32'hff);
  check_reg(6,32'hffffffff); check_reg(7,32'hff);
  check_reg(8,32'h5a); check_reg(9,32'h5a);
  check_reg(11,32'h23); check_reg(12,32'h78);
  check_reg(17,32'ha5); check_reg(18,32'h3c); check_reg(19,32'h3c);
  check_reg(20,32'h123); check_reg(21,32'h123); check_reg(22,32'h123);
  check_reg(24,0); check_reg(26,0); check_reg(27,32'h78); check_reg(28,123);
  if(dut.u_data_ram.mem[0] !== 32'h123 || dut.u_data_ram.mem[1] !== 32'h123 ||
     dut.u_data_ram.mem[255] !== 32'h123) $fatal(1,"FAIL RAM sentinel corrupted");
  if(gpio_out !== 8'h78) $fatal(1,"FAIL final GPIO output");
  if(gpio_accepts!=gpio_completions || gpio_accepts!=21 || ram_stores!=3 ||
     unmapped_completions!=4 || input_reads!=3)
   $fatal(1,"FAIL counts accept=%0d complete=%0d ram_store=%0d unmapped=%0d input=%0d",
    gpio_accepts,gpio_completions,ram_stores,unmapped_completions,input_reads);
  // Reset after a nonzero output checks reset clearing without assuming RAM reset.
  reset=1;
  @(posedge clk); #1;
  if(gpio_out !== 0 || dut.gpio_ready !== 0 || pc !== 0)
   $fatal(1,"FAIL GPIO reset clearing");
  if(dut.u_data_ram.mem[0] !== 32'h123) $fatal(1,"FAIL RAM changed during reset");
  $display("PASS gpio_test.S cycles=%0d gpio_transactions=%0d input_reads=%0d",cycles,gpio_accepts,input_reads);
  $finish;
 end
end
initial begin #10000; $fatal(1,"FAIL global timeout"); end
endmodule
