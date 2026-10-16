module sync_data_ram(
    input wire clk,
    input wire reset,
    
    input wire mem_valid,//CPU正在提出一个有效的访存请求
    input wire mem_write,//0表示从内存读取到CPU，1表示从CPU存到内存
    input wire[3:0] mem_wstrb,//字节写使能
    input wire[31:0] mem_addr,//CPU想访问的字节地址
    input wire[31:0] mem_wdata,//CPU要写入内存的数据

    output wire mem_ready,//内存已经完成当前请求，CPU可以接收结果并继续运行
    output reg[31:0] mem_rdata//内存返回给CPU的数据
);

reg[31:0] mem[0:255];//256个，每个长32

localparam IDLE = 1'b0;//空闲状态
localparam RESP = 1'b1;//响应状态

reg state;

wire[7:0] word_index;//RAM中第几个32位word
assign word_index = mem_addr[9:2];

assign mem_ready = (state == RESP);

always@(posedge clk)begin
    
    if(reset)begin
        state<=IDLE;
        mem_rdata<=32'b0;
    end
    else begin
        case(state)
            IDLE:begin
                if(mem_valid)begin
                    if(mem_write)begin
                        if(mem_wstrb[0])
                            mem[word_index][7:0]<=mem_wdata[7:0];
                        if (mem_wstrb[1])
                            mem[word_index][15:8]<= mem_wdata[15:8];
                        if (mem_wstrb[2])
                            mem[word_index][23:16]<= mem_wdata[23:16];
                        if (mem_wstrb[3])
                            mem[word_index][31:24]<= mem_wdata[31:24];
                    end
                    else begin
                        mem_rdata<=mem[word_index];
                    end

                    state<=RESP;
                end
            end

            RESP:begin
                state<=IDLE;
            end

            default:begin
                state<=IDLE;
            end
        endcase
    end
end

endmodule