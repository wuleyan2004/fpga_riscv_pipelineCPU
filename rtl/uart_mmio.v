module uart_mmio #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        mem_valid,
    input  wire        mem_write,
    input  wire [3:0]  mem_wstrb,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,

    output reg         mem_ready,
    output reg  [31:0] mem_rdata,

    output wire        uart_tx_pin
);

localparam TX_DATA_ADDR = 32'h1000_0010;
localparam STATUS_ADDR  = 32'h1000_0014;

localparam IDLE = 1'b0;
localparam RESP = 1'b1;

reg state;

wire tx_busy;
wire tx_start;

// 只有UART空闲、CPU写TX_DATA低字节时，才产生一次启动脉冲
assign tx_start =
    (state == IDLE) &&
    mem_valid &&
    mem_write &&
    (mem_addr[31:2] == TX_DATA_ADDR[31:2]) &&
    mem_wstrb[0] &&
    !tx_busy;

uart_tx #(
    .CLK_FREQ  (CLK_FREQ),
    .BAUD_RATE (BAUD_RATE)
) u_uart_tx (
    .clk   (clk),
    .reset (reset),
    .start (tx_start),
    .data  (mem_wdata[7:0]),
    .tx    (uart_tx_pin),
    .busy  (tx_busy)
);

always @(posedge clk) begin
    if(reset)begin
        state     <= IDLE;
        mem_ready <= 1'b0;
        mem_rdata <= 32'b0;
    end
    else begin
        case(state)
            IDLE:begin
                mem_ready<=1'b0;
                if (mem_valid) begin
                    case (mem_addr[31:2])
                        TX_DATA_ADDR[31:2]: begin
                            if (!mem_write) begin
                                // TX_DATA只用于写；读时返回0
                                mem_rdata <= 32'b0;
                                mem_ready <= 1'b1;
                                state     <= RESP;
                            end
                            else if (!mem_wstrb[0] || !tx_busy) begin
                                // 高字节写入忽略；有效写入等UART能接收后完成
                                mem_ready <= 1'b1;
                                state     <= RESP;
                            end
                            // 正在发送且要写低字节：保持等待
                        end

                        STATUS_ADDR[31:2]: begin
                            // bit 0表示busy；写STATUS被忽略
                            mem_rdata <= {31'b0, tx_busy};
                            mem_ready <= 1'b1;
                            state     <= RESP;
                        end

                        default: begin
                            mem_rdata <= 32'b0;
                            mem_ready <= 1'b1;
                            state     <= RESP;
                        end
                    endcase
                end                
            end
            RESP:begin
                mem_ready <= 1'b0;
                state     <= IDLE;              
            end

            default: begin
                mem_ready <= 1'b0;
                state     <= IDLE;
            end
        endcase
    end
end

endmodule