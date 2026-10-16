`timescale 1ns/1ps

module tb_arithmetic;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [31:0] rom [0:255];
    reg [31:0] expected [0:42];
    wire [31:0] pc, instruction, mem_addr, mem_wdata, mem_rdata;
    wire mem_valid, mem_write, mem_ready, misaligned;
    wire [3:0] mem_wstrb;
    integer i, cycles = 0, stores = 0;
    assign instruction = rom[pc[9:2]];
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
        $readmemh("program.hex", rom);
        $readmemh("expected.hex", expected);
        for (i=0; i<256; i=i+1) memory.mem[i]=0;
        repeat (3) @(negedge clk);
        reset = 0;
    end
    always @(posedge clk) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (cycles > 1000) $fatal(1, "arithmetic program timeout pc=%h", pc);
            if (misaligned) $fatal(1, "arithmetic program misaligned access");
            if (mem_valid && mem_ready && mem_write) stores = stores + 1;
            #1;
            if (dut.trap_valid_q) begin
                if (dut.trap_cause_q !== 3 || dut.trap_instruction_q !== 32'h00100073)
                    $fatal(1, "arithmetic program ended with wrong trap cause=%0d", dut.trap_cause_q);
                if (stores != 43) $fatal(1, "arithmetic store count=%0d expected=43", stores);
                for (i=0; i<43; i=i+1)
                    if (memory.mem[64+i] !== expected[i])
                        $fatal(1, "signature[%0d] got=%h expected=%h", i, memory.mem[64+i], expected[i]);
                if (dut.u_regfile.regs[0] !== 0) $fatal(1, "x0 changed");
                $display("PASS arithmetic 43 signatures stores=%0d cycles=%0d", stores, cycles);
                $finish;
            end
        end
    end
endmodule
