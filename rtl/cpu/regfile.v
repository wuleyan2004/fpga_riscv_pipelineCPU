//读数据是组合逻辑，写数据是时序逻辑
module regfile(
    input clk,//输入时钟
    input[4:0] rs1_addr,//输入读地址
    input[4:0] rs2_addr,//输入读地址
    output[31:0] rs1_data,//输出读数据
    output[31:0] rs2_data,//输出读数据
    input[4:0] rd_addr,//输入写地址
    input[31:0] rd_data,//输入写数据
    input rd_we//输入写使能
);
//32个32位寄存器
reg[31:0]regs[0:31];

integer i;

initial begin
    for(i=0;i<32;i=i+1)
    regs[i] = 32'd0;
end
//写寄存器：时序逻辑
always @(posedge clk) begin
    if (rd_we&&(rd_addr!=5'd0)) begin
       regs[rd_addr]<=rd_data; 
    end
end
//读寄存器：组合逻辑
assign rs1_data = (rs1_addr == 5'd0)?32'd0 : regs[rs1_addr];
assign rs2_data = (rs2_addr == 5'd0)?32'd0 : regs[rs2_addr];

endmodule