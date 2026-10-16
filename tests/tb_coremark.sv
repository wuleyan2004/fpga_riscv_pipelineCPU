`timescale 1ns/1ps
module tb_coremark #(
    parameter FILE_MODE = 1,
    parameter CALIBRATION_ONLY = 0,
    parameter BOOTS = 2,
    parameter ITERATE_PC = 0,
    parameter LIST_OFFSET = 0,
    parameter MATRIX_OFFSET = 0,
    parameter STATE_OFFSET = 0,
    parameter EXPECT_LIST = 16'he714,
    parameter EXPECT_MATRIX = 16'h1fd7,
    parameter EXPECT_STATE = 16'h8e3a,
    parameter HALT_PC = 0,
    parameter BSS_END = 0,
    parameter SNAPSHOT_START = 0,
    parameter SNAPSHOT_END = 0,
    parameter START_CYCLES_ADDR = 0,
    parameter STOP_CYCLES_ADDR = 0
);
    localparam CLKS_PER_BIT = 27000000 / 115200;
    reg clk = 0, reset_button_n = 0;
    wire [7:0] gpio_out;
    wire tx;
    board_top #(.COREMARK_FILE(FILE_MODE)) dut (
        .clk(clk), .reset_button_n(reset_button_n), .gpio_button_n(4'b1111),
        .gpio_out(gpio_out), .uart_tx_pin(tx));
    always #18.5185 clk = ~clk;
    reg [31:0] expected_rom[0:8191];
    reg [31:0] expected_ram[0:16383];
    reg [7:0] serial_byte;
    integer serial_file, frames = 0, starts = 0;
    integer boot, i, cycles = 0, min_sp = 65536;
    reg halted = 0;
    reg [63:0] elapsed_cycles, start_cycles, stop_cycles;
    reg [31:0] result_pointer = 0;
    function [15:0] result_half(input integer offset);
        reg [31:0] address;
        begin
            address = result_pointer + offset;
            result_half = dut.u_soc_top.u_data_ram.mem[address/4] >> (address[1] ? 16 : 0);
        end
    endfunction

    // 完整 8N1 接收，保存真正来自引脚的串口文本。
    initial forever begin
        @(negedge tx);
        if (!dut.reset) begin
            repeat (CLKS_PER_BIT / 2) @(posedge clk); #1;
            if (tx !== 0) $fatal(1, "FAIL UART start bit");
            for (integer b = 0; b < 8; b = b + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk); #1;
                serial_byte[b] = tx;
            end
            repeat (CLKS_PER_BIT) @(posedge clk); #1;
            if (tx !== 1 || (^serial_byte === 1'bx)) $fatal(1, "FAIL UART frame");
            $fwrite(serial_file, "%c", serial_byte);
            frames = frames + 1;
        end
    end

    always @(posedge clk) begin
        if (dut.reset) begin halted = 0; result_pointer = 0; end
        else begin
            cycles = cycles + 1;
            if (dut.u_soc_top.debug_misaligned) $fatal(1, "FAIL misaligned access");
            if (dut.u_soc_top.u_uart.tx_start) starts = starts + 1;
            if (dut.u_soc_top.mem_valid && dut.u_soc_top.unmapped_selected)
                $fatal(1, "FAIL unmapped address %h", dut.u_soc_top.mem_addr);
            if (dut.u_soc_top.u_cpu_core.ex_wb_valid_q &&
                dut.u_soc_top.u_cpu_core.ex_wb_pc_q >= 32768)
                $fatal(1, "FAIL PC outside ROM");
            if (dut.u_soc_top.u_cpu_core.u_regfile.regs[2] > 0 &&
                dut.u_soc_top.u_cpu_core.u_regfile.regs[2] < min_sp)
                min_sp = dut.u_soc_top.u_cpu_core.u_regfile.regs[2];
            if (dut.u_soc_top.mem_valid && dut.u_soc_top.mem_write && dut.u_soc_top.ram_selected) begin
                if (dut.u_soc_top.mem_addr >= SNAPSHOT_START &&
                    dut.u_soc_top.mem_addr < SNAPSHOT_END)
                    $fatal(1, "FAIL initial snapshot overwritten");
                // 最低 16 字节栈区作为保护区：实际调用不得用尽预留栈。
                if (dut.u_soc_top.mem_addr >= 61440 && dut.u_soc_top.mem_addr < 61456)
                    $fatal(1, "FAIL stack guard overwritten");
            end
            if (dut.u_soc_top.u_cpu_core.ex_wb_valid_q &&
                dut.u_soc_top.u_cpu_core.ex_wb_pc_q == HALT_PC)
                halted = 1;
            if (dut.u_soc_top.u_cpu_core.ex_wb_valid_q &&
                dut.u_soc_top.u_cpu_core.ex_wb_pc_q == ITERATE_PC)
                result_pointer = dut.u_soc_top.u_cpu_core.u_regfile.regs[10];
            if (cycles % 1000000 == 0)
                $display("PROGRESS cycles=%0d pc=%h uart_frames=%0d", cycles,
                    dut.u_soc_top.pc, frames);
        end
    end

    initial begin
        serial_file = $fopen("uart.txt", "w");
        if (!serial_file) $fatal(1, "FAIL UART log open");
        $readmemh("coremark_program.hex", expected_rom);
        $readmemh("coremark_data.hex", expected_ram);
        #1;
        for (i = 0; i < 8192; i = i + 1)
            if (dut.u_soc_top.u_instruction_rom.g_coremark_program.imem[i] !== expected_rom[i])
                $fatal(1, "FAIL ROM word %0d", i);
        for (i = 0; i < 16384; i = i + 1)
            if (dut.u_soc_top.u_data_ram.mem[i] !== expected_ram[i])
                $fatal(1, "FAIL RAM word %0d", i);
        // 初次启动也必须执行真正的 .data 复制和 BSS 清零。
        for (i = 0; i < BSS_END / 4; i = i + 1)
            dut.u_soc_top.u_data_ram.mem[i] = 32'ha5a5a5a5;
        for (boot = 1; boot <= BOOTS; boot = boot + 1) begin
            repeat (3) @(negedge clk);
            reset_button_n = 1;
            if (CALIBRATION_ONLY) begin
                wait (result_pointer != 0 && dut.u_soc_top.u_data_ram.mem[STOP_CYCLES_ADDR/4] !== 0);
                repeat (60) @(posedge clk); #1;
                if (result_pointer == 0 || result_half(LIST_OFFSET) !== EXPECT_LIST ||
                    result_half(MATRIX_OFFSET) !== EXPECT_MATRIX || result_half(STATE_OFFSET) !== EXPECT_STATE)
                    $fatal(1, "FAIL automatic calibration CRC ptr=%h list=%h matrix=%h state=%h",
                        result_pointer, result_half(LIST_OFFSET), result_half(MATRIX_OFFSET), result_half(STATE_OFFSET));
            end else begin
                wait (halted); #1;
                if (dut.u_soc_top.u_cpu_core.u_regfile.regs[2] !== 65536 ||
                dut.u_soc_top.u_cpu_core.u_regfile.regs[10] !== 0 ||
                min_sp < 61456 || gpio_out !== 2 || starts != frames)
                $fatal(1, "FAIL CoreMark return/stack/UART state sp=%h min_sp=%0d starts=%0d frames=%0d",
                    dut.u_soc_top.u_cpu_core.u_regfile.regs[2], min_sp, starts, frames);
            end
            start_cycles = {dut.u_soc_top.u_data_ram.mem[START_CYCLES_ADDR/4+1],
                            dut.u_soc_top.u_data_ram.mem[START_CYCLES_ADDR/4]};
            stop_cycles = {dut.u_soc_top.u_data_ram.mem[STOP_CYCLES_ADDR/4+1],
                           dut.u_soc_top.u_data_ram.mem[STOP_CYCLES_ADDR/4]};
            elapsed_cycles = stop_cycles - start_cycles;
            if (stop_cycles <= start_cycles || elapsed_cycles < 1024)
                $fatal(1, "FAIL real cycle timer");
            for (i = SNAPSHOT_START/4; i < SNAPSHOT_END/4; i = i + 1)
                if (dut.u_soc_top.u_data_ram.mem[i] !== expected_ram[i])
                    $fatal(1, "FAIL RAM snapshot retained value");
            $display("PASS CoreMark boot=%0d cycles=%0d elapsed_cycles=%0d stack_used=%0d frames=%0d",
                boot, cycles, elapsed_cycles, 65536-min_sp, frames);
            $fwrite(serial_file, "\n--BOOT-END--\n");
            $fflush(serial_file);
            @(negedge clk); reset_button_n = 0;
            min_sp = 65536;
        end
        $fclose(serial_file);
        $display("PASS coremark_board ROM_words=8192 RAM_words=16384 boots=%0d calibration_only=%0d", BOOTS, CALIBRATION_ONLY);
        $finish;
    end
    initial begin
        repeat (20000000) @(posedge clk);
        $fatal(1, "FAIL CoreMark simulation timeout pc=%h", dut.u_soc_top.pc);
    end
endmodule
