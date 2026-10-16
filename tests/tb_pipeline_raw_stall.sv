`timescale 1ns/1ps

module tb_pipeline_raw_stall;
    // Historical filename; RAW dependencies now use forwarding without bubbles.
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg [31:0] instruction;
    wire [31:0] pc;
    integer stalls = 0;
    integer forwarded_rs1 = 0, forwarded_rs2 = 0, retired = 0;

    always #5 clk = ~clk;

    always @(*) begin
        case (pc)
            32'd0:  instruction = 32'h00500093; // addi x1, x0, 5
            32'd4:  instruction = 32'h00708113; // addi x2, x1, 7
            32'd8:  instruction = 32'h002101b3; // add  x3, x2, x2
            32'd12: instruction = 32'h06300013; // addi x0, x0, 99
            32'd16: instruction = 32'h00200213; // addi x4, x0, 2
            default: instruction = 32'h00000013;
        endcase
    end

    cpu_core_pipeline dut (
        .clk(clk), .reset(reset), .instruction(instruction), .pc(pc),
        .mem_valid(), .mem_write(), .mem_wstrb(),
        .mem_addr(), .mem_wdata(),
        .mem_ready(1'b0), .mem_rdata(32'b0), .debug_misaligned()
    );

    always @(posedge clk) begin
        if (!reset) begin
            if (dut.stall_raw) stalls = stalls + 1;
            if (dut.forward_rs1) forwarded_rs1 = forwarded_rs1 + 1;
            if (dut.forward_rs2) forwarded_rs2 = forwarded_rs2 + 1;
            if (dut.ex_wb_valid_q) retired = retired + 1;
        end
    end

    initial begin
        repeat (2) @(negedge clk);
        reset = 1'b0;

        repeat (7) @(posedge clk);
        #1;
        if (stalls !== 0 || retired !== 5 || forwarded_rs1 !== 2 || forwarded_rs2 !== 1 ||
            dut.u_regfile.regs[1] !== 5 ||
            dut.u_regfile.regs[2] !== 12 ||
            dut.u_regfile.regs[3] !== 24 ||
            dut.u_regfile.regs[4] !== 2 ||
            dut.u_regfile.regs[0] !== 0)
            $fatal(1, "RAW result or stall count incorrect: stalls=%0d", stalls);

        $display("PASS pipeline RAW forwarding stalls=%0d x2=%0d x3=%0d", stalls,
                 dut.u_regfile.regs[2], dut.u_regfile.regs[3]);
        $finish;
    end
endmodule
