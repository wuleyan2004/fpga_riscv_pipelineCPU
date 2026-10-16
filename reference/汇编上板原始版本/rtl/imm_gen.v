module imm_gen (
    input  wire [31:0] instruction,//输入指令
    input  wire [2:0]  imm_type,//输入立即数类型
    output reg  [31:0] imm//输出立即数
);
//对应输入imm_type
localparam IMM_I = 3'd0;
localparam IMM_S = 3'd1;
localparam IMM_B = 3'd2;
localparam IMM_U = 3'd3;
localparam IMM_J = 3'd4;

always @(*) begin
    imm = 32'b0;

    case (imm_type)
        IMM_I: imm = {
            {20{instruction[31]}},
            instruction[31:20]
        };

        IMM_S: imm = {
            {20{instruction[31]}},
            instruction[31:25],
            instruction[11:7]
        };

        IMM_B: imm = {
            {19{instruction[31]}},
            instruction[31],
            instruction[7],
            instruction[30:25],
            instruction[11:8],
            1'b0
        };

        IMM_U: imm = {
            instruction[31:12],
            12'b0
        };

        IMM_J: imm = {
            {11{instruction[31]}},
            instruction[31],
            instruction[19:12],
            instruction[20],
            instruction[30:21],
            1'b0
        };

        default: imm = 32'b0;
    endcase
end

endmodule