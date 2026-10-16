`timescale 1ns/1ps

module tb_board_demo;
    localparam integer CLKS_PER_BIT = 27_000_000 / 115_200;

    reg clk = 1'b0;
    reg reset_button_n = 1'b0;
    reg [3:0] gpio_button_n = 4'b1111;
    wire [7:0] gpio_out;
    wire uart_tx_pin;

    integer frame_count = 0;
    integer start_count = 0;
    integer forward_count = 0;
    reg [7:0] expected_byte;

    // 27 MHz board oscillator (rounded to 1 ps simulation precision).
    always #18.5185 clk = ~clk;

    // Shorten only the diagnostic delay so two complete messages fit in a
    // fast simulation; the FPGA build uses the 6,750,000-iteration default.
    board_top #(.COREMARK_PROGRAM(0), .C_PROGRAM(0), .BOARD_DEMO_DELAY_COUNT(40)) dut (
        .clk         (clk),
        .reset_button_n (reset_button_n),
        .gpio_button_n  (gpio_button_n),
        .gpio_out    (gpio_out),
        .uart_tx_pin (uart_tx_pin)
    );

    // Sample the UART output at the center of every 8N1 bit.
    initial begin
        forever begin
            @(negedge uart_tx_pin);
            if (!dut.reset) begin
                case (frame_count % 3)
                    0: expected_byte = 8'h4f; // O
                    1: expected_byte = 8'h4b; // K
                    2: expected_byte = 8'h0a; // newline
                endcase

                repeat (CLKS_PER_BIT / 2) @(posedge clk);
                #1;
                if (uart_tx_pin !== 1'b0)
                    $fatal(1, "FAIL frame %0d start bit", frame_count);

                for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                    repeat (CLKS_PER_BIT) @(posedge clk);
                    #1;
                    if (uart_tx_pin !== expected_byte[bit_index])
                        $fatal(1, "FAIL frame %0d data bit %0d", frame_count, bit_index);
                end

                repeat (CLKS_PER_BIT) @(posedge clk);
                #1;
                if (uart_tx_pin !== 1'b1)
                    $fatal(1, "FAIL frame %0d stop bit", frame_count);
                frame_count = frame_count + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (!dut.reset) begin
            if (dut.u_soc_top.u_uart.tx_start) start_count = start_count + 1;
            if (!dut.u_soc_top.u_cpu_core.stall_mem &&
                (dut.u_soc_top.u_cpu_core.forward_rs1 || dut.u_soc_top.u_cpu_core.forward_rs2))
                forward_count = forward_count + 1;
            if (!dut.u_soc_top.u_cpu_core.stall_mem && dut.u_soc_top.u_cpu_core.stall_raw)
                $fatal(1, "FAIL unexpected RAW bubble in board demo");
        end
    end

    initial begin
        repeat (3) @(negedge clk);
        if (gpio_out !== 8'b0 || uart_tx_pin !== 1'b1)
            $fatal(1, "FAIL reset outputs");
        reset_button_n = 1'b1;

        wait (frame_count == 6);
        #1;
        if (gpio_out !== 8'h01 || start_count != 6 || uart_tx_pin !== 1'b1)
            $fatal(1, "FAIL board demo final state: gpio=%h starts=%0d pc=%h",
                   gpio_out, start_count, dut.u_soc_top.pc);

        @(negedge clk); #3;
        gpio_button_n = 4'b1110;
        #1;
        if (dut.gpio_in !== 0) $fatal(1, "FAIL asynchronous GPIO reached SoC directly");
        @(posedge clk); #1;
        if (dut.gpio_in !== 0) $fatal(1, "FAIL GPIO bypassed second synchronizer stage");
        @(posedge clk); #1;
        if (dut.gpio_in !== 8'h01)
            $fatal(1, "FAIL active-low GPIO button mapping");
        gpio_button_n = 4'b1111;

        @(negedge clk); #3;
        reset_button_n = 1'b0;
        #1;
        if (dut.reset !== 1) $fatal(1, "FAIL reset assertion was not asynchronous");
        @(posedge clk);
        #1;
        if (gpio_out !== 8'h00 || uart_tx_pin !== 1'b1 ||
            dut.u_soc_top.pc !== 32'b0)
            $fatal(1, "FAIL active-low reset button mapping");

        @(negedge clk); #3;
        reset_button_n = 1'b1;
        @(posedge clk); #1;
        if (dut.reset !== 1 || dut.u_soc_top.pc !== 0)
            $fatal(1, "FAIL reset released on first synchronizer edge");
        @(posedge clk); #1;
        if (dut.reset !== 0 || dut.u_soc_top.pc !== 0)
            $fatal(1, "FAIL reset did not release on second edge");
        // Restart the complete program using the retained register-file contents.
        wait (frame_count == 9); #1;
        if (start_count != 9 || gpio_out !== 8'h01 || forward_count == 0)
            $fatal(1, "FAIL restart or forwarding coverage");
        $display("PASS board_demo.S GPIO=%h UART=4f 4b 0a frames=%0d starts=%0d forwarded_ex=%0d reset_restart=PASS",
                 8'h01, frame_count, start_count, forward_count);
        $finish;
    end

    initial begin
        #1_000_000;
        $fatal(1, "FAIL board demo timeout");
    end
endmodule
