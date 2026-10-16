`timescale 1ns/1ps
module tb_timer_mmio;
    reg clk = 0, reset = 1, valid = 0, write = 0;
    reg [31:0] addr = 32'h10000020;
    wire ready;
    wire [31:0] data;
    reg [63:0] sampled_cycle;
    timer_mmio dut (.clk(clk), .reset(reset), .mem_valid(valid),
        .mem_write(write), .mem_addr(addr), .mem_ready(ready), .mem_rdata(data));
    always #5 clk = ~clk;
    task transaction(input bit high_word, input bit is_write);
        begin
            @(negedge clk);
            addr = high_word ? 32'h10000024 : 32'h10000020;
            write = is_write; valid = 1;
            sampled_cycle = dut.cycle_q;
            @(posedge clk); #1;
            if (!ready || data !== (is_write ? 32'b0 :
                (high_word ? sampled_cycle[63:32] : sampled_cycle[31:0])))
                $fatal(1, "FAIL timer snapshot/response");
            @(negedge clk); valid = 0;
            @(posedge clk); #1;
            if (ready || dut.cycle_q !== sampled_cycle + 2)
                $fatal(1, "FAIL timer response pulse/free-running count");
        end
    endtask
    initial begin
        repeat (2) @(negedge clk);
        if (ready !== 0 || data !== 0 || dut.cycle_q !== 0) $fatal(1, "FAIL timer reset");
        reset = 0;
        transaction(0, 0);
        transaction(1, 0);
        transaction(0, 1); // 写入忽略，计数仍继续。
        @(negedge clk); dut.cycle_q = 64'h00000007fffffffe;
        repeat (3) @(posedge clk); #1;
        if (dut.cycle_q !== 64'h0000000800000001) $fatal(1, "FAIL low-word carry");
        transaction(1, 0);
        transaction(0, 0);
        @(negedge clk); valid = 1;
        @(posedge clk); #1;
        if (!ready) $fatal(1, "FAIL reset test request");
        @(negedge clk); reset = 1;
        @(posedge clk); #1;
        if (ready !== 0 || data !== 0 || dut.cycle_q !== 0) $fatal(1, "FAIL reset pending request");
        $display("PASS timer_mmio count snapshots response write_ignored low32_carry reset");
        $finish;
    end
    initial begin #1000; $fatal(1, "FAIL timer timeout"); end
endmodule
