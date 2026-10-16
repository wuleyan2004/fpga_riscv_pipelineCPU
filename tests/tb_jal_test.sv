`timescale 1ns/1ps

module tb_jal_test;
    reg clk = 1'b0;
    reg reset = 1'b1;
    always #5 clk = ~clk;

    wire [31:0] debug_pc;
    wire [31:0] debug_instruction;
    wire debug_mem_valid;
    wire debug_mem_ready;
    wire debug_misaligned;

    soc_top dut (
        .clk(clk),
        .reset(reset),
        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .debug_mem_valid(debug_mem_valid),
        .debug_mem_ready(debug_mem_ready),
        .debug_misaligned(debug_misaligned)
    );

    integer instruction_count;
    integer cycles = 0;
    integer jal_count = 0;
    integer forward_jal_count = 0;
    integer backward_jal_count = 0;
    string wave_file;

    task check_reg;
        input integer index;
        input [31:0] expected;
        begin
            if (dut.u_cpu_core.u_regfile.regs[index] !== expected)
                $fatal(1,
                       "FAIL x%0d expected=%h actual=%h pc=%h instruction=%h",
                       index, expected,
                       dut.u_cpu_core.u_regfile.regs[index],
                       debug_pc, debug_instruction);
        end
    endtask

    initial begin
        if (!$value$plusargs("N=%d", instruction_count))
            $fatal(1, "FAIL missing instruction count");
        if (!$value$plusargs("WAVE=%s", wave_file))
            wave_file = "jal_test.vcd";

        $dumpfile(wave_file);
        $dumpvars(0, tb_jal_test);

        repeat (3) @(negedge clk);
        if (debug_pc !== 0 || debug_mem_valid !== 0)
            $fatal(1, "FAIL reset state pc=%h mem_valid=%b",
                   debug_pc, debug_mem_valid);
        reset = 1'b0;
    end

    always @(posedge clk) begin
        if (!reset) begin
            cycles = cycles + 1;

            if (debug_mem_valid)
                $fatal(1, "FAIL JAL program unexpectedly accessed RAM pc=%h",
                       debug_pc);
            if (debug_misaligned)
                $fatal(1, "FAIL unexpected misaligned flag pc=%h", debug_pc);
            if (cycles > 100)
                $fatal(1, "FAIL timeout pc=%h instruction=%h",
                       debug_pc, debug_instruction);

            if (dut.u_cpu_core.decoder_jal_en) begin
                jal_count = jal_count + 1;
                if (debug_pc == 32'd4 || debug_pc == 32'd16)
                    forward_jal_count = forward_jal_count + 1;
                if (debug_pc == 32'd44)
                    backward_jal_count = backward_jal_count + 1;
            end
        end
    end

    always @(negedge clk) begin
        if (!reset && debug_pc == instruction_count * 4) begin
            check_reg(0,  32'h00000000);
            check_reg(1,  32'h0000000b);

            // Link values must be the address immediately after each JAL.
            check_reg(5,  32'h00000008);
            check_reg(6,  32'h00000030);

            // These instructions were skipped by JAL.
            check_reg(10, 32'h00000000);
            check_reg(12, 32'h00000000);

            // These instructions are at valid jump targets.
            check_reg(11, 32'h00000001);
            check_reg(13, 32'h00000001);

            check_reg(14, 32'h00000003);
            check_reg(15, 32'h00000003);
            check_reg(16, 32'h0000007b);

            // One forward linked jump, one jal x0, and two backward jumps.
            if (jal_count != 4)
                $fatal(1, "FAIL JAL execution count=%0d expected=4", jal_count);
            if (forward_jal_count != 2)
                $fatal(1, "FAIL forward JAL count=%0d expected=2",
                       forward_jal_count);
            if (backward_jal_count != 2)
                $fatal(1, "FAIL backward JAL count=%0d expected=2",
                       backward_jal_count);

            $display("FINAL_JAL_REGS x5=%h x6=%h x10=%h x11=%h x12=%h x13=%h x14=%h x16=%h",
                     dut.u_cpu_core.u_regfile.regs[5],
                     dut.u_cpu_core.u_regfile.regs[6],
                     dut.u_cpu_core.u_regfile.regs[10],
                     dut.u_cpu_core.u_regfile.regs[11],
                     dut.u_cpu_core.u_regfile.regs[12],
                     dut.u_cpu_core.u_regfile.regs[13],
                     dut.u_cpu_core.u_regfile.regs[14],
                     dut.u_cpu_core.u_regfile.regs[16]);
            $display("PASS jal_test.S instructions=%0d cycles=%0d jal_count=%0d",
                     instruction_count, cycles, jal_count);
            $finish;
        end
    end

    initial begin
        #10000;
        $fatal(1, "FAIL global timeout");
    end
endmodule
