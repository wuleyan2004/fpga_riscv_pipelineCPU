module soc_top #(
    parameter COREMARK_PROGRAM = 0,
    parameter COREMARK_FILE = 0,
    parameter C_PROGRAM = 0,
    parameter UART_CLK_FREQ = 50_000_000,
    parameter BOARD_DEMO = 0,
    parameter integer BOARD_DEMO_DELAY_COUNT = 6_750_000
)(
    input wire clk,
    input wire reset,

    input  wire [7:0] gpio_in,
    output wire [7:0] gpio_out,
    output wire       uart_tx_pin,

    // 方便 Testbench 观察
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instruction,
    output wire        debug_mem_valid,
    output wire        debug_mem_ready,
    output wire        debug_misaligned
);

//
// 1. Instruction ROM 信号
//

wire [31:0] pc;
wire [31:0] instruction;


//
// 2. Data RAM 接口信号
//

wire        mem_valid;
wire        mem_write;
wire [3:0]  mem_wstrb;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;

wire        mem_ready;
wire [31:0] mem_rdata;
wire profile_retire, profile_mem_wait, profile_raw_wait;
wire profile_branch, profile_branch_taken, profile_branch_mispredict, profile_jump;

wire ram_selected;
wire gpio_selected;

wire        ram_ready;
wire [31:0] ram_rdata;

wire        gpio_ready;
wire [31:0] gpio_rdata;

assign ram_selected =
    COREMARK_PROGRAM ? (mem_addr[31:16] == 16'b0) :
                       (mem_addr[31:10] == 22'b0);

assign gpio_selected =
    (mem_addr[31:3] == (32'h1000_0000 >> 3));

wire        uart_selected;
wire        uart_ready;
wire [31:0] uart_rdata;

assign uart_selected =
    (mem_addr[31:3] == (32'h1000_0010 >> 3));


//
// 3. 实例化 Instruction ROM
//

instruction_rom #(
    .COREMARK_PROGRAM       (COREMARK_PROGRAM),
    .COREMARK_FILE          (COREMARK_FILE),
    .C_PROGRAM              (C_PROGRAM),
    .BOARD_DEMO             (BOARD_DEMO),
    .BOARD_DEMO_DELAY_COUNT (BOARD_DEMO_DELAY_COUNT)
) u_instruction_rom (
    .pc        (pc),
    .instruction (instruction)
);


//
// 4. 实例化三级流水线 CPU（IF / EX / WB）
//

cpu_core_pipeline #(.RAM_BYTES(COREMARK_PROGRAM ? 65536 : 1024)) u_cpu_core (
    .clk         (clk),
    .reset       (reset),

    // Instruction ROM
    .instruction (instruction),
    .pc          (pc),

    // Data RAM 请求
    .mem_valid   (mem_valid),
    .mem_write   (mem_write),
    .mem_wstrb   (mem_wstrb),
    .mem_addr    (mem_addr),
    .mem_wdata   (mem_wdata),

    // Data RAM 响应
    .mem_ready   (mem_ready),
    .mem_rdata   (mem_rdata),
    .debug_misaligned (debug_misaligned),
    .profile_retire (profile_retire),
    .profile_mem_wait (profile_mem_wait),
    .profile_raw_wait (profile_raw_wait),
    .profile_branch (profile_branch),
    .profile_branch_taken (profile_branch_taken),
    .profile_branch_mispredict (profile_branch_mispredict),
    .profile_jump (profile_jump)
);


//
// 5. 实例化 Data RAM
//

sync_data_ram #(
    .C_PROGRAM(C_PROGRAM),
    .COREMARK_PROGRAM(COREMARK_PROGRAM),
    .COREMARK_FILE(COREMARK_FILE),
    .WORDS(COREMARK_PROGRAM ? 16384 : 256),
    .ADDR_BITS(COREMARK_PROGRAM ? 14 : 8)
) u_data_ram (
    .clk       (clk),
    .reset     (reset),

    .mem_valid (mem_valid && ram_selected),
    .mem_write (mem_write),
    .mem_wstrb (mem_wstrb),
    .mem_addr  (mem_addr),
    .mem_wdata (mem_wdata),

    .mem_ready (ram_ready),
    .mem_rdata (ram_rdata)
);

//GPIO实例
gpio_mmio u_gpio (
    .clk       (clk),
    .reset     (reset),

    .mem_valid (mem_valid && gpio_selected),
    .mem_write (mem_write),
    .mem_wstrb (mem_wstrb),
    .mem_addr  (mem_addr),
    .mem_wdata (mem_wdata),

    .mem_ready (gpio_ready),
    .mem_rdata (gpio_rdata),

    .gpio_in   (gpio_in),
    .gpio_out  (gpio_out)
);

wire timer_selected = (mem_addr[31:3] == (32'h1000_0020 >> 3));
wire timer_ready;
wire [31:0] timer_rdata;
timer_mmio u_timer (
    .clk(clk), .reset(reset), .mem_valid(mem_valid && timer_selected),
    .mem_write(mem_write), .mem_addr(mem_addr),
    .mem_ready(timer_ready), .mem_rdata(timer_rdata)
);

wire perf_selected = (mem_addr[31:4] == (32'h1000_0030 >> 4)) ||
                     (mem_addr[31:4] == (32'h1000_0040 >> 4)) ||
                     (mem_addr[31:4] == (32'h1000_0050 >> 4));
wire perf_ready;
wire [31:0] perf_rdata;
perf_counter_mmio u_perf (
    .clk(clk), .reset(reset), .mem_valid(mem_valid && perf_selected),
    .mem_write(mem_write), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_ready(perf_ready), .mem_rdata(perf_rdata),
    .retire(profile_retire), .mem_wait(profile_mem_wait),
    .raw_wait(profile_raw_wait), .branch(profile_branch),
    .branch_taken(profile_branch_taken),
    .branch_mispredict(profile_branch_mispredict), .jump(profile_jump)
);

wire unmapped_selected;

// 地址不属于 RAM、GPIO 或 UART
assign unmapped_selected =
    !ram_selected && !gpio_selected && !uart_selected && !timer_selected && !perf_selected;

assign mem_ready =
    ram_selected  ? ram_ready :
    gpio_selected ? gpio_ready :
    uart_selected ? uart_ready :
    timer_selected ? timer_ready :
    perf_selected ? perf_ready :
                    (mem_valid && unmapped_selected);

assign mem_rdata =
    ram_selected  ? ram_rdata :
    gpio_selected ? gpio_rdata :
    uart_selected ? uart_rdata :
    timer_selected ? timer_rdata :
    perf_selected ? perf_rdata :
                    32'b0;

uart_mmio #(
    .CLK_FREQ (UART_CLK_FREQ)
) u_uart (
    .clk         (clk),
    .reset       (reset),

    .mem_valid   (mem_valid && uart_selected),
    .mem_write   (mem_write),
    .mem_wstrb   (mem_wstrb),
    .mem_addr    (mem_addr),
    .mem_wdata   (mem_wdata),

    .mem_ready   (uart_ready),
    .mem_rdata   (uart_rdata),

    .uart_tx_pin (uart_tx_pin)
);

//
// 6. 调试输出
//

// 这里观察的是 IF 级取指 PC/指令；访存请求来自 EX/WB 级。
assign debug_pc          = pc;
assign debug_instruction = instruction;
assign debug_mem_valid   = mem_valid;
assign debug_mem_ready   = mem_ready;

endmodule
