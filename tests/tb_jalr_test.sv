`timescale 1ns/1ps

module tb_jalr_test;
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
    integer jalr_count = 0;
    integer target_check_count = 0;
    reg [31:0] expected_target;
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
            wave_file = "jalr_test.vcd";

        $dumpfile(wave_file);
        $dumpvars(0, tb_jalr_test);

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
                $fatal(1, "FAIL JALR program unexpectedly accessed RAM pc=%h",
                       debug_pc);
            if (debug_misaligned)
                $fatal(1, "FAIL unexpected misaligned flag pc=%h", debug_pc);
            if (cycles > 100)
                $fatal(1, "FAIL timeout pc=%h instruction=%h",
                       debug_pc, debug_instruction);

            if (dut.u_cpu_core.decoder_jalr_en) begin
                jalr_count = jalr_count + 1;

                case (debug_pc)
                    32'd20: expected_target = 32'd8;
                    32'd32: expected_target = 32'd44;
                    32'd52: expected_target = 32'd64;
                    32'd72: expected_target = 32'd80;
                    default:
                        $fatal(1, "FAIL unexpected JALR execution pc=%h",
                               debug_pc);
                endcase

                if (dut.u_cpu_core.jalr_target !== expected_target)
                    $fatal(1,
                           "FAIL JALR target pc=%h expected=%h actual=%h rs1=%h imm=%h",
                           debug_pc, expected_target,
                           dut.u_cpu_core.jalr_target,
                           dut.u_cpu_core.rs1_data,
                           dut.u_cpu_core.imm);
                target_check_count = target_check_count + 1;
            end
        end
    end

    always @(negedge clk) begin
        if (!reset && debug_pc == instruction_count * 4) begin
            check_reg(0,  32'h00000000);

            // JAL call link and three JALR link values.
            check_reg(1,  32'h00000008);
            check_reg(5,  32'h00000024);
            check_reg(6,  32'h00000038);
            check_reg(7,  32'h0000004c);

            check_reg(2,  32'h0000002d); // odd source address 45
            check_reg(3,  32'h0000003c); // positive-offset base 60
            check_reg(4,  32'h00000054); // negative-offset base 84

            // Function executed and returned to the caller.
            check_reg(10, 32'h00000001);
            check_reg(11, 32'h0000002a);
            check_reg(12, 32'h00000001);

            // Instructions skipped by the three indirect jumps.
            check_reg(13, 32'h00000000);
            check_reg(14, 32'h00000000);
            check_reg(16, 32'h00000000);
            check_reg(17, 32'h00000000);
            check_reg(19, 32'h00000000);

            // Reached targets and completion signature.
            check_reg(15, 32'h00000001);
            check_reg(18, 32'h00000001);
            check_reg(20, 32'h00000001);
            check_reg(21, 32'h0000007b);

            if (jalr_count != 4 || target_check_count != 4)
                $fatal(1,
                       "FAIL JALR counts executions=%0d targets=%0d expected=4",
                       jalr_count, target_check_count);

            $display("FINAL_JALR_REGS x1=%h x5=%h x6=%h x7=%h x10=%h x11=%h x13=%h x15=%h x18=%h x20=%h x21=%h",
                     dut.u_cpu_core.u_regfile.regs[1],
                     dut.u_cpu_core.u_regfile.regs[5],
                     dut.u_cpu_core.u_regfile.regs[6],
                     dut.u_cpu_core.u_regfile.regs[7],
                     dut.u_cpu_core.u_regfile.regs[10],
                     dut.u_cpu_core.u_regfile.regs[11],
                     dut.u_cpu_core.u_regfile.regs[13],
                     dut.u_cpu_core.u_regfile.regs[15],
                     dut.u_cpu_core.u_regfile.regs[18],
                     dut.u_cpu_core.u_regfile.regs[20],
                     dut.u_cpu_core.u_regfile.regs[21]);
            $display("PASS jalr_test.S instructions=%0d cycles=%0d jalr_count=%0d",
                     instruction_count, cycles, jalr_count);
            $finish;
        end
    end

    initial begin
        #10000;
        $fatal(1, "FAIL global timeout");
    end
endmodule
