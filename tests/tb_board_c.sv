`timescale 1ns/1ps
module tb_board_c #(
    parameter INITIALIZED_ADDR = 0,
    parameter RESULT_ADDR = 0,
    parameter VISITS_ADDR = 0,
    parameter BSS_END = 0,
    parameter COPY_START = 0,
    parameter COPY_END = 0,
    parameter HALT_PC = 0
);
    localparam integer CLKS_PER_BIT = 27_000_000 / 115_200;
    reg clk = 0, reset_button_n = 0;
    wire [7:0] gpio_out;
    wire tx;
    reg [31:0] image_pc = 32'hffff_fffc;
    wire [31:0] image_instruction;
    reg [31:0] expected_rom [0:511];
    reg [31:0] expected_ram [0:255];
    string rom_path, ram_path;
    integer frame_count = 0, starts = 0, forwards = 0;
    integer minimum_sp = 1024;
    integer boot, i;
    reg halted = 0;
    reg [7:0] expected_byte;
    always #18.5185 clk = ~clk;

    // 使用 board_top 的默认参数，和导出的实际上板版本一致。
    board_top #(.COREMARK_PROGRAM(0)) dut (.clk(clk), .reset_button_n(reset_button_n),
        .gpio_button_n(4'b1111), .gpio_out(gpio_out), .uart_tx_pin(tx));
    instruction_rom #(.C_PROGRAM(1)) image_rom (
        .pc(image_pc), .instruction(image_instruction));

    // 从物理 UART 引脚逐位接收，而不是只观察内部发送请求。
    initial forever begin
        @(negedge tx);
        if (!dut.reset) begin
            case (frame_count % 8)
                0: expected_byte = "C";
                1: expected_byte = " ";
                2: expected_byte = "O";
                3: expected_byte = "K";
                4: expected_byte = ":";
                5: expected_byte = " ";
                6: expected_byte = "6";
                7: expected_byte = 8'h0a;
            endcase
            repeat (CLKS_PER_BIT / 2) @(posedge clk); #1;
            if (tx !== 0) $fatal(1, "FAIL C UART start bit");
            for (integer bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk); #1;
                if (tx !== expected_byte[bit_index])
                    $fatal(1, "FAIL C UART frame=%0d bit=%0d", frame_count, bit_index);
            end
            repeat (CLKS_PER_BIT) @(posedge clk); #1;
            if (tx !== 1) $fatal(1, "FAIL C UART stop bit");
            frame_count = frame_count + 1;
        end
    end

    always @(posedge clk) begin
        if (dut.reset) halted = 0;
        else begin
            if (dut.u_soc_top.debug_misaligned) $fatal(1, "FAIL misaligned C access");
            if (dut.u_soc_top.u_uart.tx_start) starts = starts + 1;
            if (!dut.u_soc_top.u_cpu_core.stall_mem &&
                (dut.u_soc_top.u_cpu_core.forward_rs1 || dut.u_soc_top.u_cpu_core.forward_rs2))
                forwards = forwards + 1;
            if (dut.u_soc_top.u_cpu_core.u_regfile.regs[2] >= 768 &&
                dut.u_soc_top.u_cpu_core.u_regfile.regs[2] < minimum_sp)
                minimum_sp = dut.u_soc_top.u_cpu_core.u_regfile.regs[2];
            // 必须等 halt 指令实际到达 WB；IF 的预测顺序取指不代表 main 已返回。
            if (dut.u_soc_top.u_cpu_core.ex_wb_valid_q &&
                dut.u_soc_top.u_cpu_core.ex_wb_pc_q == HALT_PC)
                halted = 1;
        end
    end

    initial begin
        if (!$value$plusargs("ROM=%s", rom_path) || !$value$plusargs("RAM=%s", ram_path))
            $fatal(1, "FAIL missing expected image paths");
        $readmemh(rom_path, expected_rom);
        $readmemh(ram_path, expected_ram);
        #1;
        for (i = 0; i < 256; i = i + 1) begin
            if (dut.u_soc_top.u_data_ram.mem[i] !== expected_ram[i])
                $fatal(1, "FAIL RAM initial image word %0d", i);
        end
        for (i = 0; i < 512; i = i + 1) begin
            image_pc = i * 4; #1;
            if (image_instruction !== expected_rom[i])
                $fatal(1, "FAIL ROM image word %0d", i);
        end
        // 不预装运行区初值：制造垃圾数据，确认 start.S 真正执行复制和清零。
        for (i = 0; i < BSS_END / 4; i = i + 1)
            dut.u_soc_top.u_data_ram.mem[i] = 32'ha5a5a5a5;
        for (boot = 1; boot <= 2; boot = boot + 1) begin
            repeat (3) @(negedge clk);
            reset_button_n = 1;
            wait (frame_count == boot * 8 && halted);
            // 等最后一帧完全结束，检查之后没有重复字符/额外 Store。
            repeat (2 * CLKS_PER_BIT) @(posedge clk); #1;
            if (starts != boot * 8 || frame_count != boot * 8 || gpio_out !== 8'h06 ||
                dut.u_soc_top.u_cpu_core.u_regfile.regs[10] !== 0 ||
                dut.u_soc_top.u_cpu_core.u_regfile.regs[2] !== 1024 || minimum_sp >= 1024)
                $fatal(1, "FAIL C final state boot=%0d starts=%0d gpio=%h sp=%h a0=%h", boot,
                    starts, gpio_out, dut.u_soc_top.u_cpu_core.u_regfile.regs[2],
                    dut.u_soc_top.u_cpu_core.u_regfile.regs[10]);
            if (dut.u_soc_top.u_data_ram.mem[INITIALIZED_ADDR / 4] !== 99 ||
                dut.u_soc_top.u_data_ram.mem[RESULT_ADDR / 4] !== 6 ||
                dut.u_soc_top.u_data_ram.mem[VISITS_ADDR / 4] !== 1)
                $fatal(1, "FAIL C variables after boot %0d", boot);
            for (i = COPY_START / 4; i < COPY_END / 4; i = i + 1)
                if (dut.u_soc_top.u_data_ram.mem[i] !== expected_ram[i])
                    $fatal(1, "FAIL initial copy overwritten word %0d", i);
            $display("PASS C boot=%0d UART='C OK: 6' GPIO=06 initial=99 result=6 visits=1 stack_used=%0d",
                boot, 1024 - minimum_sp);
            // 仅按按钮复位，RAM 不重新装载。第二次 C 启动必须恢复初值。
            @(negedge clk); reset_button_n = 0;
            minimum_sp = 1024;
        end
        if (forwards == 0) $fatal(1, "FAIL no forwarding exercised");
        $display("PASS board_c ROM_words=512 RAM_words=256 frames=%0d starts=%0d forwarded=%0d warm_reset=PASS",
            frame_count, starts, forwards);
        $finish;
    end
    initial begin
        #3_000_000;
        $fatal(1, "FAIL C board timeout");
    end
endmodule
