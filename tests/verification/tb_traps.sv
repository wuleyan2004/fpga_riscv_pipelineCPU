`timescale 1ns/1ps

// PC 0: older ADDI; PC 4: fault; PC 8: younger SW, which must be flushed.
module tb_traps;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire [31:0] pc, instruction, mem_addr, mem_wdata;
    wire mem_valid, mem_write, misaligned;
    wire [3:0] mem_wstrb;
    reg [31:0] fault_ins;
    integer case_id, expected_cause, cycles = 0, traps = 0;
    reg expected_misaligned;
    reg [31:0] expected_tval;

    assign instruction = pc == 32'h00007ffc ? 32'h0000006f :
                         pc == 0 ? 32'h00900293 : // addi x5, x0, 9
                         pc == 4 ? fault_ins :
                         pc == 8 ? 32'h00502023 : // sw x5, 0(x0)
                         32'h00000013;
    cpu_core_pipeline dut(
        .clk(clk), .reset(reset), .instruction(instruction), .pc(pc),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(1'b1), .mem_rdata(32'b0), .debug_misaligned(misaligned)
    );

    initial begin
        if (!$value$plusargs("CASE=%d", case_id)) $fatal(1, "missing CASE");
        expected_misaligned = 0;
        expected_tval = 0;
        case (case_id)
            0: begin fault_ins = 32'hffffffff; expected_cause = 2; expected_tval = fault_ins; end
            1: begin fault_ins = 32'h00000073; expected_cause = 11; end // ECALL
            2: begin fault_ins = 32'h00100073; expected_cause = 3; end  // EBREAK
            3: begin fault_ins = 32'h000000f3; expected_cause = 2; expected_tval = fault_ins; end // malformed SYSTEM
            4: begin fault_ins = 32'h002000ef; expected_cause = 0; expected_tval = 6; end // JAL +2
            5: begin fault_ins = 32'h003000e7; expected_cause = 0; expected_tval = 2; end // JALR +3 -> +2
            6: begin fault_ins = 32'h00000163; expected_cause = 0; expected_tval = 6; end // taken BEQ +2
            7: begin fault_ins = 32'h3ff01083; expected_cause = 4; expected_misaligned = 1; expected_tval = 1023; end // LH crosses RAM end
            8: begin fault_ins = 32'h3ff05083; expected_cause = 4; expected_misaligned = 1; expected_tval = 1023; end // LHU crosses RAM end
            9: begin fault_ins = 32'h3fe02083; expected_cause = 4; expected_misaligned = 1; expected_tval = 1022; end // LW crosses RAM end
            10: begin fault_ins = 32'h3e101fa3; expected_cause = 6; expected_misaligned = 1; expected_tval = 1023; end // SH crosses RAM end
            11: begin fault_ins = 32'h3e102f23; expected_cause = 6; expected_misaligned = 1; expected_tval = 1022; end // SW crosses RAM end
            default: $fatal(1, "unknown trap case");
        endcase
        repeat (3) @(negedge clk);
        reset = 0;
    end

    always @(posedge clk) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (cycles > 30) $fatal(1, "trap timeout case=%0d pc=%h", case_id, pc);
            if (mem_valid) $fatal(1, "fault or younger instruction issued memory request");
            #1;
            if (dut.trap_valid_q && traps == 0) begin
                traps = traps + 1;
                if (dut.trap_pc_q !== 32'd4 || dut.trap_instruction_q !== fault_ins ||
                    dut.trap_cause_q !== expected_cause || pc !== 32'h00007ffc ||
                    dut.if_ex_valid_q !== 0 || dut.ex_wb_valid_q !== 0 ||
                    dut.ex_wb_reg_write_q !== 0 || dut.ex_wb_mem_access_q !== 0 ||
                    misaligned !== expected_misaligned ||
                    dut.u_csr_file.mepc_q !== 32'd4 ||
                    dut.u_csr_file.mcause_q !== expected_cause ||
                    dut.u_csr_file.mtval_q !== expected_tval)
                    $fatal(1, "wrong trap case=%0d cause=%0d pc=%h ins=%h debug=%b",
                        case_id, dut.trap_cause_q, pc, dut.trap_instruction_q, misaligned);
                if (dut.u_regfile.regs[5] !== 9)
                    $fatal(1, "older ADDI failed to retire before trap");
            end
            if (traps == 1 && cycles >= 9) begin
                if (dut.u_regfile.regs[5] !== 9 || dut.trap_cause_q !== expected_cause ||
                    dut.trap_pc_q !== 4)
                    $fatal(1, "trap record or older register changed");
                $display("PASS trap case=%0d instruction=%h cause=%0d", case_id, fault_ins, expected_cause);
                $finish;
            end
        end
    end
endmodule
