//组合逻辑
module decoder(
    //输入信号
    input wire[6:0] opcode,//输入指令中的opcode
    input wire[2:0] funct3,//输入指令中的funct3
    input wire[6:0] funct7,//输入指令中的funct7
    input wire[31:0] instruction,//输入完整的指令
    //输出信号
    output reg reg_write,//寄存器是否写
    output reg alu_src_imm,//alu第二个数是否是立即数
    output reg[3:0] alu_op,//alu的操作
    output reg mem_read,//是否读内存
    output reg mem_write,//是否写内存
    output reg [2:0] imm_type,//立即数类型
    output reg branch_en,//当前指令是否是合法的分支指令
    output reg jal_en,//当前是否是JAL指令
    output reg jalr_en,//当前指令是否是合法的JALR
    output reg lui_en,//当前指令是否是合法的LUI
    output reg auipc_en,//当前指令是否是合法的auipc
    output reg illegal,//当前指令是否是合法的指令
    output reg ecall,
    output reg ebreak,
    output reg mret,//表示当前指令是MRET，MRET是“从机器模式异常处理程序返回”的指令
    output reg csr_en,//表示当前指令要访问 CSR
    output reg[2:0] csr_cmd//表示怎样访问 CSR，CSR是控制与状态存储器
);

//立即数类型
//对应输出imm_type
localparam IMM_I    = 3'd0;
localparam IMM_S    = 3'd1;
localparam IMM_B    = 3'd2;
localparam IMM_U    = 3'd3;
localparam IMM_J    = 3'd4;
localparam IMM_NONE = 3'd7;

//opcode
//对应输入opcode
localparam OPCODE_OP_IMM = 7'b0010011;
localparam OPCODE_OP     = 7'b0110011;
localparam OPCODE_LOAD   = 7'b0000011;
localparam OPCODE_STORE  = 7'b0100011;
localparam OPCODE_BRANCH = 7'b1100011;
localparam OPCODE_JAL    = 7'b1101111;
localparam OPCODE_JALR   = 7'b1100111;
localparam OPCODE_LUI    = 7'b0110111;
localparam OPCODE_AUIPC  = 7'b0010111;
localparam OPCODE_MISC_MEM = 7'b0001111;
localparam OPCODE_SYSTEM = 7'b1110011;

//ALU操作编码
//对应输出alu_op
//result = a + b
localparam ALU_ADD = 4'b0000;
//result = a - b
localparam ALU_SUB = 4'b0001;
//result = a & b
localparam ALU_AND = 4'b0010;
//result = a | b
localparam ALU_OR  = 4'b0011;
//result = a ^ b
localparam ALU_XOR = 4'b0100;
//result = a << b[4:0]
localparam ALU_SLL = 4'b0101;
//result = a >> b[4:0]
localparam ALU_SRL = 4'b0110;
//result = $signed(a) >>> b[4:0]
localparam ALU_SRA = 4'b0111;
//result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0
localparam ALU_SLT = 4'b1000;
//result = (a < b) ? 32'd1 : 32'd0
localparam ALU_SLTU = 4'b1001;

always @(*) begin
    // 默认值
    reg_write   = 1'b0;
    alu_src_imm = 1'b0;
    alu_op      = ALU_ADD;
    mem_read    = 1'b0;
    mem_write   = 1'b0;
    imm_type    = IMM_NONE;
    branch_en = 1'b0;
    jal_en = 1'b0;
    jalr_en = 1'b0;
    lui_en = 1'b0;
    auipc_en = 1'b0;
    illegal = 1'b1;
    ecall  = 1'b0;
    ebreak = 1'b0;
    mret = 1'b0;
    csr_en = 1'b0;
    csr_cmd = 3'b0;

    case (opcode)
        // I-type 算术指令，用到了立即数
        OPCODE_OP_IMM: begin
            imm_type = IMM_I;
            case (funct3)
                // ADDI
                3'b000: begin
                    reg_write   = 1'b1;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_ADD;
                    mem_read    = 1'b0;
                    mem_write   = 1'b0;
                    imm_type    = IMM_I;
                    illegal = 1'b0;
                end
                // SLTI：有符号比较寄存器和立即数
                3'b010: begin
                    reg_write   = 1'b1;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_SLT;
                    imm_type    = IMM_I;
                    illegal = 1'b0;
                end
                // SLTIU：立即数先符号扩展，再进行无符号比较
                3'b011: begin
                    reg_write   = 1'b1;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_SLTU;
                    imm_type    = IMM_I;
                    illegal = 1'b0;
                end
                // ANDI
                3'b111: begin
                    reg_write   = 1'b1;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_AND;
                    imm_type    = IMM_I;
                    illegal = 1'b0;
                end
                // ORI
                3'b110: begin
                    reg_write   = 1'b1;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_OR;
                    imm_type    = IMM_I;
                    illegal = 1'b0;
                end
                // XORI
                3'b100: begin
                    reg_write   = 1'b1;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_XOR;
                    imm_type    = IMM_I;
                    illegal = 1'b0;
                end
                // SLLI：立即数逻辑左移
                3'b001: begin
                    if (funct7 == 7'b0000000) begin
                        reg_write   = 1'b1;
                        alu_src_imm = 1'b1;
                        alu_op      = ALU_SLL;
                        imm_type    = IMM_I;
                        illegal = 1'b0;
                    end
                end
                // SRLI / SRAI：立即数右移
                3'b101: begin
                    case (funct7)
                        7'b0000000: begin
                            reg_write   = 1'b1;
                            alu_src_imm = 1'b1;
                            alu_op      = ALU_SRL;
                            imm_type    = IMM_I;
                            illegal = 1'b0;
                        end
                        7'b0100000: begin
                            reg_write   = 1'b1;
                            alu_src_imm = 1'b1;
                            alu_op      = ALU_SRA;
                            imm_type    = IMM_I;
                            illegal = 1'b0;
                        end
                        default: begin
                            reg_write = 1'b0;
                        end
                    endcase
                end
                default: begin
                    reg_write = 1'b0;
                end
            endcase
        end
        // R-type 算术指令，没用到立即数
        OPCODE_OP: begin
            case (funct3)
                3'b000: begin
                    case (funct7)
                        // ADD，两个数相加
                        7'b0000000: begin
                            reg_write   = 1'b1;
                            alu_src_imm = 1'b0;
                            alu_op      = ALU_ADD;
                            mem_read    = 1'b0;
                            mem_write   = 1'b0;
                            imm_type    = IMM_NONE;
                            illegal = 1'b0;
                        end
                        // SUB，两个数相减
                        7'b0100000: begin
                            reg_write   = 1'b1;
                            alu_src_imm = 1'b0;
                            alu_op      = ALU_SUB;
                            mem_read    = 1'b0;
                            mem_write   = 1'b0;
                            imm_type    = IMM_NONE;
                            illegal = 1'b0;
                        end
                        default: begin
                            reg_write = 1'b0;
                        end
                    endcase
                end
                // SLT：有符号比较两个寄存器
                3'b010: begin
                    if (funct7 == 7'b0000000) begin
                        reg_write   = 1'b1;
                        alu_src_imm = 1'b0;
                        alu_op      = ALU_SLT;
                        illegal = 1'b0;
                    end
                end
                // SLTU：无符号比较两个寄存器
                3'b011: begin
                    if (funct7 == 7'b0000000) begin
                        reg_write   = 1'b1;
                        alu_src_imm = 1'b0;
                        alu_op      = ALU_SLTU;
                        illegal = 1'b0;
                    end
                end
                //AND
                3'b111:begin
                    if(funct7==7'b0000000)begin
                        reg_write = 1'b1;
                        alu_src_imm = 1'b0;
                        alu_op = ALU_AND;
                        illegal = 1'b0;
                    end
                end
                // OR
                3'b110: begin
                    if (funct7 == 7'b0000000) begin
                        reg_write   = 1'b1;
                        alu_src_imm = 1'b0;
                        alu_op      = ALU_OR;
                        illegal = 1'b0;
                    end
                end
                // XOR
                3'b100: begin
                    if (funct7 == 7'b0000000) begin
                        reg_write   = 1'b1;
                        alu_src_imm = 1'b0;
                        alu_op      = ALU_XOR;
                        illegal = 1'b0;
                    end
                end
                // SLL：逻辑左移
                3'b001: begin
                    if (funct7 == 7'b0000000) begin
                        reg_write   = 1'b1;
                        alu_src_imm = 1'b0;
                        alu_op      = ALU_SLL;
                        illegal = 1'b0;
                    end
                end
                // SRL / SRA：右移
                3'b101: begin
                    case (funct7)
                        // SRL：左边补0
                        7'b0000000: begin
                        reg_write   = 1'b1;
                        alu_src_imm = 1'b0;
                        alu_op      = ALU_SRL;
                        illegal = 1'b0;
                    end
                        // SRA：左边补符号位
                        7'b0100000: begin
                        reg_write   = 1'b1;
                        alu_src_imm = 1'b0;
                        alu_op      = ALU_SRA;
                        illegal = 1'b0;
                    end
                        default: begin
                            reg_write = 1'b0;
                        end
                     endcase
                end
                default: begin
                    reg_write = 1'b0;
                end
            endcase
        end
        // LB/LH/LW/LBU/LHU：用 ALU 计算 rs1 + I-type immediate得内存地址，写回rd。几种load在decoder阶段产生的控制信号相同
        OPCODE_LOAD: begin
            imm_type = IMM_I;
            case (funct3)
                3'b000, // LB
                3'b001, // LH
                3'b010, // LW
                3'b100, // LBU
                3'b101: begin // LHU
                    reg_write   = 1'b0;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_ADD;
                    mem_read    = 1'b1;
                    mem_write   = 1'b0;
                    illegal = 1'b0;
                end
                default: begin
                    mem_read = 1'b0;
                end
            endcase
        end
        // SB/SH/SW：用 ALU 计算 rs1 + S-type immediate得内存地址，将rs2写过去。几种store在decoder阶段产生的控制信号相同
        OPCODE_STORE: begin
            imm_type = IMM_S;
            case (funct3)
                3'b000, // SB
                3'b001, // SH
                3'b010: begin // SW
                    reg_write   = 1'b0;
                    alu_src_imm = 1'b1;
                    alu_op      = ALU_ADD;
                    mem_read    = 1'b0;
                    mem_write   = 1'b1;
                    illegal = 1'b0;
                end
                default: begin
                    mem_write = 1'b0;
                end
            endcase
        end

        // B-type 条件分支立即数
        OPCODE_BRANCH: begin
            case (funct3)
                3'b000, // BEQ
                3'b001, // BNE
                3'b100, // BLT
                3'b101, // BGE
                3'b110, // BLTU
                3'b111: begin // BGEU
                    branch_en = 1'b1;
                    imm_type  = IMM_B;
                    illegal = 1'b0;
                end

                default: begin
                    branch_en = 1'b0;
                    imm_type  = IMM_NONE;
                end
            endcase 

        end

        // LUI/AUIPC 共用 U-type 立即数格式
        OPCODE_LUI:begin
            lui_en    = 1'b1;
            reg_write = 1'b1;
            imm_type  = IMM_U;
            illegal = 1'b0;
        end
        OPCODE_AUIPC: begin
            auipc_en  = 1'b1;
            reg_write = 1'b1;
            imm_type  = IMM_U;
            illegal = 1'b0;
        end

        // JAL 使用 J-type 立即数
        OPCODE_JAL: begin
            jal_en    = 1'b1;
            reg_write = 1'b1;
            imm_type = IMM_J;
            illegal = 1'b0;
        end

        // JALR 的目标偏移是 I-type
        OPCODE_JALR: begin
            if (funct3 == 3'b000) begin
                jalr_en   = 1'b1;
                reg_write = 1'b1;
                imm_type  = IMM_I;
                illegal = 1'b0;
            end
        end

        OPCODE_MISC_MEM: begin
            // RV32I FENCE。顺序流水线在前一笔访存完成前会暂停；此处无需额外副作用。
            // pred/succ、fm、rs1、rd 不改变本核的执行方式；FENCE.I 属于另一扩展。
            if (funct3 == 3'b000)
                illegal = 1'b0;
        end

        OPCODE_SYSTEM: begin
            case (instruction)
                32'h00000073: begin // ECALL
                ecall   = 1'b1;
                illegal = 1'b0;
                end
                32'h00100073: begin // EBREAK
                ebreak  = 1'b1;
                illegal = 1'b0;
                end
                32'h30200073: begin//MRET
                mret = 1'b1;
                illegal = 1'b0;
                end
                
        default: begin
                case (funct3)
                3'b001, // CSRRW 写入 CSR,用寄存器提供新值
                3'b010, // CSRRS 将指定的位设为 1，用寄存器提供新值
                3'b011, // CSRRC 将指定的位清为 0，用寄存器提供新值
                3'b101, // CSRRWI 写入 CSR,用指令中的立即数提供新值
                3'b110, // CSRRSI 将指定的位设为 1，用指令中的立即数提供新值
                3'b111: // CSRRCI 将指定的位清为 0，用指令中的立即数提供新值
                //这六条指令都可以把 CSR 的旧值写入目标通用寄存器
                begin 
                csr_en   = 1'b1;
                csr_cmd  = funct3;
                reg_write = 1'b1; // CSR 原值写入 rd
                illegal  = 1'b0;
        end
        default: begin
            // 保持 illegal = 1
        end
    endcase
        end
    endcase
end

        default: begin
            reg_write = 1'b0;
        end
    endcase
end

endmodule
