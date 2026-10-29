module bht(
    input wire clk,
    input wire reset,

    input wire[31:0] lookup_pc_i,//IF级当前PC，用来查询计数器
    output wire predict_taken_o,//BHT对该PC预测跳转还是不跳转

    input wire update_valid_en,//EX级有一条条件分支真正完成，允许更新计数器
    input wire[31:0] update_pc_i,//这条已完成分支的PC
    input update_taken_i//这条分支实际是否跳转
);
//00强不跳转01弱不跳转10弱跳转11强跳转
reg[1:0] counter_q[0:31];
integer i;

wire[4:0] lookup_index = lookup_pc_i[6:2];
wire[4:0] update_index = update_pc_i[6:2];
//最高位决定预测方向
assign predict_taken_o = counter_q[lookup_index][1];

always @(posedge clk) begin
    if(reset)begin
        for(i=0;i<32;i=i+1)
            counter_q[i]<=2'b01;
    end
    else if(update_valid_en)begin
        if(update_taken_i)begin
            if(counter_q[update_index]!=2'b11)
                counter_q[update_index]<=counter_q[update_index]+2'b01;
        end
        else  begin
            if(counter_q[update_index]!=2'b00)
                counter_q[update_index]<=counter_q[update_index]-2'b01;
        end
    end
end



endmodule