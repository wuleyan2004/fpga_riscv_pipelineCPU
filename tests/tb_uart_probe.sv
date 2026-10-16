`timescale 1ns/1ps

module tb_uart_probe;
    localparam integer CLKS_PER_BIT = 27_000_000 / 115_200;

    reg clk = 1'b0;
    reg reset_button_n = 1'b1;
    reg [3:0] gpio_button_n = 4'b1111;
    wire [7:0] gpio_out;
    wire uart_tx_pin;
    integer frames = 0;

    always #18.5185 clk = ~clk;

    uart_probe_top #(.GAP_CYCLES(5000)) dut (
        .clk            (clk),
        .reset_button_n (reset_button_n),
        .gpio_button_n  (gpio_button_n),
        .gpio_out       (gpio_out),
        .uart_tx_pin    (uart_tx_pin)
    );

    initial begin
        forever begin
            @(negedge uart_tx_pin);
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            #1;
            if (uart_tx_pin !== 1'b0)
                $fatal(1, "FAIL UART start bit");
            for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                #1;
                if (uart_tx_pin !== ((8'h55 >> bit_index) & 1))
                    $fatal(1, "FAIL UART data bit %0d", bit_index);
            end
            repeat (CLKS_PER_BIT) @(posedge clk);
            #1;
            if (uart_tx_pin !== 1'b1)
                $fatal(1, "FAIL UART stop bit");
            frames = frames + 1;
            if (frames == 2) begin
                if (gpio_out !== 8'h01)
                    $fatal(1, "FAIL GPIO output");
                $display("PASS uart_probe_top: two 0x55 frames");
                $finish;
            end
        end
    end

    initial begin
        #1_000_000;
        $fatal(1, "FAIL UART probe timeout");
    end
endmodule
