`timescale 1ns/1ps

module tb_m_emulation;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire [31:0] pc;
    reg [31:0] results_addr, last_fault_pc, last_instruction;
    reg [31:0] expected [0:11];
    integer cycles = 0, i;

    soc_top dut (
        .clk(clk), .reset(reset), .gpio_in(8'b0), .gpio_out(), .uart_tx_pin(),
        .debug_pc(pc), .debug_instruction(), .debug_mem_valid(),
        .debug_mem_ready(), .debug_misaligned()
    );

    initial begin
        expected[0] = 32'hffffffeb;
        expected[1] = 32'hffffffff;
        expected[2] = 32'hfffffff9;
        expected[3] = 32'hfffffffe;
        expected[4] = 32'hfffffffe;
        expected[5] = 32'h55555555;
        expected[6] = 32'hffffffff;
        expected[7] = 32'h00000000;
        expected[8] = 32'hffffffff;
        expected[9] = 32'hfffffff9;
        expected[10] = 32'h80000000;
        expected[11] = 32'h00000000;
        if (!$value$plusargs("RESULTS=%h", results_addr) ||
            !$value$plusargs("LAST_PC=%h", last_fault_pc) ||
            !$value$plusargs("LAST_INS=%h", last_instruction))
            $fatal(1, "missing M emulation arguments");
        $readmemh("ram-preload.hex", dut.u_data_ram.mem);
        repeat (3) @(negedge clk);
        reset = 0;
    end

    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (cycles > 30000) $fatal(1, "M emulation timeout pc=%h", pc);
        #1;
        if (dut.u_data_ram.mem[(results_addr >> 2) + 12] === 32'd1) begin
            for (i = 0; i < 12; i = i + 1)
                if (dut.u_data_ram.mem[(results_addr >> 2) + i] !== expected[i])
                    $fatal(1, "M result %0d got=%h expected=%h",
                        i, dut.u_data_ram.mem[(results_addr >> 2) + i], expected[i]);
            if (dut.u_cpu_core.u_csr_file.mcause_q !== 32'd2 ||
                dut.u_cpu_core.u_csr_file.mtval_q !== last_instruction ||
                dut.u_cpu_core.u_csr_file.mepc_q !== last_fault_pc + 4 ||
                dut.u_cpu_core.u_regfile.regs[2] !== 32'd1024 ||
                dut.u_cpu_core.u_regfile.regs[0] !== 32'd0)
                $fatal(1, "M trap state or GPR restore incorrect");
            $display("PASS RV32M software emulation 12 arithmetic and edge cases");
            $finish;
        end
    end
endmodule
