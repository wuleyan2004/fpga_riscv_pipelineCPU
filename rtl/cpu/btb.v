module btb(
    input wire clk,
    input wire reset,
    input wire update_valid_en,//写使能
    //IF级
    input wire[31:0] lookup_pc_i,//IF级当前正在取指的PC
    output wire look_hit_o,//PC的索引和标签命中有效表项
    output wire[31:0] predict_target_o,//表项保存的分支目标地址
    //EX级
    input wire[31:0] update_pc_i,//EX级已经执行的分支指令地址，确认写入哪个表项
    input wire[31:0] update_target_i//分支目标
);
//32个表项
reg[31:0] valid_q;//该表项是否有效
reg[24:0] tag_q[0:31];//25位的标签
reg[31:0] target_q[0:31];//跳转地址

wire[4:0] lookup_index = lookup_pc_i[6:2];//查询指令的索引
wire[24:0] lookup_tag = lookup_pc_i[31:7];//查询指令的标签
wire[4:0] update_index = update_pc_i[6:2];//更新指令的索引
wire[24:0] update_tag = update_pc_i[31:7];//更新指令的标签

//IF级组合查询
assign look_hit_o = valid_q[lookup_index]&&(tag_q[lookup_index] == lookup_tag);
assign predict_target_o = look_hit_o?target_q[lookup_index]:32'b0;

//EX级在时钟沿更新
always @(posedge clk) begin
    if(reset)begin
        valid_q<=32'b0;
    end
    else if(update_valid_en)begin
        valid_q[update_index]<=1'b1;
        tag_q[update_index]    <= update_tag;
        target_q[update_index] <= update_target_i;
    end
end



endmodule