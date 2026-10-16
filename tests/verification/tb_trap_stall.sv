`timescale 1ns/1ps

module tb_trap_stall;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    wire [31:0] pc, instruction, mem_addr, mem_wdata, mem_rdata;
    wire mem_valid, mem_write, mem_ready, misaligned;
    wire [3:0] mem_wstrb;
    integer cycles=0, waits=0, writes=0;
    assign instruction = pc == 0 ? 32'h05a00093 :  // addi x1,x0,90
                         pc == 4 ? 32'h00102023 :  // sw x1,0(x0)
                         pc == 8 ? 32'h00100073 :  // ebreak
                         pc == 12 ? 32'h00102223 : // younger sw x1,4(x0)
                         pc == 32'h00007ffc ? 32'h0000006f : 32'h00000013;
    cpu_core_pipeline dut(
        .clk(clk), .reset(reset), .instruction(instruction), .pc(pc),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata), .debug_misaligned(misaligned)
    );
    sync_data_ram memory(
        .clk(clk), .reset(reset), .mem_valid(mem_valid), .mem_write(mem_write),
        .mem_wstrb(mem_wstrb), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata)
    );
    initial begin
        memory.mem[0]=0; memory.mem[1]=0;
        repeat (3) @(negedge clk);
        reset=0;
    end
    always @(posedge clk) if (!reset) begin
        cycles=cycles+1;
        if (cycles>30) $fatal(1, "trap stall timeout");
        if (mem_valid && !mem_ready) waits=waits+1;
        if (mem_valid && mem_ready && mem_write) writes=writes+1;
        #1;
        if (dut.trap_valid_q && cycles>=10) begin
            if (dut.trap_pc_q !== 8 || dut.trap_cause_q !== 3 ||
                dut.trap_instruction_q !== 32'h00100073 ||
                memory.mem[0] !== 90 || memory.mem[1] !== 0 ||
                writes !== 1 || waits < 1 || misaligned)
                $fatal(1, "imprecise trap: cause=%0d ram0=%h ram1=%h writes=%0d waits=%0d",
                    dut.trap_cause_q, memory.mem[0], memory.mem[1], writes, waits);
            $display("PASS trap after pending Store waits=%0d writes=%0d", waits, writes);
            $finish;
        end
    end
endmodule
