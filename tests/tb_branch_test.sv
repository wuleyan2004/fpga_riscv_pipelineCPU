`timescale 1ns/1ps

module tb_branch_test;
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
    integer taken_count = 0;
    integer not_taken_count = 0;
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
            wave_file = "branch_test.vcd";

        $dumpfile(wave_file);
        $dumpvars(0, tb_branch_test);

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
                $fatal(1, "FAIL branch program unexpectedly accessed RAM pc=%h",
                       debug_pc);
            if (debug_misaligned)
                $fatal(1, "FAIL unexpected misaligned flag pc=%h", debug_pc);
            if (cycles > 200)
                $fatal(1, "FAIL timeout pc=%h instruction=%h",
                       debug_pc, debug_instruction);

            if (dut.u_cpu_core.decoder_branch_en) begin
                if (dut.u_cpu_core.branch_taken)
                    taken_count = taken_count + 1;
                else
                    not_taken_count = not_taken_count + 1;
            end
        end
    end

    always @(negedge clk) begin
        if (!reset && debug_pc == instruction_count * 4) begin
            check_reg(0,  32'h00000000);
            check_reg(1,  32'h00000005);
            check_reg(2,  32'h00000005);
            check_reg(3,  32'h00000007);
            check_reg(4,  32'hffffffff);
            check_reg(5,  32'h00000001);

            // Taken tests stay 0; not-taken tests become 1.
            check_reg(10, 32'h00000000); // BEQ taken
            check_reg(11, 32'h00000001); // BEQ not taken
            check_reg(12, 32'h00000000); // BNE taken
            check_reg(13, 32'h00000001); // BNE not taken
            check_reg(14, 32'h00000000); // BLT taken
            check_reg(15, 32'h00000001); // BLT not taken
            check_reg(16, 32'h00000000); // BGE taken
            check_reg(17, 32'h00000001); // BGE not taken
            check_reg(18, 32'h00000000); // BLTU taken
            check_reg(19, 32'h00000001); // BLTU not taken
            check_reg(20, 32'h00000000); // BGEU taken
            check_reg(21, 32'h00000001); // BGEU not taken

            check_reg(22, 32'h00000003); // backward loop result
            check_reg(23, 32'h00000003);
            check_reg(24, 32'h0000007b); // completion signature

            // Six forward-taken branches plus two taken loop iterations.
            if (taken_count != 8)
                $fatal(1, "FAIL taken branch count=%0d expected=8", taken_count);
            // Six forward-not-taken branches plus the loop exit.
            if (not_taken_count != 7)
                $fatal(1, "FAIL not-taken branch count=%0d expected=7",
                       not_taken_count);

            $display("FINAL_BRANCH_REGS x10=%h x11=%h x12=%h x13=%h x14=%h x15=%h x16=%h x17=%h x18=%h x19=%h x20=%h x21=%h x22=%h x24=%h",
                     dut.u_cpu_core.u_regfile.regs[10],
                     dut.u_cpu_core.u_regfile.regs[11],
                     dut.u_cpu_core.u_regfile.regs[12],
                     dut.u_cpu_core.u_regfile.regs[13],
                     dut.u_cpu_core.u_regfile.regs[14],
                     dut.u_cpu_core.u_regfile.regs[15],
                     dut.u_cpu_core.u_regfile.regs[16],
                     dut.u_cpu_core.u_regfile.regs[17],
                     dut.u_cpu_core.u_regfile.regs[18],
                     dut.u_cpu_core.u_regfile.regs[19],
                     dut.u_cpu_core.u_regfile.regs[20],
                     dut.u_cpu_core.u_regfile.regs[21],
                     dut.u_cpu_core.u_regfile.regs[22],
                     dut.u_cpu_core.u_regfile.regs[24]);
            $display("PASS branch_test.S instructions=%0d cycles=%0d taken=%0d not_taken=%0d",
                     instruction_count, cycles, taken_count, not_taken_count);
            $finish;
        end
    end

    initial begin
        #10000;
        $fatal(1, "FAIL global timeout");
    end
endmodule
