`timescale 1ns/1ps

// Uses soc_top's actual file ROM. program.hex has ECALL at index 0 and
// jal x0,0 at index 511, the alias of TRAP_VECTOR=0x7ffc.
module tb_soc_trap_vector;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    wire [31:0] pc, instruction;
    wire mem_valid, mem_ready, misaligned;
    integer cycles=0, handler_cycles=0;
    soc_top dut(
        .clk(clk), .reset(reset), .gpio_in(8'b0), .gpio_out(), .uart_tx_pin(),
        .debug_pc(pc), .debug_instruction(instruction),
        .debug_mem_valid(mem_valid), .debug_mem_ready(mem_ready),
        .debug_misaligned(misaligned)
    );
    initial begin
        repeat (3) @(negedge clk);
        reset=0;
    end
    always @(posedge clk) if (!reset) begin
        cycles=cycles+1;
        if (cycles>40) $fatal(1, "SoC trap vector timeout");
        if (mem_valid || misaligned) $fatal(1, "unexpected SoC memory/debug side effect");
        #1;
        if (dut.u_cpu_core.trap_valid_q) begin
            handler_cycles=handler_cycles+1;
            if (dut.u_cpu_core.trap_pc_q !== 0 ||
                dut.u_cpu_core.trap_instruction_q !== 32'h00000073 ||
                dut.u_cpu_core.trap_cause_q !== 11 ||
                (pc !== 32'h00007ffc && pc !== 32'h00008000))
                $fatal(1, "SoC trap handler failed pc=%h cause=%0d", pc, dut.u_cpu_core.trap_cause_q);
        end
        if (handler_cycles>=15) begin
            $display("PASS SoC ECALL to file-ROM trap vector handler_cycles=%0d", handler_cycles);
            $finish;
        end
    end
endmodule
