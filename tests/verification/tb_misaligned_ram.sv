`timescale 1ns/1ps

module tb_misaligned_ram;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire [31:0] pc, instruction, mem_addr, mem_wdata, mem_rdata;
    wire mem_valid, mem_write, mem_ready, debug_misaligned;
    wire [3:0] mem_wstrb;
    reg [31:0] rom [0:31];
    integer i, cycles = 0, requests = 0;
    reg saw_misaligned = 0;

    function [31:0] load_ins(input [11:0] imm, input [2:0] f3,
                              input [4:0] rd, input [4:0] rs1);
        load_ins = {imm, rs1, f3, rd, 7'h03};
    endfunction
    function [31:0] store_ins(input [11:0] imm, input [2:0] f3,
                               input [4:0] rs2, input [4:0] rs1);
        store_ins = {imm[11:5], rs2, rs1, f3, imm[4:0], 7'h23};
    endfunction

    assign instruction = rom[pc[6:2]];
    cpu_core_pipeline dut (
        .clk(clk), .reset(reset), .instruction(instruction), .pc(pc),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_ready(mem_ready),
        .mem_rdata(mem_rdata), .debug_misaligned(debug_misaligned)
    );
    sync_data_ram u_ram (
        .clk(clk), .reset(reset), .mem_valid(mem_valid), .mem_write(mem_write),
        .mem_wstrb(mem_wstrb), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata)
    );

    initial begin
        for (i = 0; i < 32; i = i + 1) rom[i] = 32'h00000013;
        rom[0] = 32'h04000093; // addi x1,x0,64
        rom[1] = load_ins(1, 2, 2, 1);  // lw x2,1(x1), two beats
        rom[2] = load_ins(3, 1, 3, 1);  // lh x3,3(x1), two beats
        rom[3] = load_ins(1, 5, 4, 1);  // lhu x4,1(x1), one beat
        rom[4] = store_ins(2, 2, 2, 1); // sw x2,2(x1), two beats
        rom[5] = store_ins(3, 1, 3, 1); // sh x3,3(x1), two beats
        rom[6] = load_ins(3, 1, 5, 1);  // lh x5,3(x1), forwards
        rom[7] = store_ins(1, 1, 3, 1); // sh x3,1(x1), one beat
        rom[8] = load_ins(0, 2, 6, 1);  // lw x6,0(x1)
        rom[9] = 32'h00128393;           // addi x7,x5,1
        rom[10] = 32'h3fc00413;          // addi x8,x0,1020
        rom[11] = store_ins(1, 1, 3, 8);
        rom[12] = load_ins(1, 1, 9, 8);
        rom[13] = 32'h0000006f;          // finished
        u_ram.mem[16] = 32'h44332211;
        u_ram.mem[17] = 32'h88776655;
        u_ram.mem[255] = 32'h00000000;
        repeat (3) @(negedge clk);
        reset = 0;
    end

    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (mem_valid && !u_ram.state) requests = requests + 1;
        if (debug_misaligned) saw_misaligned = 1;
        if (dut.trap_valid_q) $fatal(1, "unexpected trap cause=%0d", dut.trap_cause_q);
        if (cycles > 220) $fatal(1, "misaligned RAM timeout pc=%h", pc);
        #1;
        if (dut.u_regfile.regs[9] == 32'h00005544) begin
            if (dut.u_regfile.regs[2] !== 32'h55443322 ||
                dut.u_regfile.regs[3] !== 32'h00005544 ||
                dut.u_regfile.regs[4] !== 32'h00003322 ||
                dut.u_regfile.regs[5] !== 32'h00005544 ||
                dut.u_regfile.regs[6] !== 32'h44554411 ||
                dut.u_regfile.regs[7] !== 32'h00005545 ||
                u_ram.mem[16] !== 32'h44554411 ||
                u_ram.mem[17] !== 32'h88775555 ||
                u_ram.mem[255] !== 32'h00554400 ||
                requests != 15 || !saw_misaligned)
                $fatal(1, "wrong RAM recovery: x2=%h x6=%h ram=%h/%h last=%h requests=%0d",
                    dut.u_regfile.regs[2], dut.u_regfile.regs[6],
                    u_ram.mem[16], u_ram.mem[17], u_ram.mem[255], requests);
            $display("PASS misaligned RAM loads/stores and dependent instructions");
            $finish;
        end
    end
endmodule
