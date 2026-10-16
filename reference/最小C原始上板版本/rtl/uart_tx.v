module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output wire       busy
);

localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
localparam integer COUNT_WIDTH =
    (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;//计数器的位宽

localparam [1:0] IDLE  = 2'd0;
localparam [1:0] START = 2'd1;
localparam [1:0] DATA  = 2'd2;
localparam [1:0] STOP  = 2'd3;

reg [1:0] state;
reg [COUNT_WIDTH-1:0] bit_timer;
reg [2:0] bit_index;
reg [7:0] data_reg;

assign busy = (state != IDLE);

always @(posedge clk) begin
    if (reset) begin
        state     <= IDLE;
        bit_timer <= 0;
        bit_index <= 0;
        data_reg  <= 0;
        tx        <= 1'b1; // UART空闲电平为1
    end
    else begin
        case(state)
            IDLE:begin
                tx<=1'b1;
                bit_timer<=0;

                if(start)begin
                    data_reg  <= data; // 先保存数据，发送期间不受外部变化影响
                    bit_index <= 0;
                    tx        <= 1'b0; // 起始位
                    state     <= START;
                end
                
            end
            START:begin
                if (bit_timer == CLKS_PER_BIT - 1) begin
                    bit_timer <= 0;
                    tx        <= data_reg[0];
                    state     <= DATA;
                end
                else
                    bit_timer <= bit_timer + 1'b1;
            end
            DATA:begin
                if (bit_timer == CLKS_PER_BIT - 1) begin
                    bit_timer <= 0;

                    if (bit_index == 3'd7) begin
                        tx    <= 1'b1; // 停止位
                        state <= STOP;
                    end
                    else begin
                        bit_index <= bit_index + 1'b1;
                        tx        <= data_reg[bit_index + 1'b1];
                    end
                end
                else
                    bit_timer <= bit_timer + 1'b1;
            end
            STOP:begin
                if (bit_timer == CLKS_PER_BIT - 1) begin
                    bit_timer <= 0;
                    tx        <= 1'b1;
                    state     <= IDLE;
                end
                else
                    bit_timer <= bit_timer + 1'b1;                
            end
            default: begin
                state <= IDLE;
                tx    <= 1'b1;
            end
        endcase
    end
end

endmodule