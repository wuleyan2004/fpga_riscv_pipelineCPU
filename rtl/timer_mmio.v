// 只读的 64 位时钟周期计数器：0x10000020 低位，0x10000024 高位。
// 每个非复位周期加 1，包括 CPU 访存等待周期；写入忽略。
module timer_mmio (
    input wire clk,
    input wire reset,
    input wire mem_valid,
    input wire mem_write,
    input wire [31:0] mem_addr,
    output wire mem_ready,
    output reg [31:0] mem_rdata
);
    reg [63:0] cycle_q;
    reg response_q;
    assign mem_ready = response_q;
    always @(posedge clk) begin
        if (reset) begin
            cycle_q <= 64'b0;
            response_q <= 1'b0;
            mem_rdata <= 32'b0;
        end else begin
            cycle_q <= cycle_q + 64'd1;
            if (response_q) begin
                response_q <= 1'b0;
            end else if (mem_valid) begin
                mem_rdata <= mem_write ? 32'b0 :
                             (mem_addr[2] ? cycle_q[63:32] : cycle_q[31:0]);
                response_q <= 1'b1;
            end
        end
    end
endmodule
