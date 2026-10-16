`timescale 1ns/1ps
module tb_board_inputs;
    reg clk = 0, reset_button_n = 1;
    reg [3:0] buttons = 4'b1111;
    wire [7:0] gpio_out;
    wire tx;
    integer i;
    always #18.5185 clk = ~clk;
    board_top #(.COREMARK_PROGRAM(0), .BOARD_DEMO_DELAY_COUNT(40)) dut (
        .clk(clk), .reset_button_n(reset_button_n), .gpio_button_n(buttons),
        .gpio_out(gpio_out), .uart_tx_pin(tx)
    );
    initial begin
        // No button press at startup: initialized reset synchronizer holds SoC.
        #1;
        if (dut.reset !== 1) $fatal(1, "FAIL power-on reset");
        @(posedge clk); #1;
        if (dut.reset !== 1 || dut.u_soc_top.pc !== 0 || gpio_out !== 0 || tx !== 1)
            $fatal(1, "FAIL first startup edge");
        @(posedge clk); #1;
        if (dut.reset !== 0 || dut.u_soc_top.pc !== 0)
            $fatal(1, "FAIL second startup edge");
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk); #3;
            buttons = ~(4'b0001 << i);
            @(posedge clk); #1;
            if (dut.gpio_in !== 0) $fatal(1, "FAIL GPIO changed after only one edge");
            @(posedge clk); #1;
            if (dut.gpio_in !== (8'b1 << i)) $fatal(1, "FAIL GPIO bit mapping");
            @(negedge clk); #3;
            buttons = 4'b1111;
            repeat (2) @(posedge clk);
            #1;
            if (dut.gpio_in !== 0) $fatal(1, "FAIL GPIO release synchronization");
        end
        wait (dut.u_soc_top.u_uart.tx_busy);
        // A short reset pulse wholly between clock edges must still reset SoC.
        @(negedge clk); #3;
        reset_button_n = 0;
        #2;
        if (dut.reset !== 1) $fatal(1, "FAIL short reset pulse lost");
        reset_button_n = 1;
        @(posedge clk); #1;
        if (dut.reset !== 1 || dut.u_soc_top.pc !== 0 || gpio_out !== 0 || tx !== 1 ||
            dut.u_soc_top.u_uart.tx_busy !== 0 || dut.u_soc_top.mem_valid !== 0 ||
            dut.u_soc_top.u_cpu_core.if_ex_valid_q !== 0 ||
            dut.u_soc_top.u_cpu_core.ex_wb_valid_q !== 0)
            $fatal(1, "FAIL reset during UART transaction");
        @(posedge clk); #1;
        if (dut.reset !== 0 || dut.u_soc_top.pc !== 0)
            $fatal(1, "FAIL reset release after short pulse");
        $display("PASS board_inputs power_on=PASS gpio_bits=4 short_reset=PASS uart_busy_reset=PASS");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "FAIL board inputs timeout");
    end
endmodule
