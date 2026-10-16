`timescale 1ns/1ps

module tb_auipc_test;
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
    integer auipc_count = 0;
    reg [31:0] expected_result;
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
            wave_file = "auipc_test.vcd";

        $dumpfile(wave_file);
        $dumpvars(0, tb_auipc_test);

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
                $fatal(1, "FAIL AUIPC program unexpectedly accessed RAM pc=%h",
                       debug_pc);
            if (debug_misaligned)
                $fatal(1, "FAIL unexpected misaligned flag pc=%h", debug_pc);
            if (cycles > 100)
                $fatal(1, "FAIL timeout pc=%h instruction=%h",
                       debug_pc, debug_instruction);

            if (dut.u_cpu_core.decoder_auipc_en) begin
                auipc_count = auipc_count + 1;
                expected_result = debug_pc + dut.u_cpu_core.imm;

                if (dut.u_cpu_core.imm[11:0] !== 12'b0)
                    $fatal(1, "FAIL AUIPC immediate low bits are not zero pc=%h imm=%h",
                           debug_pc, dut.u_cpu_core.imm);
                if (dut.u_cpu_core.auipc_result !== expected_result)
                    $fatal(1, "FAIL AUIPC sum pc=%h imm=%h expected=%h actual=%h",
                           debug_pc, dut.u_cpu_core.imm, expected_result,
                           dut.u_cpu_core.auipc_result);
                if (dut.u_cpu_core.rd_data !== expected_result)
                    $fatal(1, "FAIL AUIPC writeback pc=%h expected=%h actual=%h",
                           debug_pc, expected_result, dut.u_cpu_core.rd_data);
            end
        end
    end

    always @(negedge clk) begin
        if (!reset && debug_pc == instruction_count * 4) begin
            check_reg(0, 32'h00000000);
            check_reg(1, 32'h00000000); // PC 0 + 0
            check_reg(2, 32'h00000004); // PC 4 + 0
            check_reg(3, 32'h00001008); // PC 8 + 0x1000
            check_reg(4, 32'h1234500c); // PC 12 + 0x12345000
            check_reg(5, 32'h80000010); // PC 16 + 0x80000000
            check_reg(6, 32'hfffff014); // PC 20 + 0xfffff000
            check_reg(7, 32'h0000007b);

            if (auipc_count != 7)
                $fatal(1, "FAIL AUIPC execution count=%0d expected=7",
                       auipc_count);

            $display("FINAL_AUIPC_REGS x1=%h x2=%h x3=%h x4=%h x5=%h x6=%h x7=%h",
                     dut.u_cpu_core.u_regfile.regs[1],
                     dut.u_cpu_core.u_regfile.regs[2],
                     dut.u_cpu_core.u_regfile.regs[3],
                     dut.u_cpu_core.u_regfile.regs[4],
                     dut.u_cpu_core.u_regfile.regs[5],
                     dut.u_cpu_core.u_regfile.regs[6],
                     dut.u_cpu_core.u_regfile.regs[7]);
            $display("PASS auipc_test.S instructions=%0d cycles=%0d auipc_count=%0d",
                     instruction_count, cycles, auipc_count);
            $finish;
        end
    end

    initial begin
        #10000;
        $fatal(1, "FAIL global timeout");
    end
endmodule
