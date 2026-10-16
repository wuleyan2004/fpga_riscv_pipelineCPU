module cpu_core (
    input wire clk,//输入时钟信号
    input wire reset,//输入复位信号
    //Instruction ROM接口
    input wire[31:0] instruction,//输入指令
    output reg[31:0] pc,//输出pc

    output wire        mem_valid,
    output wire        mem_write,
    output wire [3:0]  mem_wstrb,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,

    input wire         mem_ready,
    input wire [31:0]  mem_rdata,

    // 调试信号：发现错位 Load/Store 时拉高一个周期
    output reg          debug_misaligned
);

//CPU状态
reg cpu_state;//在两个时钟上升沿之间保持不变，只在上升沿处根据条件更新
localparam CPU_RUN = 1'b0;
localparam CPU_MEM_WAIT = 1'b1;

//指令字段（RISBUJ适用）
//指令信号
wire[6:0] opcode;//操作码
wire[4:0] rd;//写寄存器的地址
wire[2:0] funct3;
wire[4:0] rs1;//读寄存器的地址1
wire[4:0] rs2;//读寄存器的地址2
wire[6:0] funct7;
//把输入的instruction拆成opcode,rd,funct3,rs1,rs2,funct7
assign opcode = instruction[6:0];
assign rd = instruction[11:7];
assign funct3 = instruction[14:12];
assign rs1 = instruction[19:15];
assign rs2 = instruction[24:20];
assign funct7 = instruction[31:25];

//imm_gen
wire[2:0] imm_type;
wire[31:0] imm;
imm_gen u_imm_gen(
    .instruction(instruction),
    .imm_type(imm_type),
    .imm(imm)
);

//regfile
wire[31:0] rs1_data;
wire[31:0] rs2_data;
wire rd_we;
wire[31:0] rd_data;
wire[4:0] regfile_rd_addr;
regfile u_regfile (
    .clk      (clk),

    .rs1_addr (rs1),
    .rs2_addr (rs2),
    .rs1_data (rs1_data),
    .rs2_data (rs2_data),

    .rd_addr  (regfile_rd_addr),
    .rd_data  (rd_data),
    .rd_we    (rd_we)
);

//decoder
wire       decoder_reg_write;
wire       alu_src_imm;
wire [3:0] alu_op;
wire       decoder_mem_read;
wire       decoder_mem_write;
wire decoder_branch_en;
wire decoder_jal_en;
wire decoder_jalr_en;
wire decoder_lui_en;
wire decoder_auipc_en;
decoder u_decoder (
    .opcode      (opcode),
    .funct3      (funct3),
    .funct7      (funct7),
    .reg_write   (decoder_reg_write),
    .alu_src_imm (alu_src_imm),
    .alu_op      (alu_op),
    .mem_read    (decoder_mem_read),
    .mem_write   (decoder_mem_write),
    .imm_type(imm_type),
    .branch_en(decoder_branch_en),
    .jal_en (decoder_jal_en),
    .jalr_en (decoder_jalr_en),
    .lui_en(decoder_lui_en),
    .auipc_en(decoder_auipc_en)
);

//alu
wire[31:0] alu_a;
wire[31:0] alu_b;
wire[31:0] alu_result;
assign alu_a = rs1_data;
assign alu_b = alu_src_imm ? imm : rs2_data;
alu u_alu (
    .a      (alu_a),
    .b      (alu_b),
    .op     (alu_op),
    .result (alu_result)
);

//branch_compare
wire branch_equal;
wire branch_signed_less;
wire branch_unsigned_less;
branch_compare u_branch_compare (
    .rs1_data      (rs1_data),
    .rs2_data      (rs2_data),

    .equal         (branch_equal),
    .signed_less   (branch_signed_less),
    .unsigned_less (branch_unsigned_less)
);

// 分支指令：BEQ、BNE、BLT、BGE、BLTU、BGEU
reg branch_taken;//是否跳转
always @(*) begin
    // 默认不跳转
    branch_taken = 1'b0;
    if (decoder_branch_en) begin
        case (funct3)
            // BEQ：相等就跳转
            3'b000: branch_taken = branch_equal;
            // BNE：不相等就跳转
            3'b001: branch_taken = !branch_equal;
            // BLT：有符号 rs1 < rs2 就跳转
            3'b100: branch_taken = branch_signed_less;
            // BGE：有符号 rs1 >= rs2 就跳转
            3'b101: branch_taken = !branch_signed_less;
            // BLTU：无符号 rs1 < rs2 就跳转
            3'b110: branch_taken = branch_unsigned_less;
            // BGEU：无符号 rs1 >= rs2 就跳转
            3'b111: branch_taken = !branch_unsigned_less;
            default: branch_taken = 1'b0;
        endcase
    end
end

wire [31:0] branch_target;
assign branch_target = pc + imm;

// 跳转指令：JAL、JALR（pc_plus_4 也用于顺序执行）
wire[31:0] jalr_sum;
wire[31:0] jalr_target;

assign jalr_sum = rs1_data+imm;
assign jalr_target = {jalr_sum[31:1],1'b0};

wire [31:0] pc_plus_4;
wire [31:0] jal_target;

assign pc_plus_4  = pc + 32'd4;
assign jal_target = pc + imm;

wire jump_link_en;
assign jump_link_en =
    decoder_jal_en || decoder_jalr_en;

// 高位立即数指令：LUI、AUIPC
wire [31:0] auipc_result;

assign auipc_result = pc + imm;

// 加载指令：LB、LH、LW、LBU、LHU
reg       pending_load_q;
reg [4:0] load_rd_addr_q;
reg [2:0] load_funct3_q;
reg [1:0] load_addr_low_q;

reg [7:0]  load_byte;
reg [15:0] load_half;
reg [31:0] load_data;

// Byte Load 可以使用任意地址；Halfword 需2字节对齐；Word 需4字节对齐。
reg load_address_aligned;//用于判断Load访问的地址是否满足对齐要求，1满足，0不满足
always @(*) begin
    if ((funct3 == 3'b000) || (funct3 == 3'b100))//字节访问只读取一个字节
        load_address_aligned = 1'b1;//永远认为对齐
    else if ((funct3 == 3'b001) || (funct3 == 3'b101))//半字访问读取2个字节
        load_address_aligned = (alu_result[0] == 1'b0);
    else if (funct3 == 3'b010)//读取四个字节
        load_address_aligned = (alu_result[1:0] == 2'b00);
    else
        load_address_aligned = 1'b0;
end

always @(*) begin
    case (load_addr_low_q)
        2'b00: load_byte = mem_rdata[7:0];
        2'b01: load_byte = mem_rdata[15:8];
        2'b10: load_byte = mem_rdata[23:16];
        2'b11: load_byte = mem_rdata[31:24];
    endcase

    load_half = load_addr_low_q[1]
              ? mem_rdata[31:16]
              : mem_rdata[15:0];

    case (load_funct3_q)
        3'b000: load_data = {{24{load_byte[7]}}, load_byte}; // LB
        3'b001: load_data = {{16{load_half[15]}}, load_half}; // LH
        3'b010: load_data = mem_rdata;                         // LW
        3'b100: load_data = {24'b0, load_byte};                // LBU
        3'b101: load_data = {16'b0, load_half};                // LHU
        default: load_data = 32'b0;
    endcase
end

wire load_rd_we;
// Load 只在 RAM 返回 ready 的这一拍写回一次
assign load_rd_we =
    !reset
    && (cpu_state == CPU_MEM_WAIT)
    && mem_ready
    && pending_load_q;

// 存储指令：SB、SH、SW
// funct3 决定写入大小，地址低两位决定写哪几个字节
reg [3:0]  store_wstrb;
//写入内存的数据
reg [31:0] store_wdata;

always @(*) begin
    //默认一个字节都不写入
    store_wstrb = 4'b0000;
    //默认写入0
    store_wdata = 32'b0;
    case (funct3)
        3'b000: begin // SB，向内存写一个字节
            case (alu_result[1:0])
                //写入第一个字节
                2'b00: begin
                    store_wstrb = 4'b0001;
                    store_wdata = {24'b0, rs2_data[7:0]};
                end
                //写入第二个字节
                2'b01: begin
                    store_wstrb = 4'b0010;
                    store_wdata = {16'b0, rs2_data[7:0], 8'b0};
                end
                //写入第三个字节
                2'b10: begin
                    store_wstrb = 4'b0100;
                    store_wdata = {8'b0, rs2_data[7:0], 16'b0};
                end
                //写入第四个字节
                2'b11: begin
                    store_wstrb = 4'b1000;
                    store_wdata = {rs2_data[7:0], 24'b0};
                end
            endcase
        end
        3'b001: begin // SH，写两个字节
            case (alu_result[1:0])
                //写入第一第二个字节
                2'b00: begin
                    store_wstrb = 4'b0011;
                    store_wdata = {16'b0, rs2_data[15:0]};
                end
                //写入第三第四个字节
                2'b10: begin
                    store_wstrb = 4'b1100;
                    store_wdata = {rs2_data[15:0], 16'b0};
                end
                default: begin
                    store_wstrb = 4'b0000;
                    store_wdata = 32'b0;
                end
            endcase
        end
        3'b010: begin // SW，写整个word
            if (alu_result[1:0] == 2'b00) begin
                store_wstrb = 4'b1111;
                store_wdata = rs2_data;
            end
        end
        default: begin
            store_wstrb = 4'b0000;
            store_wdata = 32'b0;
        end
    endcase
end

// Byte Store 无对齐限制；Halfword 需2字节对齐；Word 需4字节对齐。
wire store_address_aligned;
assign store_address_aligned =
    (funct3 == 3'b000) ? 1'b1 :
    (funct3 == 3'b001) ? (alu_result[0] == 1'b0) :
    (funct3 == 3'b010) ? (alu_result[1:0] == 2'b00) :
    1'b0;

// Load / Store 共用的地址错位检测和访存请求
wire memory_access_misaligned;
assign memory_access_misaligned =
    (decoder_mem_read  && !load_address_aligned) ||
    (decoder_mem_write && !store_address_aligned);

reg        mem_write_q;
reg [3:0]  mem_wstrb_q;
reg [31:0] mem_addr_q;
reg [31:0] mem_wdata_q;

// 等待状态中向 Data RAM 发出请求
assign mem_valid = (cpu_state == CPU_MEM_WAIT);

assign mem_write = mem_write_q;
assign mem_wstrb = mem_wstrb_q;
assign mem_addr  = mem_addr_q;
assign mem_wdata = mem_wdata_q;

wire start_mem;

assign start_mem = decoder_mem_read || decoder_mem_write;

// 寄存器写回：R/I 型算术、JAL/JALR、LUI/AUIPC、Load
wire normal_rd_we;
// R/I 型算术、JAL/JALR、LUI/AUIPC 在 RUN 状态直接写回
assign normal_rd_we =
    !reset
    && (cpu_state == CPU_RUN)
    && decoder_reg_write;

assign rd_we           = normal_rd_we || load_rd_we;
assign rd_data =
    load_rd_we        ? load_data :
    jump_link_en      ? pc_plus_4 :
    decoder_lui_en    ? imm :
    decoder_auipc_en  ? auipc_result :
                        alu_result;
assign regfile_rd_addr = load_rd_we ? load_rd_addr_q : rd;

//10.PC和状态控制

always @(posedge clk) begin
    if (reset) begin
        pc           <= 32'h0000_0000;
        cpu_state    <= CPU_RUN;

        mem_write_q  <= 1'b0;
        mem_wstrb_q  <= 4'b0000;
        mem_addr_q   <= 32'b0;
        mem_wdata_q  <= 32'b0;
        pending_load_q <= 1'b0;
        load_rd_addr_q <= 5'b0;
        load_funct3_q  <= 3'b0;
        load_addr_low_q <= 2'b0;
        debug_misaligned <= 1'b0;
    end
    else begin
        // 默认拉低；只在发现错位请求后保持一个周期的高电平。
        debug_misaligned <= 1'b0;
        case(cpu_state)
            CPU_RUN:begin
                if(start_mem)begin
                    // 在离开 RUN 前锁存整个访存请求；
                    // 等待 mem_ready 期间这些信号保持不变。
                    mem_write_q    <= decoder_mem_write;
                    mem_wstrb_q    <= decoder_mem_write ? store_wstrb : 4'b0000;
                    mem_addr_q     <= alu_result;
                    mem_wdata_q    <= decoder_mem_write ? store_wdata : 32'b0;
                    pending_load_q <= decoder_mem_read && load_address_aligned;
                    load_rd_addr_q <= rd;
                    load_funct3_q  <= funct3;
                    load_addr_low_q <= alu_result[1:0];
                    debug_misaligned <= memory_access_misaligned;

                    // 此处不更新 PC，当前 LW/SW 会保持到请求完成。
                    cpu_state <= CPU_MEM_WAIT;
                end
                else if (decoder_jal_en) begin
                    pc <= jal_target;
                end
                else if (decoder_jalr_en) begin
                    pc <= jalr_target;
                end
                else if (decoder_branch_en) begin
                    if (branch_taken) begin
                        pc <= branch_target;
                    end
                    else begin
                        pc <= pc_plus_4;
                    end
                end
                else begin
                    // ADDI、ADD、SUB 正常完成
                    pc <= pc_plus_4;
                end
            end
            CPU_MEM_WAIT: begin
                // 等待期间 PC 不变化

                if (mem_ready) begin
                    // LW 的写回在本时钟沿由 load_rd_we/rd_data 完成；
                    // SW 不产生寄存器写回。

                    pc             <= pc + 32'd4;
                    cpu_state      <= CPU_RUN;
                    pending_load_q <= 1'b0;
                    mem_write_q    <= 1'b0;
                    mem_wstrb_q    <= 4'b0000;
                end
            end
            default: begin
                pc             <= 32'h0000_0000;
                cpu_state      <= CPU_RUN;
                mem_write_q    <= 1'b0;
                mem_wstrb_q    <= 4'b0000;
                mem_addr_q     <= 32'b0;
                mem_wdata_q    <= 32'b0;
                pending_load_q <= 1'b0;
                load_rd_addr_q <= 5'b0;
                load_funct3_q  <= 3'b0;
                load_addr_low_q <= 2'b0;
            end
        endcase
    end
end

endmodule
