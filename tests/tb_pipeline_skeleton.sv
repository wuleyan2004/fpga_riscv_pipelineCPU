`timescale 1ns/1ps

module tb_pipeline_skeleton;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg [31:0] instruction;
    wire [31:0] pc;
    wire mem_valid, mem_write, debug_misaligned;
    wire [3:0] mem_wstrb;
    wire [31:0] mem_addr, mem_wdata;

    always #5 clk = ~clk;

    always @(*) begin
        case (pc)
            32'd0:  instruction = 32'h00500093; // addi x1, x0, 5
            32'd4:  instruction = 32'h00700113; // addi x2, x0, 7
            32'd8:  instruction = 32'h00900193; // addi x3, x0, 9
            default: instruction = 32'h00000013; // nop
        endcase
    end

    cpu_core_pipeline dut (
        .clk(clk), .reset(reset), .instruction(instruction), .pc(pc),
        .mem_valid(mem_valid), .mem_write(mem_write),
        .mem_wstrb(mem_wstrb), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(1'b0), .mem_rdata(32'b0),
        .debug_misaligned(debug_misaligned)
    );

    initial begin
        repeat (2) @(negedge clk);
        if (pc !== 0 || dut.if_ex_valid_q !== 0 || dut.ex_wb_valid_q !== 0)
            $fatal(1, "reset did not clear pipeline validity");

        reset = 1'b0;
        @(posedge clk); #1;
        if (pc !== 4 || !dut.if_ex_valid_q || dut.if_ex_pc_q !== 0 ||
            dut.if_ex_instruction_q !== 32'h00500093 || dut.ex_wb_valid_q)
            $fatal(1, "first instruction did not enter IF/EX");

        @(posedge clk); #1;
        if (pc !== 8 || dut.if_ex_pc_q !== 4 || !dut.ex_wb_valid_q ||
            dut.ex_wb_pc_q !== 0 || dut.ex_wb_result_q !== 5 ||
            !dut.ex_wb_reg_write_q || dut.u_regfile.regs[1] !== 0)
            $fatal(1, "first instruction did not enter EX/WB");

        repeat (3) @(posedge clk);
        #1;
        if (dut.u_regfile.regs[1] !== 5 ||
            dut.u_regfile.regs[2] !== 7 ||
            dut.u_regfile.regs[3] !== 9 ||
            dut.u_regfile.regs[0] !== 0 || mem_valid !== 0 ||
            mem_write !== 0 || debug_misaligned !== 0)
            $fatal(1, "pipeline writeback or inactive memory interface failed");

        reset = 1'b1;
        @(posedge clk); #1;
        if (pc !== 0 || dut.if_ex_valid_q !== 0 || dut.ex_wb_valid_q !== 0)
            $fatal(1, "reset did not flush both pipeline registers");

        $display("PASS pipeline skeleton: IF/EX, EX/WB, valid and writeback");
        $finish;
    end
endmodule
