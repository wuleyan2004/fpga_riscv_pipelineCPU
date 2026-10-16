`timescale 1ns/1ps
module tb_coremark_uart_pacing;
    localparam CLKS_PER_BIT = 27000000 / 115200;
    localparam GAP_CYCLES = 540000;
    reg clk = 0, reset_button_n = 0;
    wire tx;
    wire [7:0] gpio;
    always #18.5185 clk = ~clk;
    // 执行同一 uart_send_char 的最小 C 程序，保留实际 20 ms 等待。
    board_top #(.COREMARK_FILE(1)) dut (
        .clk(clk), .reset_button_n(reset_button_n), .gpio_button_n(4'b1111),
        .gpio_out(gpio), .uart_tx_pin(tx));
    // 同时核对导出 CoreMark 包的实际内置镜像，CPU 保持复位。
    board_top #(.COREMARK_FILE(0)) image_dut (
        .clk(clk), .reset_button_n(1'b0), .gpio_button_n(4'b1111),
        .gpio_out(), .uart_tx_pin());
    reg [31:0] expected_rom[0:8191], expected_ram[0:16383];
    reg [7:0] value;
    integer cycles = 0, frames = 0, previous_start = 0, this_start, index;
    always @(posedge clk) begin
        cycles = cycles + 1;
        if (!dut.reset && dut.u_soc_top.debug_misaligned)
            $fatal(1, "FAIL misaligned access");
    end
    initial begin
        $readmemh("actual_coremark_program.hex", expected_rom);
        $readmemh("actual_coremark_data.hex", expected_ram);
        #1;
        for (index = 0; index < 8192; index = index + 1)
            if (image_dut.u_soc_top.u_instruction_rom.g_coremark_program.imem[index] !== expected_rom[index])
                $fatal(1, "FAIL package ROM word %0d", index);
        for (index = 0; index < 16384; index = index + 1)
            if (image_dut.u_soc_top.u_data_ram.mem[index] !== expected_ram[index])
                $fatal(1, "FAIL package RAM word %0d", index);
        repeat (3) @(negedge clk);
        reset_button_n = 1;
        wait (gpio == 2);
        #1;
        if (frames != 3) $fatal(1, "FAIL frame count %0d", frames);
        $display("PASS UART pacing: A B LF, 115200 8N1, actual 20 ms gaps, counter rollover");
        $display("PASS diagnostic package: ROM_words=8192 RAM_words=16384");
        $finish;
    end
    initial forever begin
        @(negedge tx);
        this_start = cycles;
        if (frames && this_start - previous_start < GAP_CYCLES + 10 * CLKS_PER_BIT)
            $fatal(1, "FAIL frame spacing: %0d cycles", this_start - previous_start);
        previous_start = this_start;
        repeat (CLKS_PER_BIT/2) @(posedge clk); #1;
        if (tx !== 0) $fatal(1, "FAIL start bit");
        for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            repeat (CLKS_PER_BIT) @(posedge clk); #1;
            value[bit_index] = tx;
        end
        repeat (CLKS_PER_BIT) @(posedge clk); #1;
        if (tx !== 1) $fatal(1, "FAIL stop bit");
        if (value !== (frames == 0 ? 8'h41 : frames == 1 ? 8'h42 : 8'h0a))
            $fatal(1, "FAIL character %0d: %h", frames, value);
        frames = frames + 1;
        if (frames == 1) begin
            // 最后一个停止位仍未结束：在等待开始前将低位计数器设到回绕附近。
            @(negedge clk);
            dut.u_soc_top.u_timer.cycle_q = 64'h00000000_ffff0000;
        end
    end
    initial begin
        repeat (2000000) @(posedge clk);
        $fatal(1, "FAIL paced UART timeout");
    end
endmodule
