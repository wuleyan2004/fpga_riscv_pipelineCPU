module csr_file(
    input wire clk,
    input wire reset,

    input  wire        csr_exec_i, //这条 CSR 指令本周期要执行
    input  wire [11:0] csr_addr_i,//指定要访问哪个 CSR
    input  wire [2:0]  csr_cmd_i, //指定 CSR 操作，直接对应 CSR 指令的 funct3
    input  wire [4:0]  rs1_field_i,//指令里的 rs1 字段；立即数形式把它当作 5 位数值，某些指令还用它判断是否只读。
    input  wire [31:0] rs1_data_i,//通用寄存器 rs1 中的值，供非立即数形式使用
    output reg  [31:0] csr_rdata_o, //当前 CSR 的旧值，可写回目标寄存器 rd
    output wire        csr_supported_o,//当前 csr_addr 是否是这个模块已实现的 CSR
    input  wire        trap_valid_i,//发生异常，要保存异常信息
    input  wire [31:0] trap_pc_i,//出异常的指令地址，保存到 mepc
    input  wire [31:0] trap_cause_i,//异常原因，保存到 mcause
    input  wire [31:0] trap_value_i,//异常补充信息，保存到 mtval
    input  wire        mret_valid_i,//执行 MRET，恢复 mstatus 中的中断使能状态

    output wire [31:0] mtvec_o,//输出异常处理程序的入口地址，供 CPU 跳转
    output wire [31:0] mepc_o//输出异常返回地址，供 CPU 执行 MRET 时跳转
);

    reg [31:0] mtvec_q;//异常处理程序的入口地址。发生异常后，CPU 跳到这里
    reg [31:0] mepc_q;//发生异常的指令地址。执行 MRET 时，CPU 跳回这里
    reg [31:0] mcause_q; //异常原因，例如非法指令或 ECALL
    reg [31:0] mtval_q;//异常的补充信息，例如非法指令的编码或出错的地址
    reg mie_q;//当前是否允许机器模式中断，1 表示允许
    reg mpie_q; //暂存进入异常前的 mie_q，供返回时恢复

    //mstatus 这个 CSR 的 32 位读出值
    wire [31:0] mstatus_value =
        32'h0000_1800 | ({31'b0, mpie_q} << 7) |
                         ({31'b0, mie_q}  << 3);
    //输出异常处理程序的入口地址
    assign mtvec_o = mtvec_q;
    //输出异常返回地址
    assign mepc_o = mepc_q;
    //当前csr_addr是否是这个模块已实现的CSR
    assign csr_supported_o =
        csr_addr_i == 12'h305 || // mtvec
        csr_addr_i == 12'h341 || // mepc
        csr_addr_i == 12'h342 || // mcause
        csr_addr_i == 12'h343 || // mtval
        csr_addr_i == 12'h300 ;  // mstatus

//读出当前CSR的旧值
always @(*) begin
        case (csr_addr_i)
            12'h305: csr_rdata_o = mtvec_q;
            12'h341: csr_rdata_o = mepc_q;
            12'h342: csr_rdata_o = mcause_q;
            12'h343: csr_rdata_o = mtval_q;
            12'h300: csr_rdata_o = mstatus_value;
            default: csr_rdata_o = 32'b0;
        endcase
    end

//CSR 操作要使用的数值
//如果为1，则使用的数值为指令里rs1的字段，如果为0，则使用通用寄存器里rs1的数值
 wire [31:0] csr_operand = csr_cmd_i[2] ? {27'b0, rs1_field_i} : rs1_data_i;
//计算 CSR 准备写入的新值
reg [31:0] csr_new_value;
always @(*) begin
    case (csr_cmd_i[1:0])
        2'b01: csr_new_value = csr_operand;              // 写
        2'b10: csr_new_value = csr_rdata_o | csr_operand;  // 置位
        2'b11: csr_new_value = csr_rdata_o & ~csr_operand; // 清位
        default: csr_new_value = csr_rdata_o;
    endcase
end

// CSRRS/CSRRC 的 rs1 字段为 0 时只读；CSRRW 始终写
wire csr_write =
     csr_exec_i && csr_supported_o &&
    ((csr_cmd_i[1:0] == 2'b01) ||
    ((csr_cmd_i[1:0] == 2'b10 || csr_cmd_i[1:0] == 2'b11) &&
    rs1_field_i != 5'd0));

always @(posedge clk) begin
    if (reset) begin
        mtvec_q  <= 32'h0000_7FFC;
        mepc_q   <= 32'b0;
        mcause_q <= 32'b0;
        mtval_q  <= 32'b0;
        mie_q    <= 1'b0;
        mpie_q   <= 1'b0;
        end 
    else if (trap_valid_i) begin
        mepc_q   <= trap_pc_i;
        mcause_q <= trap_cause_i;
        mtval_q  <= trap_value_i;
        mpie_q   <= mie_q;
        mie_q    <= 1'b0;
        end 
    else if (mret_valid_i) begin
        mie_q  <= mpie_q;
        mpie_q <= 1'b1;
        end 
    else if (csr_write) begin
        case (csr_addr_i)
            12'h300: begin
                mie_q  <= csr_new_value[3];
                mpie_q <= csr_new_value[7];
                end
            12'h305: mtvec_q  <= {csr_new_value[31:2], 2'b00};
            12'h341: mepc_q   <= {csr_new_value[31:2], 2'b00};
            12'h342: mcause_q <= csr_new_value;
            12'h343: mtval_q  <= csr_new_value;
            endcase
        end
    end
endmodule
