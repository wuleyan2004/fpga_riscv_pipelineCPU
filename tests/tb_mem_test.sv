`timescale 1ns/1ps

module tb_mem_test;
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
    integer store_completions = 0;
    integer load_completions = 0;
    integer physical_stores = 0;
    integer i;
    reg [31:0] previous_pc;
    reg must_hold_pc;
    reg holding_request = 1'b0;
    reg [68:0] saved_request;
    string wave_file;

    task check_reg;
        input integer index;
        input [31:0] expected;
        begin
            if (dut.u_cpu_core.u_regfile.regs[index] !== expected)
                $fatal(1, "FAIL x%0d expected=%h actual=%h pc=%h instruction=%h addr=%h wstrb=%h",
                       index, expected, dut.u_cpu_core.u_regfile.regs[index],
                       debug_pc, debug_instruction, dut.mem_addr, dut.mem_wstrb);
        end
    endtask

    task check_mem;
        input integer index;
        input [31:0] expected;
        begin
            if (dut.u_data_ram.mem[index] !== expected)
                $fatal(1, "FAIL RAM[%0d] expected=%h actual=%h pc=%h instruction=%h addr=%h wstrb=%h",
                       index, expected, dut.u_data_ram.mem[index],
                       debug_pc, debug_instruction, dut.mem_addr, dut.mem_wstrb);
        end
    endtask

    initial begin
        if (!$value$plusargs("N=%d", instruction_count))
            $fatal(1, "FAIL missing instruction count");
        if (!$value$plusargs("WAVE=%s", wave_file))
            wave_file = "mem_test.vcd";

        $dumpfile(wave_file);
        $dumpvars(0, tb_mem_test);

        repeat (3) @(negedge clk);
        if (debug_pc !== 0 || debug_mem_valid !== 0 || debug_misaligned !== 0)
            $fatal(1, "FAIL reset state pc=%h mem_valid=%b misaligned=%b",
                   debug_pc, debug_mem_valid, debug_misaligned);
        reset = 1'b0;
    end

    always @(posedge clk) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (debug_misaligned)
                $fatal(1, "FAIL unexpected misaligned access pc=%h instruction=%h addr=%h wstrb=%h",
                       debug_pc, debug_instruction, dut.mem_addr, dut.mem_wstrb);
            if (cycles > 500)
                $fatal(1, "FAIL timeout pc=%h instruction=%h", debug_pc, debug_instruction);

            previous_pc = debug_pc;
            must_hold_pc = debug_mem_valid && !debug_mem_ready;

            if (debug_mem_valid) begin
                if (holding_request &&
                    {dut.mem_write, dut.mem_wstrb, dut.mem_addr, dut.mem_wdata} !== saved_request)
                    $fatal(1, "FAIL memory request changed while waiting at pc=%h", debug_pc);

                saved_request = {
                    dut.mem_write, dut.mem_wstrb, dut.mem_addr, dut.mem_wdata
                };

                if (debug_mem_ready) begin
                    if (dut.mem_write)
                        store_completions = store_completions + 1;
                    else
                        load_completions = load_completions + 1;
                end
            end
            holding_request = debug_mem_valid && !debug_mem_ready;

            if (dut.u_data_ram.state === 1'b0 &&
                dut.u_data_ram.mem_valid && dut.u_data_ram.mem_write)
                physical_stores = physical_stores + 1;

            #1;
            if (must_hold_pc && debug_pc !== previous_pc)
                $fatal(1, "FAIL PC changed before mem_ready old=%h new=%h",
                       previous_pc, debug_pc);
        end
    end

    always @(negedge clk) begin
        if (!reset && debug_pc == instruction_count * 4) begin
            check_reg(0,  32'h00000000);
            check_reg(1,  32'h00000040);
            check_reg(2,  32'hffffffff);
            check_reg(3,  32'h00000011);
            check_reg(4,  32'h00000022);
            check_reg(5,  32'h00000033);
            check_reg(6,  32'h00000044);
            check_reg(7,  32'hffffff80);
            check_reg(8,  32'h00000123);
            check_reg(9,  32'hfffff800);
            check_reg(10, 32'hffffffff);
            check_reg(11, 32'h44332211);
            check_reg(12, 32'h00000044);
            check_reg(13, 32'h00000044);
            check_reg(14, 32'hffffff80);
            check_reg(15, 32'h00000080);
            check_reg(16, 32'hf8000123);
            check_reg(17, 32'h00000123);
            check_reg(18, 32'h00000123);
            check_reg(19, 32'hfffff800);
            check_reg(20, 32'h0000f800);
            check_reg(21, 32'h00000050);
            check_reg(22, 32'h44332211);
            check_reg(23, 32'h0000007b);
            for (i = 24; i < 32; i = i + 1)
                check_reg(i, 32'h00000000);

            check_mem(16, 32'hffffffff); // byte address 64
            check_mem(17, 32'h44338011); // byte address 68
            check_mem(18, 32'hf8000123); // byte address 72
            check_mem(19, 32'h44332211); // byte address 76

            if (store_completions != 11 || physical_stores != 11)
                $fatal(1, "FAIL Store count completion=%0d physical=%0d expected=11",
                       store_completions, physical_stores);
            if (load_completions != 13)
                $fatal(1, "FAIL Load count=%0d expected=13", load_completions);

            $display("FINAL_REGS x10=%h x11=%h x14=%h x15=%h x16=%h x19=%h x20=%h x22=%h x23=%h",
                     dut.u_cpu_core.u_regfile.regs[10], dut.u_cpu_core.u_regfile.regs[11],
                     dut.u_cpu_core.u_regfile.regs[14], dut.u_cpu_core.u_regfile.regs[15],
                     dut.u_cpu_core.u_regfile.regs[16], dut.u_cpu_core.u_regfile.regs[19],
                     dut.u_cpu_core.u_regfile.regs[20], dut.u_cpu_core.u_regfile.regs[22],
                     dut.u_cpu_core.u_regfile.regs[23]);
            $display("FINAL_RAM RAM[16]=%h RAM[17]=%h RAM[18]=%h RAM[19]=%h",
                     dut.u_data_ram.mem[16], dut.u_data_ram.mem[17],
                     dut.u_data_ram.mem[18], dut.u_data_ram.mem[19]);
            $display("PASS mem_test.S instructions=%0d cycles=%0d stores=%0d loads=%0d",
                     instruction_count, cycles, store_completions, load_completions);
            $finish;
        end
    end

    initial begin
        #10000;
        $fatal(1, "FAIL global timeout");
    end
endmodule
