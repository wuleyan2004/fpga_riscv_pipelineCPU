`timescale 1ns/1ps
module tb_c_diagnostic #(
    parameter FAULT = 0,
    parameter COPY_START = 0,
    parameter BSS_START = 0
);
    localparam CLKS_PER_BIT = 27000000 / 115200;
    reg clk = 0, reset_button_n = 0;
    wire [7:0] gpio;
    wire tx;
    // 只缩短重复消息间的空等，UART 位时序与实际上板相同。
    board_top #(.DIAG_DELAY_COUNT(40)) dut (.clk(clk), .reset_button_n(reset_button_n),
        .gpio_button_n(4'b1111), .gpio_out(gpio), .uart_tx_pin(tx));
    always #18.5185 clk = ~clk;
    reg [7:0] byte_value, expected;
    integer frames = 0, boot = 0;
    reg [31:0] image_pc = 32'hffff_fffc;
    wire [31:0] image_instruction;
    reg [31:0] expected_rom [0:255];
    reg [31:0] expected_ram [0:255];
    instruction_rom #(.C_PROGRAM(1)) default_image (
        .pc(image_pc), .instruction(image_instruction));
    initial forever begin
        @(negedge tx);
        if (!dut.reset) begin
            repeat (CLKS_PER_BIT/2) @(posedge clk); #1;
            if (tx !== 0) $fatal(1,"FAIL start bit");
            for (integer b=0; b<8; b=b+1) begin
                repeat (CLKS_PER_BIT) @(posedge clk); #1;
                byte_value[b] = tx;
            end
            repeat (CLKS_PER_BIT) @(posedge clk); #1;
            if (tx !== 1) $fatal(1,"FAIL stop bit");
            case (frames)
                0: expected = "B";
                1: expected = "D";
                2: expected = "Z";
                3: expected = "M";
                default: expected = (frames % 2 == 0) ? (FAULT == 1 ? "I" : "K") : 8'h0a;
            endcase
            if (byte_value !== expected)
                $fatal(1,"FAIL diagnostic frame=%0d got=%h expected=%h",frames,byte_value,expected);
            frames = frames + 1;
        end
    end
    initial begin
        $readmemh("board_c_diagnostic/software/program.hex", expected_rom);
        $readmemh("board_c_diagnostic/software/ram.hex", expected_ram);
        #1;
        for (integer i=0; i<256; i=i+1) begin
            image_pc = i*4; #1;
            if (image_instruction !== expected_rom[i] || dut.u_soc_top.u_data_ram.mem[i] !== expected_ram[i])
                $fatal(1,"FAIL default ROM/RAM image word %0d",i);
        end
        if (FAULT == 1) begin
            // 模拟 FPGA RAM 初始化未被保留：初始副本和运行区全为零。
            for (integer i=0; i<256; i=i+1) dut.u_soc_top.u_data_ram.mem[i] = 0;
        end else begin
            for (integer i=0; i<BSS_START/4; i=i+1)
                dut.u_soc_top.u_data_ram.mem[i] = 32'ha5a5a5a5;
        end
        for (boot=0; boot<2; boot=boot+1) begin
            repeat (3) @(negedge clk); reset_button_n=1;
            wait (frames == 8); #1;
            if (gpio !== (FAULT == 1 ? 8'h81 : 8'h06))
                $fatal(1,"FAIL diagnostic GPIO %h",gpio);
            $display("PASS diagnostic boot=%0d fault=%0d frames=BDZM%0s GPIO=%h repeat=PASS",
                boot,FAULT,FAULT == 1 ? "I" : "K",gpio);
            // 等最后一帧结束再复位，避免截断输出。
            repeat (CLKS_PER_BIT/2-2) @(posedge clk);
            @(negedge clk); reset_button_n=0; frames=0;
        end
        $finish;
    end
    initial begin
        repeat (15000000) @(posedge clk);
        $fatal(1,"FAIL diagnostic timeout");
    end
endmodule
