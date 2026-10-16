module branch_compare (
    input  wire [31:0] rs1_data,//CPU寄存器读出来的rs1
    input  wire [31:0] rs2_data,//CPU寄存器读出来的rs2

    output wire        equal,//如果rs1==rs2，那么该信号置为1
    output wire        signed_less,//如果按有符号rs1<rs2，那么该信号置为1
    output wire        unsigned_less//如果按无符号rs1<rs2，那么该信号置为1
);

assign equal = (rs1_data == rs2_data);

// 把两个操作数看作有符号数后再比较
assign signed_less = ($signed(rs1_data) < $signed(rs2_data));

// 默认把两个操作数看作无符号数
assign unsigned_less = (rs1_data < rs2_data);

endmodule