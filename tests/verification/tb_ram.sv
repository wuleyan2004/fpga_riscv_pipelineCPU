`timescale 1ns/1ps

module tb_ram;
    reg clk=0, reset=1, valid=0, write=0;
    always #5 clk=~clk;
    reg [3:0] mask=0;
    reg [31:0] addr=0, wdata=0;
    wire ready;
    wire [31:0] rdata;
    integer j, k;
    reg [31:0] model;
    sync_data_ram dut(.clk(clk), .reset(reset), .mem_valid(valid),
        .mem_write(write), .mem_wstrb(mask), .mem_addr(addr),
        .mem_wdata(wdata), .mem_ready(ready), .mem_rdata(rdata));
    task transaction(input bit wr, input [31:0] ad, input [31:0] dat, input [3:0] st);
        begin
            @(negedge clk); valid=1; write=wr; addr=ad; wdata=dat; mask=st;
            if (ready !== 0) $fatal(1, "RAM not idle");
            @(posedge clk); #1;
            if (ready !== 1) $fatal(1, "RAM response absent");
            @(posedge clk); #1;
            if (ready !== 0) $fatal(1, "RAM response did not clear");
            @(negedge clk); valid=0;
        end
    endtask
    initial begin
        repeat (2) @(negedge clk);
        reset=0;
        for (j=0; j<16; j=j+1) begin
            transaction(1,16,32'h12345678,15);
            transaction(1,16,32'haabbccdd,j);
            model=32'h12345678;
            for (k=0; k<4; k=k+1)
                if ((j>>k)&1) model[k*8+:8]=32'haabbccdd>>(k*8);
            transaction(0,16,0,0);
            if (rdata !== model)
                $fatal(1, "RAM mask=%h got=%h expected=%h", j, rdata, model);
        end
        transaction(1,0,32'h13579bdf,15);
        transaction(1,1020,32'h2468ace0,15);
        transaction(0,0,0,0);
        if (rdata !== 32'h13579bdf) $fatal(1, "RAM low boundary");
        transaction(0,1020,0,0);
        if (rdata !== 32'h2468ace0) $fatal(1, "RAM high boundary");
        @(negedge clk); reset=1; valid=1; write=1; addr=0; wdata=0; mask=15;
        @(posedge clk); #1;
        if (ready !== 0 || rdata !== 0 || dut.mem[0] !== 32'h13579bdf)
            $fatal(1, "RAM reset priority or content persistence");
        $display("PASS RAM 16 masks, boundaries, response timing, reset priority");
        $finish;
    end
endmodule
