`timescale 1ns/1ps
module tb_perf_counter_mmio;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, mem_valid = 0, mem_write = 0;
    reg [31:0] mem_addr = 0, mem_wdata = 0;
    reg retire = 0, mem_wait = 0, raw_wait = 0;
    reg branch = 0, branch_taken = 0, jump = 0;
    wire mem_ready;
    wire [31:0] mem_rdata;
    perf_counter_mmio dut (.*);

    task write_ctrl(input [31:0] value);
        begin
            @(negedge clk);
            mem_valid = 1; mem_write = 1;
            mem_addr = 32'h1000_0030; mem_wdata = value;
            @(posedge clk); #1;
            if (!mem_ready) $fatal(1, "control write did not respond");
            @(negedge clk); mem_valid = 0; mem_write = 0;
            @(posedge clk); #1;
        end
    endtask

    task check(input [31:0] address, input [31:0] expected);
        begin
            @(negedge clk);
            mem_valid = 1; mem_write = 0; mem_addr = address;
            @(posedge clk); #1;
            if (!mem_ready || mem_rdata !== expected)
                $fatal(1, "counter %h got %d expected %d", address, mem_rdata, expected);
            @(negedge clk); mem_valid = 0;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); reset = 0;
        write_ctrl(1);
        @(negedge clk);
        retire = 1; mem_wait = 1;
        @(negedge clk);
        retire = 0; mem_wait = 0;
        raw_wait = 1; branch = 1; branch_taken = 1;
        @(negedge clk);
        raw_wait = 0; branch = 0; branch_taken = 0;
        jump = 1;
        @(negedge clk); jump = 0;
        write_ctrl(0);
        check(32'h1000_0038, 1);
        check(32'h1000_003c, 1);
        check(32'h1000_0040, 1);
        check(32'h1000_0044, 1);
        check(32'h1000_0048, 1);
        check(32'h1000_004c, 1);
        check(32'h1000_0050, 1);
        if (dut.cycles_q < 4) $fatal(1, "cycle counter did not run");
        write_ctrl(1);
        write_ctrl(0);
        check(32'h1000_0038, 0);
        check(32'h1000_003c, 0);
        $display("PASS perf_counter_mmio");
        $finish;
    end
endmodule
