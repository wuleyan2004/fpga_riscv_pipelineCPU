`timescale 1ns/1ps
module tb_uart_test;
localparam integer CLKS_PER_BIT = 50_000_000 / 115_200;
reg clk=0, reset=1;
always #5 clk=~clk;
wire [7:0] gpio_out;
wire uart_tx_pin;
wire [31:0] pc, instruction;
wire valid, ready, misaligned;
soc_top dut(.clk(clk),.reset(reset),.gpio_in(8'b0),.gpio_out(gpio_out),
 .uart_tx_pin(uart_tx_pin),.debug_pc(pc),.debug_instruction(instruction),
 .debug_mem_valid(valid),.debug_mem_ready(ready),.debug_misaligned(misaligned));

integer n, cycles=0, frame_count=0, starts=0, tx_completions=0, waited_cycles=0;
integer ram_stores=0, status_reads=0;
reg [31:0] previous_pc;
reg should_hold, holding=0, program_done=0, retired_last=0;
reg [68:0] saved_request;
reg [7:0] expected_byte;
string wave;

task check_reg(input integer index,input [31:0] expected);
begin
 if(dut.u_cpu_core.u_regfile.regs[index] !== expected)
  $fatal(1,"FAIL x%0d expected=%h actual=%h pc=%h",index,expected,
    dut.u_cpu_core.u_regfile.regs[index],pc);
end
endtask

task sample_bit(input bit expected,input integer index);
begin
 if(uart_tx_pin !== expected)
  $fatal(1,"FAIL frame=%0d bit=%0d expected=%b actual=%b time=%0t",
    frame_count,index,expected,uart_tx_pin,$time);
end
endtask

// Decode the physical TX pin independently at each bit center.
initial begin
 forever begin
  @(negedge uart_tx_pin);
  if(!reset) begin
   case(frame_count)
    0: expected_byte=8'h41;
    1: expected_byte=8'ha5;
    2: expected_byte=8'h5a;
    default: $fatal(1,"FAIL unexpected extra UART frame");
   endcase
   repeat(CLKS_PER_BIT/2) @(posedge clk); #1;
   sample_bit(0,-1); // start bit
   for(integer i=0;i<8;i=i+1) begin
    repeat(CLKS_PER_BIT) @(posedge clk); #1;
    sample_bit(expected_byte[i],i); // LSB first
   end
   repeat(CLKS_PER_BIT) @(posedge clk); #1;
   sample_bit(1,8); // stop bit
   frame_count=frame_count+1;
  end
 end
end

initial begin
 if(!$value$plusargs("N=%d",n)) $fatal(1,"FAIL missing instruction count");
 if(!$value$plusargs("WAVE=%s",wave)) wave="uart_test.vcd";
 $dumpfile(wave); $dumpvars(0,tb_uart_test);
 repeat(3) @(negedge clk);
 if(uart_tx_pin !== 1 || dut.u_uart.tx_busy !== 0 || pc !== 0)
  $fatal(1,"FAIL initial UART reset");
 reset=0;
end

always @(posedge clk) if(!reset) begin
 cycles=cycles+1;
 if(cycles>16000) $fatal(1,"FAIL timeout pc=%h frames=%0d",pc,frame_count);
 if(misaligned) $fatal(1,"FAIL unexpected misaligned access");
 // The IF PC leads execution in the pipeline; finish only after the final WB.
 if(dut.u_cpu_core.ex_wb_valid_q &&
    (!dut.u_cpu_core.ex_wb_mem_access_q || ready) &&
    dut.u_cpu_core.ex_wb_pc_q == (n-1)*4) retired_last=1;
 previous_pc=pc;
 should_hold=valid && !ready;
 if(valid) begin
  if(holding && saved_request !== {dut.mem_write,dut.mem_wstrb,dut.mem_addr,dut.mem_wdata})
   $fatal(1,"FAIL request changed while UART was busy");
  saved_request={dut.mem_write,dut.mem_wstrb,dut.mem_addr,dut.mem_wdata};
  if(dut.mem_addr==32'h10000010 || dut.mem_addr==32'h10000014) begin
   if(dut.u_uart.mem_valid !== 1 || dut.u_data_ram.mem_valid !== 0 ||
      dut.u_gpio.mem_valid !== 0) $fatal(1,"FAIL UART address routing");
   if(dut.mem_addr==32'h10000010 && dut.mem_write && dut.mem_wstrb[0] &&
      !ready && dut.u_uart.tx_busy) waited_cycles=waited_cycles+1;
   if(dut.mem_addr==32'h10000010 && dut.mem_write && dut.mem_wstrb[0] && ready)
      tx_completions=tx_completions+1;
   if(dut.mem_addr==32'h10000014 && !dut.mem_write && ready)
      status_reads=status_reads+1;
  end
  else if(dut.mem_addr==0) begin
   if(dut.u_data_ram.mem_valid !== 1 || dut.u_uart.mem_valid !== 0)
    $fatal(1,"FAIL RAM routing");
   if(dut.mem_write && dut.u_data_ram.state==0) ram_stores=ram_stores+1;
  end
 end
 if(dut.u_uart.tx_start) begin
  starts=starts+1;
  case(starts)
   1: if(dut.mem_wdata[7:0] !== 8'h41) $fatal(1,"FAIL first start data");
   2: if(dut.mem_wdata[7:0] !== 8'ha5) $fatal(1,"FAIL second start data");
   3: if(dut.mem_wdata[7:0] !== 8'h5a) $fatal(1,"FAIL third start data");
   default: $fatal(1,"FAIL duplicate UART start");
  endcase
 end
 holding=valid && !ready;
 #1;
 if(should_hold && pc !== previous_pc) $fatal(1,"FAIL PC advanced before ready");
end

always @(negedge clk) if(!reset && retired_last && !program_done) begin
 program_done=1;
 check_reg(11,0); check_reg(12,1); check_reg(13,1); check_reg(14,1);
 check_reg(15,0); check_reg(16,0); check_reg(17,0);
 check_reg(18,32'h123); check_reg(19,123);
 if(dut.u_data_ram.mem[0] !== 32'h123 || gpio_out !== 0)
  $fatal(1,"FAIL unrelated RAM/GPIO state changed");
 if(frame_count!=3 || starts!=3 || tx_completions!=3 ||
    waited_cycles<CLKS_PER_BIT || ram_stores!=1 || status_reads<5 ||
    uart_tx_pin !== 1 || dut.u_uart.tx_busy !== 0)
  $fatal(1,"FAIL UART counts frames=%0d starts=%0d completes=%0d waited=%0d RAM=%0d status=%0d",
   frame_count,starts,tx_completions,waited_cycles,ram_stores,status_reads);
 reset=1;
 @(posedge clk); #1;
 if(uart_tx_pin !== 1 || dut.u_uart.tx_busy !== 0 || pc !== 0)
  $fatal(1,"FAIL UART reset");
 $display("PASS uart_test.S frames=%0d starts=%0d waited_cycles=%0d cycles=%0d",
  frame_count,starts,waited_cycles,cycles);
 $finish;
end
initial begin #200000; $fatal(1,"FAIL global timeout"); end
endmodule
