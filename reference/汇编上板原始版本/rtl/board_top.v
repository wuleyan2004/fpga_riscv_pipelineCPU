module board_top #(
    parameter integer BOARD_DEMO_DELAY_COUNT = 6_750_000
)(
    input  wire       clk,
    input  wire       reset_button_n,
    input  wire [3:0] gpio_button_n,
    output wire [7:0] gpio_out,
    output wire       uart_tx_pin
);
    // 上电先保持复位；按钮按下异步置位，松开后经过两个时钟沿释放。
    // CPU/外设在 clk 上升沿使用这个复位信号。
    (* syn_preserve = 1 *) reg reset_meta_q = 1'b1;
    (* syn_preserve = 1 *) reg reset_sync_q = 1'b1;
    always @(posedge clk or negedge reset_button_n) begin
        if (!reset_button_n) begin
            reset_meta_q <= 1'b1;
            reset_sync_q <= 1'b1;
        end else begin
            reset_meta_q <= 1'b0;
            reset_sync_q <= reset_meta_q;
        end
    end
    wire reset = reset_sync_q;

    // 每个按钮独立同步到 clk 域，第二级输出才送入 GPIO。
    // 此处只同步电平；需要按键事件计数时再考虑消抖。
    (* syn_preserve = 1 *) reg [3:0] gpio_meta_q;
    (* syn_preserve = 1 *) reg [3:0] gpio_sync_q;
    always @(posedge clk) begin
        if (reset) begin
            gpio_meta_q <= 4'b0000;
            gpio_sync_q <= 4'b0000;
        end else begin
            gpio_meta_q <= ~gpio_button_n;
            gpio_sync_q <= gpio_meta_q;
        end
    end
    wire [7:0] gpio_in = {4'b0000, gpio_sync_q};

    soc_top #(
        .UART_CLK_FREQ (27_000_000),
        .BOARD_DEMO    (1),
        .BOARD_DEMO_DELAY_COUNT (BOARD_DEMO_DELAY_COUNT)
    ) u_soc_top (
        .clk                (clk),
        .reset              (reset),
        .gpio_in            (gpio_in),
        .gpio_out           (gpio_out),
        .uart_tx_pin        (uart_tx_pin),
        .debug_pc           (),
        .debug_instruction  (),
        .debug_mem_valid    (),
        .debug_mem_ready    (),
        .debug_misaligned   ()
    );

endmodule
