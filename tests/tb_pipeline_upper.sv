`timescale 1ns/1ps

// Check architectural writes in order, including redirects and memory waits.
module tb_pipeline_upper;
    parameter DIRECT = 1, PRE_DELAY = 0, POST_DELAY = 0;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire [31:0] pc, instruction, mem_addr, mem_wdata, mem_rdata;
    wire mem_valid, mem_write, mem_ready, debug_misaligned;
    wire [3:0] mem_wstrb;
    reg [31:0] rom[0:255];
    assign instruction = rom[pc[9:2]];
    cpu_core_pipeline dut (
        .clk(clk), .reset(reset), .instruction(instruction), .pc(pc),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_ready(mem_ready),
        .mem_rdata(mem_rdata), .debug_misaligned(debug_misaligned)
    );
    // Reuse the latency adapter around the actual synchronous data RAM.
    pipeline_mem_fixture #(.DIRECT(DIRECT), .PRE_DELAY(PRE_DELAY),
                          .POST_DELAY(POST_DELAY)) memory (
        .clk(clk), .reset(reset), .mem_valid(mem_valid), .mem_write(mem_write),
        .mem_wstrb(mem_wstrb), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata)
    );

    function automatic [31:0] upper(input [6:0] opcode, input [4:0] rd,
                                     input [19:0] imm);
        upper = {imm, rd, opcode};
    endfunction
    function automatic [31:0] immediate(input [6:0] opcode, input [4:0] rd,
                                         input [4:0] rs1, input integer imm);
        immediate = {imm[11:0], rs1, 3'b000, rd, opcode};
    endfunction
    function automatic [31:0] lw(input [4:0] rd, input [4:0] rs1, input integer imm);
        lw = {imm[11:0], rs1, 3'b010, rd, 7'h03};
    endfunction
    function automatic [31:0] sw(input [4:0] rs2, input [4:0] rs1, input integer imm);
        sw = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'h23};
    endfunction

    reg [31:0] expected_pc[0:127], expected_ins[0:127], expected_value[0:127];
    reg expected_we[0:127];
    reg [4:0] expected_rd[0:127];
    reg [31:0] golden_regs[0:31], cursor = 0, value, base;
    reg [19:0] upper_imms[0:5];
    integer n = 0, retired = 0, i, j, cycles = 0;
    integer raw_bubbles = 0, memory_holds = 0, upper_retired = 0;
    integer upper_forwarded = 0;
    reg retiring;
    string wave;

    task automatic emit(input [31:0] ins, input we, input [4:0] rd,
                        input [31:0] result);
        begin
            rom[cursor[9:2]] = ins;
            expected_pc[n] = cursor;
            expected_ins[n] = ins;
            expected_we[n] = we;
            expected_rd[n] = rd;
            expected_value[n] = result;
            n = n + 1;
            cursor = cursor + 4;
        end
    endtask

    initial begin
        if (!$value$plusargs("WAVE=%s", wave)) wave = "upper.vcd";
        $dumpfile(wave); $dumpvars(0, tb_pipeline_upper);
        for (i = 0; i < 256; i = i + 1) begin
            rom[i] = 32'h00000013;
            memory.ram.mem[i] = 0;
        end
        for (i = 0; i < 32; i = i + 1) golden_regs[i] = 0;
        upper_imms[0] = 20'h00000; upper_imms[1] = 20'h00001;
        upper_imms[2] = 20'h7ffff; upper_imms[3] = 20'h80000;
        upper_imms[4] = 20'hfffff; upper_imms[5] = 20'h12345;
        for (i = 0; i < 6; i = i + 1) begin
            value = {upper_imms[i], 12'b0};
            emit(upper(7'h37, 5, upper_imms[i]), 1, 5, value);
            emit(immediate(7'h13, 6, 5, 1), 1, 6, value + 1);
            value = cursor + {upper_imms[i], 12'b0};
            emit(upper(7'h17, 7, upper_imms[i]), 1, 7, value);
            emit(immediate(7'h13, 8, 7, -1), 1, 8, value - 1);
        end
        // U-immediate bits overlap both apparent source fields of the producer.
        emit(immediate(7'h13, 5, 0, 99), 1, 5, 99);
        emit(upper(7'h37, 6, 20'h00528), 1, 6, 32'h00528000);
        emit(upper(7'h17, 7, 20'h00630), 1, 7, cursor + 32'h00630000);
        emit(upper(7'h37, 0, 20'hfffff), 1, 0, 32'hfffff000);
        emit(upper(7'h17, 0, 20'h80000), 1, 0, cursor + 32'h80000000);
        emit(immediate(7'h13, 9, 0, 3), 1, 9, 3);

        // U-type results feed Store data and Load/Store addresses.
        emit(immediate(7'h13, 1, 0, 64), 1, 1, 64);
        emit(upper(7'h37, 12, 20'h12345), 1, 12, 32'h12345000);
        emit(sw(12, 1, 0), 0, 0, 0);
        value = cursor + 32'hffff8000;
        emit(upper(7'h17, 13, 20'hffff8), 1, 13, value);
        emit(immediate(7'h13, 14, 13, 1), 1, 14, value + 1);
        emit(lw(15, 1, 0), 1, 15, 32'h12345000);
        emit(upper(7'h37, 16, 20'h00078), 1, 16, 32'h00078000);
        emit(lw(18, 1, 0), 1, 18, 32'h12345000);
        value = cursor + 32'h00090000;
        emit(upper(7'h17, 19, 20'h00090), 1, 19, value);
        emit(immediate(7'h13, 20, 19, 1), 1, 20, value + 1);
        base = cursor;
        emit(upper(7'h17, 21, 0), 1, 21, base);
        emit(sw(12, 21, 64 - base), 0, 0, 0);
        emit(upper(7'h37, 22, 0), 1, 22, 0);
        emit(lw(23, 22, 64), 1, 23, 32'h12345000);

        // AUIPC -> JALR dependency; a wrong-path LUI must be flushed.
        base = cursor;
        emit(upper(7'h17, 24, 0), 1, 24, base);
        emit(immediate(7'h67, 25, 24, 12), 1, 25, cursor + 4);
        rom[cursor[9:2]] = upper(7'h37, 31, 20'hdeadb);
        cursor = cursor + 4;
        emit(upper(7'h17, 26, 1), 1, 26, cursor + 32'h1000);
        emit(upper(7'h37, 27, 0), 1, 27, 0);
        emit(32'h000d8463, 0, 0, 0); // beq x27, x0, +8
        rom[cursor[9:2]] = upper(7'h17, 31, 20'hdeadb);
        cursor = cursor + 4;
        emit(upper(7'h17, 28, 20'h80000), 1, 28, cursor + 32'h80000000);

        // Jump near 2^32 to check that AUIPC's addition wraps to 32 bits.
        emit(upper(7'h37, 29, 0), 1, 29, 0);
        emit(immediate(7'h13, 29, 29, -32), 1, 29, 32'hffffffe0);
        emit(immediate(7'h67, 0, 29, 0), 1, 0, cursor + 4);
        rom[cursor[9:2]] = upper(7'h37, 31, 20'hbad00);
        cursor = 32'hffffffe0;
        emit(upper(7'h17, 30, 1), 1, 30, 32'h00000fe0);
        emit(immediate(7'h13, 30, 30, 1), 1, 30, 32'h00000fe1);
        emit(upper(7'h17, 31, 20'hfffff), 1, 31, 32'hffffefe8);
        emit(immediate(7'h13, 31, 31, 1), 1, 31, 32'hffffefe9);
        emit(upper(7'h37, 2, 20'h80000), 1, 2, 32'h80000000);
        emit(upper(7'h17, 3, 1), 1, 3, 32'h00000ff4);

        repeat (3) @(negedge clk);
        reset = 0;
    end

    always @(posedge clk) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (cycles > 1500) $fatal(1, "timeout");
            if (dut.stall_raw && !dut.stall_mem) raw_bubbles = raw_bubbles + 1;
            if (dut.stall_mem) memory_holds = memory_holds + 1;
            if (!dut.stall_mem && (dut.forward_rs1 || dut.forward_rs2) &&
                (dut.ex_wb_instruction_q[6:0] == 7'h37 ||
                 dut.ex_wb_instruction_q[6:0] == 7'h17)) upper_forwarded = upper_forwarded + 1;
            if (debug_misaligned) $fatal(1, "unexpected misaligned access");
            if (dut.if_ex_valid_q &&
                (dut.ex_opcode == 7'h37 || dut.ex_opcode == 7'h17)) begin
                if (dut.ex_uses_rs1 || dut.ex_uses_rs2 || dut.stall_raw || dut.ex_mem_access)
                    $fatal(1, "U-type has a false source dependency or memory access");
            end
            retiring = dut.ex_wb_valid_q && (!dut.ex_wb_mem_access_q || mem_ready);
            if (retiring) begin
                if (dut.ex_wb_pc_q !== expected_pc[retired] ||
                    dut.ex_wb_instruction_q !== expected_ins[retired] ||
                    dut.u_regfile.rd_we !== expected_we[retired])
                    $fatal(1, "retirement mismatch step=%0d PC=%h expected=%h",
                           retired, dut.ex_wb_pc_q, expected_pc[retired]);
                if (expected_we[retired]) begin
                    if (dut.ex_wb_rd_q !== expected_rd[retired] ||
                        dut.ex_wb_writeback_data !== expected_value[retired])
                        $fatal(1, "writeback mismatch PC=%h got=%h expected=%h",
                               dut.ex_wb_pc_q, dut.ex_wb_writeback_data, expected_value[retired]);
                    if (expected_rd[retired] != 0)
                        golden_regs[expected_rd[retired]] = expected_value[retired];
                end
                if (dut.ex_wb_instruction_q[6:0] == 7'h37 ||
                    dut.ex_wb_instruction_q[6:0] == 7'h17) upper_retired = upper_retired + 1;
                retired = retired + 1;
            end
            #1;
            for (j = 0; j < 32; j = j + 1)
                if (dut.u_regfile.regs[j] !== golden_regs[j])
                    $fatal(1, "register mismatch x%0d", j);
            if (retired == n) begin
                if (raw_bubbles != 0 || upper_forwarded == 0 || memory_holds == 0 ||
                    memory.ram.mem[16] !== 32'h12345000)
                    $fatal(1, "missing dependency/memory coverage or incorrect Store");
                $display("PASS pipeline_upper instructions=%0d upper=%0d cycles=%0d raw_bubbles=%0d memory_holds=%0d upper_forwarded=%0d",
                         retired, upper_retired, cycles, raw_bubbles, memory_holds, upper_forwarded);
                $finish;
            end
        end
    end
endmodule
