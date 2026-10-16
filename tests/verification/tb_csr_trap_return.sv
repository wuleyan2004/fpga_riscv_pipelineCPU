`timescale 1ns/1ps

// Exercises CSR forwarding, all six CSR operations, ECALL return, and
// unsupported-CSR illegal-instruction return through a real handler.
module tb_csr_trap_return;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;

    wire [31:0] pc;
    reg [31:0] instruction;
    wire mem_valid, mem_write;
    wire [3:0] mem_wstrb;
    wire [31:0] mem_addr, mem_wdata;
    integer cycles = 0, traps = 0;

    function automatic [31:0] csr_ins(
        input [11:0] addr, input [4:0] rs1_or_uimm,
        input [2:0] cmd, input [4:0] rd
    );
        csr_ins = {addr, rs1_or_uimm, cmd, rd, 7'h73};
    endfunction

    localparam [31:0] INVALID_CSR = {12'h777, 5'd0, 3'b010, 5'd24, 7'h73};

    always @(*) begin
        case (pc)
            32'd0:   instruction = 32'h08000293; // addi x5,x0,128
            32'd4:   instruction = csr_ins(12'h305, 5'd5, 3'b001, 5'd0); // csrw mtvec,x5
            32'd8:   instruction = csr_ins(12'h300, 5'd8, 3'b110, 5'd6); // set mstatus.MIE
            32'd12:  instruction = 32'h00000073; // ecall
            32'd16:  instruction = csr_ins(12'h300, 5'd0, 3'b010, 5'd7); // read restored mstatus
            32'd20:  instruction = csr_ins(12'h342, 5'd5, 3'b101, 5'd17); // csrrwi
            32'd24:  instruction = csr_ins(12'h342, 5'd2, 3'b110, 5'd18); // csrrsi
            32'd28:  instruction = csr_ins(12'h342, 5'd1, 3'b111, 5'd19); // csrrci
            32'd32:  instruction = csr_ins(12'h342, 5'd0, 3'b010, 5'd20); // csrr
            32'd36:  instruction = 32'h00200a93; // addi x21,x0,2
            32'd40:  instruction = csr_ins(12'h342, 5'd21, 3'b011, 5'd22); // csrrc
            32'd44:  instruction = csr_ins(12'h342, 5'd0, 3'b010, 5'd23); // csrr
            32'd48:  instruction = INVALID_CSR;
            32'd52:  instruction = 32'h00100c93; // addi x25,x0,1
            32'd56:  instruction = 32'h0000006f; // done: jal x0,0

            32'd128: instruction = csr_ins(12'h342, 5'd0, 3'b010, 5'd10); // csrr mcause
            32'd132: instruction = csr_ins(12'h341, 5'd0, 3'b010, 5'd11); // csrr mepc
            32'd136: instruction = csr_ins(12'h343, 5'd0, 3'b010, 5'd12); // csrr mtval
            32'd140: instruction = 32'h00458593; // addi x11,x11,4
            32'd144: instruction = csr_ins(12'h341, 5'd11, 3'b001, 5'd0); // csrw mepc,x11
            32'd148: instruction = csr_ins(12'h300, 5'd0, 3'b010, 5'd27); // mstatus in handler
            32'd152: instruction = 32'h30200073; // mret
            default: instruction = 32'h00000013;
        endcase
    end

    cpu_core_pipeline dut (
        .clk(clk), .reset(reset), .instruction(instruction), .pc(pc),
        .mem_valid(mem_valid), .mem_write(mem_write),
        .mem_wstrb(mem_wstrb), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(1'b1), .mem_rdata(32'b0), .debug_misaligned()
    );

    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
    end

    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (cycles > 100) $fatal(1, "CSR return timeout pc=%h traps=%0d", pc, traps);
        if (mem_valid) $fatal(1, "unexpected memory request");
        if (dut.csr_trap_valid) begin
            traps = traps + 1;
            if (traps == 1 &&
                (dut.csr_trap_cause !== 32'd11 || dut.if_ex_pc_q !== 32'd12 ||
                 dut.csr_trap_value !== 32'd0))
                $fatal(1, "bad ECALL trap");
            if (traps == 2 &&
                (dut.csr_trap_cause !== 32'd2 || dut.if_ex_pc_q !== 32'd48 ||
                 dut.csr_trap_value !== INVALID_CSR))
                $fatal(1, "bad unsupported CSR trap");
            if (traps > 2) $fatal(1, "unexpected repeated trap");
        end
        #1;
        if (traps == 2 && pc == 32'd56 && dut.u_regfile.regs[25] == 1) begin
            if (dut.u_regfile.regs[6] !== 32'h00001800 ||
                dut.u_regfile.regs[7] !== 32'h00001888 ||
                dut.u_regfile.regs[10] !== 2 || dut.u_regfile.regs[11] !== 52 ||
                dut.u_regfile.regs[12] !== INVALID_CSR ||
                dut.u_regfile.regs[27] !== 32'h00001880 ||
                dut.u_regfile.regs[17] !== 11 || dut.u_regfile.regs[18] !== 5 ||
                dut.u_regfile.regs[19] !== 7 || dut.u_regfile.regs[20] !== 6 ||
                dut.u_regfile.regs[22] !== 6 || dut.u_regfile.regs[23] !== 4 ||
                dut.u_regfile.regs[24] !== 0 ||
                dut.u_csr_file.mtvec_q !== 128 ||
                dut.u_csr_file.mepc_q !== 52 ||
                dut.u_csr_file.mcause_q !== 2 ||
                dut.u_csr_file.mtval_q !== INVALID_CSR)
                $fatal(1, "CSR/return result mismatch");
            $display("PASS CSR trap return and six CSR operations");
            $finish;
        end
    end
endmodule
