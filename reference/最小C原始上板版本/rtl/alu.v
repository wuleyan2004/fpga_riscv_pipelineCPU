module alu(
    input  [31:0] a,//操作数a
    input  [31:0] b,//操作数b
    input  [3:0]  op,//操作
    output reg [31:0] result//计算结果
);

always @(*) begin
    case (op)

        4'b0000: result = a + b;

        4'b0001: result = a - b;

        4'b0010: result = a & b;

        4'b0011: result = a | b;

        4'b0100: result = a ^ b;
        //左移运算
        4'b0101: result = a << b[4:0];
        //右移运算，左边补0
        4'b0110: result = a >> b[4:0];
        //算术右移，符号位填补左侧
        4'b0111: result = $signed(a) >>> b[4:0];
        //有符号比较
        4'b1000: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
        //无符号比较
        4'b1001: result = (a < b) ? 32'd1 : 32'd0;

        default: result = 32'd0;

    endcase
end

endmodule