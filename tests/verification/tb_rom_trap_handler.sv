`timescale 1ns/1ps

// Run a linked ROM program through the real SoC, including its RAM trap record.
module tb_rom_trap_handler;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;

    wire [31:0] pc;
    reg [31:0] fault_pc, expected_tval, trap_entry, trap_halt;
    reg [31:0] record_addr, progress_addr;
    integer case_id, expected_cause, cycles = 0;

    soc_top dut (
        .clk(clk), .reset(reset), .gpio_in(8'b0), .gpio_out(), .uart_tx_pin(),
        .debug_pc(pc), .debug_instruction(), .debug_mem_valid(),
        .debug_mem_ready(), .debug_misaligned()
    );

    initial begin
        if (!$value$plusargs("CASE=%d", case_id) ||
            !$value$plusargs("CAUSE=%d", expected_cause) ||
            !$value$plusargs("FAULT_PC=%h", fault_pc) ||
            !$value$plusargs("TVAL=%h", expected_tval) ||
            !$value$plusargs("ENTRY=%h", trap_entry) ||
            !$value$plusargs("HALT=%h", trap_halt) ||
            !$value$plusargs("RECORD=%h", record_addr) ||
            !$value$plusargs("PROGRESS=%h", progress_addr))
            $fatal(1, "missing trap test arguments");
        $readmemh("ram-preload.hex", dut.u_data_ram.mem);
        repeat (3) @(negedge clk);
        reset = 0;
    end

    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (cycles > 500) $fatal(1, "ROM trap timeout case=%0d pc=%h", case_id, pc);
        #1;
        if (dut.u_data_ram.mem[record_addr >> 2] === expected_cause &&
            dut.u_data_ram.mem[(record_addr >> 2) + 1] === fault_pc &&
            dut.u_data_ram.mem[(record_addr >> 2) + 2] === expected_tval) begin
            if (case_id < 2) begin
                if (dut.u_data_ram.mem[progress_addr >> 2] === 32'd1 &&
                    dut.u_cpu_core.u_csr_file.mepc_q === fault_pc + 4) begin
                    $display("PASS ROM trap case=%0d cause=%0d returned", case_id, expected_cause);
                    $finish;
                end
            end else if ((pc == trap_halt || pc == trap_halt + 4) &&
                         dut.u_data_ram.mem[progress_addr >> 2] === 32'd0 &&
                         dut.u_cpu_core.u_csr_file.mepc_q === fault_pc &&
                         dut.u_cpu_core.u_csr_file.mtvec_q === trap_entry) begin
                $display("PASS ROM trap case=%0d cause=%0d halted", case_id, expected_cause);
                $finish;
            end
        end
    end
endmodule
