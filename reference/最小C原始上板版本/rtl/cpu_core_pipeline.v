module cpu_core_pipeline (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] instruction,
    output reg  [31:0] pc,

    output wire        mem_valid,
    output wire        mem_write,
    output wire [3:0]  mem_wstrb,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    input  wire        mem_ready,
    input  wire [31:0] mem_rdata,
    output reg         debug_misaligned
);

//if_ex寄存器
reg        if_ex_valid_q;
reg [31:0] if_ex_pc_q;
reg [31:0] if_ex_instruction_q;
//ex_wb寄存器
reg        ex_wb_valid_q;
reg [31:0] ex_wb_pc_q;
reg [31:0] ex_wb_instruction_q;
reg [4:0]  ex_wb_rd_q;
reg        ex_wb_reg_write_q;
reg [31:0] ex_wb_result_q;
reg        ex_wb_mem_access_q;
reg        ex_wb_mem_read_q;
reg        ex_wb_mem_write_q;
reg [31:0] ex_wb_mem_addr_q;
reg [31:0] ex_wb_mem_wdata_q;
reg [3:0]  ex_wb_mem_wstrb_q;
reg [2:0]  ex_wb_mem_funct3_q;
reg [1:0]  ex_wb_mem_addr_low_q;
reg        ex_wb_load_aligned_q;
//从EX级正在处理的32位指令中，按固定bit位置切出常用字段，供后续译码器、寄存器堆等模块使用
wire [6:0] ex_opcode = if_ex_instruction_q[6:0];
wire [4:0] ex_rd     = if_ex_instruction_q[11:7];
wire [2:0] ex_funct3 = if_ex_instruction_q[14:12];
wire [4:0] ex_rs1    = if_ex_instruction_q[19:15];
wire [4:0] ex_rs2    = if_ex_instruction_q[24:20];
wire [6:0] ex_funct7 = if_ex_instruction_q[31:25];
//decoder输出信号
wire       ex_decoder_reg_write;
wire       ex_alu_src_imm;
wire [3:0] ex_alu_op;
wire [2:0] ex_imm_type;
wire       ex_branch_en;
wire       ex_jal_en;
wire       ex_jalr_en;
wire       ex_lui_en;
wire       ex_auipc_en;
wire       ex_mem_read;
wire       ex_mem_write;
//imm_gen输出信号
wire [31:0] ex_imm;
//regfile输出信号
wire [31:0] ex_rs1_data;
wire [31:0] ex_rs2_data;
// 前递选择后的操作数，供 EX 级所有使用源寄存器的位置使用。
wire [31:0] ex_rs1_value;
wire [31:0] ex_rs2_value;
//alu输出信号
wire [31:0] ex_alu_result;
wire [31:0] ex_wb_writeback_data;
//branch_compare输出信号
wire        ex_branch_equal;
wire        ex_branch_signed_less;
wire        ex_branch_unsigned_less;
//decoder
decoder u_decoder (
    .opcode(ex_opcode),
    .funct3(ex_funct3),
    .funct7(ex_funct7),
    .reg_write(ex_decoder_reg_write),
    .alu_src_imm(ex_alu_src_imm),
    .alu_op(ex_alu_op),
    .mem_read(ex_mem_read),
    .mem_write(ex_mem_write),
    .imm_type(ex_imm_type),
    .branch_en(ex_branch_en),
    .jal_en(ex_jal_en),
    .jalr_en(ex_jalr_en),
    .lui_en(ex_lui_en),
    .auipc_en(ex_auipc_en)
);
//imm_gen
imm_gen u_imm_gen (
    .instruction(if_ex_instruction_q),
    .imm_type(ex_imm_type),
    .imm(ex_imm)
);
//regfile
regfile u_regfile (
    .clk(clk),
    .rs1_addr(ex_rs1),
    .rs2_addr(ex_rs2),
    .rs1_data(ex_rs1_data),
    .rs2_data(ex_rs2_data),
    .rd_addr(ex_wb_rd_q),
    .rd_data(ex_wb_writeback_data),
    .rd_we(!reset && ex_wb_valid_q && ex_wb_reg_write_q &&
           (!ex_wb_mem_read_q ||
            (mem_ready && ex_wb_load_aligned_q)))
);
//alu
alu u_alu (
    .a(ex_rs1_value),
    .b(ex_alu_src_imm ? ex_imm : ex_rs2_value),
    .op(ex_alu_op),
    .result(ex_alu_result)
);
//branch_compare
branch_compare u_branch_compare (
    .rs1_data(ex_rs1_value),
    .rs2_data(ex_rs2_value),
    .equal(ex_branch_equal),
    .signed_less(ex_branch_signed_less),
    .unsigned_less(ex_branch_unsigned_less)
);

//用于判断EX级当前指令是不是寄存器算术或立即数算术指令
wire ex_arithmetic = (ex_opcode == 7'b0010011)||(ex_opcode == 7'b0110011);
//用于判断EX级当前指令是不是合法的分支指令                                      
wire ex_branch = if_ex_valid_q && ex_branch_en;
//用于判断EX级当前指令是否涉及到内存
wire ex_mem_access = if_ex_valid_q && (ex_mem_read || ex_mem_write);
//用来判断EX级当前的 Load/Store 地址是否满足数据宽度要求的对齐
reg ex_mem_aligned;
always @(*) begin
    if (ex_mem_read) begin
        case (ex_funct3)
            3'b000, 3'b100: ex_mem_aligned = 1'b1; // LB/LBU
            3'b001, 3'b101: ex_mem_aligned = !ex_alu_result[0]; // LH/LHU
            3'b010: ex_mem_aligned = (ex_alu_result[1:0] == 2'b00); // LW
            default: ex_mem_aligned = 1'b0;
        endcase
    end else if (ex_mem_write) begin
        case (ex_funct3)
            3'b000: ex_mem_aligned = 1'b1; // SB
            3'b001: ex_mem_aligned = !ex_alu_result[0]; // SH
            3'b010: ex_mem_aligned = (ex_alu_result[1:0] == 2'b00); // SW
            default: ex_mem_aligned = 1'b0;
        endcase
    end else begin
        ex_mem_aligned = 1'b1;
    end
end
//STORE
//分别保存 Store 请求的字节写掩码和写入数据
reg [3:0] ex_store_wstrb;
reg [31:0] ex_store_wdata;
always @(*) begin
    ex_store_wstrb = 4'b0000;
    ex_store_wdata = 32'b0;
    case (ex_funct3)
        3'b000: begin // SB
            case (ex_alu_result[1:0])
                2'b00: begin ex_store_wstrb = 4'b0001; ex_store_wdata = {24'b0, ex_rs2_value[7:0]}; end
                2'b01: begin ex_store_wstrb = 4'b0010; ex_store_wdata = {16'b0, ex_rs2_value[7:0], 8'b0}; end
                2'b10: begin ex_store_wstrb = 4'b0100; ex_store_wdata = {8'b0, ex_rs2_value[7:0], 16'b0}; end
                2'b11: begin ex_store_wstrb = 4'b1000; ex_store_wdata = {ex_rs2_value[7:0], 24'b0}; end
            endcase
        end
        3'b001: begin // SH
            case (ex_alu_result[1:0])
                2'b00: begin ex_store_wstrb = 4'b0011; ex_store_wdata = {16'b0, ex_rs2_value[15:0]}; end
                2'b10: begin ex_store_wstrb = 4'b1100; ex_store_wdata = {ex_rs2_value[15:0], 16'b0}; end
                default: begin ex_store_wstrb = 4'b0000; ex_store_wdata = 32'b0; end
            endcase
        end
        3'b010: begin // SW
            if (ex_alu_result[1:0] == 2'b00) begin
                ex_store_wstrb = 4'b1111;
                ex_store_wdata = ex_rs2_value;
            end
        end
        default: begin
            ex_store_wstrb = 4'b0000;
            ex_store_wdata = 32'b0;
        end
    endcase
end
//LOAD
//这三个信号用于 WB 阶段处理 Load 返回的数据
reg [7:0] ex_wb_load_byte;
reg [15:0] ex_wb_load_half;
reg [31:0] ex_wb_load_result;
always @(*) begin
    case (ex_wb_mem_addr_low_q)
        2'b00: ex_wb_load_byte = mem_rdata[7:0];
        2'b01: ex_wb_load_byte = mem_rdata[15:8];
        2'b10: ex_wb_load_byte = mem_rdata[23:16];
        2'b11: ex_wb_load_byte = mem_rdata[31:24];
        default: ex_wb_load_byte = 8'b0;
    endcase

    ex_wb_load_half = ex_wb_mem_addr_low_q[1] ? mem_rdata[31:16]
                                               : mem_rdata[15:0];
    case (ex_wb_mem_funct3_q)
        3'b000: ex_wb_load_result = {{24{ex_wb_load_byte[7]}}, ex_wb_load_byte}; // LB
        3'b001: ex_wb_load_result = {{16{ex_wb_load_half[15]}}, ex_wb_load_half}; // LH
        3'b010: ex_wb_load_result = mem_rdata; // LW
        3'b100: ex_wb_load_result = {24'b0, ex_wb_load_byte}; // LBU
        3'b101: ex_wb_load_result = {16'b0, ex_wb_load_half}; // LHU
        default: ex_wb_load_result = 32'b0;
    endcase
end
//写回数据选择器：决定EX/WB阶段要送给寄存器堆的值是哪一个
assign ex_wb_writeback_data = ex_wb_mem_read_q ?ex_wb_load_result : ex_wb_result_q;
//表示 EX 级当前这条分支指令的比较条件是否成立
reg ex_branch_condition;
always @(*) begin
    ex_branch_condition = 1'b0;
    if (ex_branch) begin
        case (ex_funct3)
            3'b000: ex_branch_condition =  ex_branch_equal;          // BEQ
            3'b001: ex_branch_condition = !ex_branch_equal;          // BNE
            3'b100: ex_branch_condition =  ex_branch_signed_less;    // BLT
            3'b101: ex_branch_condition = !ex_branch_signed_less;    // BGE
            3'b110: ex_branch_condition =  ex_branch_unsigned_less;  // BLTU
            3'b111: ex_branch_condition = !ex_branch_unsigned_less;  // BGEU
            default: ex_branch_condition = 1'b0;
        endcase
    end
end

wire [31:0] ex_branch_target = if_ex_pc_q + ex_imm;
wire        ex_jal  = if_ex_valid_q && ex_jal_en;
wire        ex_jalr = if_ex_valid_q && ex_jalr_en;
wire [31:0] ex_jal_target = if_ex_pc_q + ex_imm;
wire [31:0] ex_jalr_sum = ex_rs1_value + ex_imm;
wire [31:0] ex_jalr_target = {ex_jalr_sum[31:1], 1'b0};
//表示EX 级当前这条指令是否要改变取指方向
wire        ex_control_redirect = ex_jal || ex_jalr ||
                                  (ex_branch && ex_branch_condition);
wire [31:0] ex_redirect_target = ex_jalr ? ex_jalr_target :
                                 ex_jal  ? ex_jal_target  :
                                           ex_branch_target;
wire [31:0] ex_jump_link = if_ex_pc_q + 32'd4;
// LUI 直接使用 U 型立即数；AUIPC 使用当前 EX 指令自己的 PC。
wire [31:0] ex_result = (ex_jal || ex_jalr) ? ex_jump_link :
                        ex_lui_en ? ex_imm :
                        ex_auipc_en ? (if_ex_pc_q + ex_imm) :
                                      ex_alu_result;

// LUI/AUIPC 的 [19:15]、[24:20] 属于立即数，不是源寄存器。
wire ex_uses_rs1 = ex_arithmetic || ex_branch || ex_jalr || ex_mem_access;
wire ex_uses_rs2 = (ex_opcode == 7'b0110011) || ex_branch || ex_mem_write;
// WB -> EX 前递：Load 必须等响应返回且对齐，x0 永不前递。
wire wb_forward_valid = !reset && ex_wb_valid_q &&
                        ex_wb_reg_write_q && (ex_wb_rd_q != 5'd0) &&
                        (!ex_wb_mem_read_q ||
                         (mem_ready && ex_wb_load_aligned_q));
wire forward_rs1 = if_ex_valid_q && ex_uses_rs1 && wb_forward_valid &&
                   (ex_rs1 == ex_wb_rd_q);
wire forward_rs2 = if_ex_valid_q && ex_uses_rs2 && wb_forward_valid &&
                   (ex_rs2 == ex_wb_rd_q);
assign ex_rs1_value = forward_rs1 ? ex_wb_writeback_data : ex_rs1_data;
assign ex_rs2_value = forward_rs2 ? ex_wb_writeback_data : ex_rs2_data;

// 有数据依赖且结果还不能前递时才暂停；访存等待优先保持整条流水线。
wire stall_raw = if_ex_valid_q && ex_wb_valid_q &&
                 ex_wb_reg_write_q && (ex_wb_rd_q != 5'd0) &&
                 !wb_forward_valid &&
                 ((ex_uses_rs1 && (ex_rs1 == ex_wb_rd_q)) ||
                  (ex_uses_rs2 && (ex_rs2 == ex_wb_rd_q)));
wire stall_mem = ex_wb_mem_access_q && !mem_ready;

always @(posedge clk) begin
    if (reset) begin
        pc                    <= 32'b0;
        debug_misaligned      <= 1'b0;
        if_ex_valid_q         <= 1'b0;
        if_ex_pc_q            <= 32'b0;
        if_ex_instruction_q   <= 32'b0;
        ex_wb_valid_q         <= 1'b0;
        ex_wb_pc_q            <= 32'b0;
        ex_wb_instruction_q   <= 32'b0;
        ex_wb_rd_q            <= 5'b0;
        ex_wb_reg_write_q     <= 1'b0;
        ex_wb_result_q        <= 32'b0;
        ex_wb_mem_access_q    <= 1'b0;
        ex_wb_mem_read_q      <= 1'b0;
        ex_wb_mem_write_q     <= 1'b0;
        ex_wb_mem_addr_q      <= 32'b0;
        ex_wb_mem_wdata_q     <= 32'b0;
        ex_wb_mem_wstrb_q     <= 4'b0;
        ex_wb_mem_funct3_q    <= 3'b0;
        ex_wb_mem_addr_low_q  <= 2'b0;
        ex_wb_load_aligned_q  <= 1'b0;
    end else if (stall_mem) begin
        debug_misaligned <= 1'b0;
    end else if (stall_raw) begin
        debug_misaligned  <= 1'b0;
        ex_wb_valid_q     <= 1'b0;
        ex_wb_reg_write_q <= 1'b0;
        ex_wb_mem_access_q <= 1'b0;
        ex_wb_mem_read_q   <= 1'b0;
        ex_wb_mem_write_q  <= 1'b0;
        ex_wb_mem_wstrb_q  <= 4'b0;
    end else if (ex_control_redirect) begin
        debug_misaligned      <= 1'b0;
        pc                    <= ex_redirect_target;
        if_ex_valid_q         <= 1'b0;
        ex_wb_valid_q         <= if_ex_valid_q;
        ex_wb_pc_q            <= if_ex_pc_q;
        ex_wb_instruction_q   <= if_ex_instruction_q;
        ex_wb_rd_q            <= ex_rd;
        ex_wb_reg_write_q     <= ex_jal || ex_jalr;
        ex_wb_result_q        <= ex_result;
        ex_wb_mem_access_q    <= 1'b0;
        ex_wb_mem_read_q      <= 1'b0;
        ex_wb_mem_write_q     <= 1'b0;
        ex_wb_mem_addr_q      <= 32'b0;
        ex_wb_mem_wdata_q     <= 32'b0;
        ex_wb_mem_wstrb_q     <= 4'b0;
        ex_wb_mem_funct3_q    <= 3'b0;
        ex_wb_mem_addr_low_q  <= 2'b0;
        ex_wb_load_aligned_q  <= 1'b0;
    end else begin
        debug_misaligned      <= ex_mem_access && !ex_mem_aligned;
        pc                  <= pc + 32'd4;
        if_ex_valid_q       <= 1'b1;
        if_ex_pc_q          <= pc;
        if_ex_instruction_q <= instruction;
        ex_wb_valid_q       <= if_ex_valid_q;
        ex_wb_pc_q          <= if_ex_pc_q;
        ex_wb_instruction_q <= if_ex_instruction_q;
        ex_wb_rd_q          <= ex_rd;
        ex_wb_reg_write_q   <= if_ex_valid_q &&
                               ((ex_arithmetic && ex_decoder_reg_write) ||
                                ex_jal || ex_jalr ||
                                ex_lui_en || ex_auipc_en ||
                                (ex_mem_read && ex_mem_aligned));
        ex_wb_result_q      <= ex_result;
        ex_wb_mem_access_q   <= ex_mem_access;
        ex_wb_mem_read_q     <= ex_mem_access && ex_mem_read;
        ex_wb_mem_write_q    <= ex_mem_access && ex_mem_write;
        ex_wb_mem_addr_q     <= ex_alu_result;
        ex_wb_mem_wdata_q    <= ex_mem_write ? ex_store_wdata : 32'b0;
        ex_wb_mem_wstrb_q    <= (ex_mem_write && ex_mem_aligned) ?
                                ex_store_wstrb : 4'b0;
        ex_wb_mem_funct3_q   <= ex_funct3;
        ex_wb_mem_addr_low_q <= ex_alu_result[1:0];
        ex_wb_load_aligned_q <= ex_mem_aligned;
    end
end

assign mem_valid = !reset && ex_wb_valid_q && ex_wb_mem_access_q;
assign mem_write = mem_valid && ex_wb_mem_write_q;
assign mem_wstrb = mem_valid ? ex_wb_mem_wstrb_q : 4'b0;
assign mem_addr  = mem_valid ? ex_wb_mem_addr_q : 32'b0;
assign mem_wdata = mem_valid ? ex_wb_mem_wdata_q : 32'b0;

endmodule
