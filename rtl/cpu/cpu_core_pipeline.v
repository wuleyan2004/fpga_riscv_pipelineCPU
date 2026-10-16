module cpu_core_pipeline #(
    parameter integer RAM_BYTES = 1024//RAM的容量，表示有1024个字节
) (
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
    output reg         debug_misaligned,//表示CPU检测到一次Load/Store地址错位
    output wire        profile_retire,
    output wire        profile_mem_wait,
    output wire        profile_raw_wait,
    output wire        profile_branch,
    output wire        profile_branch_taken,
    output wire        profile_jump
);
//IF-EX级间寄存器
reg        if_ex_valid_q;//这条指令是否有效
reg [31:0] if_ex_pc_q;//这条指令的pc
reg [31:0] if_ex_instruction_q;//取到的32位指令
//EX-WB级间寄存器
reg        ex_wb_valid_q;//WB级当前指令是否有效
reg [31:0] ex_wb_pc_q;//当前指令的pc
reg [31:0] ex_wb_instruction_q;//当前指令的原始编码
reg [4:0]  ex_wb_rd_q;//目的寄存器地址
reg        ex_wb_reg_write_q;//是否写回目的寄存器
reg [31:0] ex_wb_result_q;//非Load指令要写回的结果
reg        ex_wb_mem_access_q;//是否为Load或者Store
reg        ex_wb_mem_read_q;//读ram
reg        ex_wb_mem_write_q;//写ram
reg [31:0] ex_wb_mem_addr_q;//访存地址
reg [31:0] ex_wb_mem_wdata_q;//Store数据
reg [3:0]  ex_wb_mem_wstrb_q;//Stor数据字节写使能
reg [2:0]  ex_wb_mem_funct3_q;//Load类型
reg [1:0]  ex_wb_mem_addr_low_q;//访存地址的低两位
reg        ex_wb_load_aligned_q;//是否对齐
reg        ex_wb_mem_recover_q;//这次未对齐访存是否通过拆分访问来完成
reg        ex_wb_mem_two_beats_q;//是否需要跨两个 32 位字、发起两笔请求
reg        ex_wb_mem_second_q;//当前是否正在处理第二笔请求
reg [31:0] ex_wb_first_rdata_q;//暂存第一笔 Load 返回的数据，供第二笔返回后拼接
reg [31:0] ex_wb_second_wdata_q;//第二笔 Store 的数据
reg [3:0]  ex_wb_second_wstrb_q;//第二笔 Store 字节写使能
wire       wb_mem_done;//访存是否真正完成
//记录异常现场的寄存器，主要用于内部观察
reg        trap_valid_q;//表示曾发生异常
reg [31:0] trap_pc_q;//出异常的指令地址
reg [31:0] trap_instruction_q;//出异常的指令编码
reg [31:0] trap_cause_q;//记录异常原因码
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
wire       ex_decode_illegal;
wire       ex_ecall;
wire       ex_ebreak;
wire       ex_mret;
wire       ex_csr_en;
//imm_gen输出信号
wire [31:0] ex_imm;
//regfile输出信号
wire [31:0] ex_rs1_data;
wire [31:0] ex_rs2_data;
//regfile输入信号
wire [31:0] ex_wb_writeback_data;
// ex级从regfile rs1和rs2读出的数据
wire [31:0] ex_rs1_value;
wire [31:0] ex_rs2_value;
//alu输出信号
wire [31:0] ex_alu_result;
//branch_compare输出信号
wire        ex_branch_equal;
wire        ex_branch_signed_less;
wire        ex_branch_unsigned_less;
//csr_file相关信号
wire        csr_exec;
wire [11:0] ex_csr_addr = if_ex_instruction_q[31:20];
wire [2:0] ex_csr_cmd;
wire [31:0] ex_csr_rdata;
wire       ex_csr_supported;
wire        csr_trap_valid;
wire [31:0] csr_trap_cause;
wire [31:0] csr_trap_value;
wire        csr_mret_exec;
wire [31:0] csr_mtvec;
wire [31:0] csr_mepc;
assign ex_illegal = ex_decode_illegal || (ex_csr_en && !ex_csr_supported);
//decoder
decoder u_decoder (
    //输入
    .instruction(if_ex_instruction_q), 
    .opcode(ex_opcode),
    .funct3(ex_funct3),
    .funct7(ex_funct7),
    //输出
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
    .auipc_en(ex_auipc_en),
    .illegal(ex_decode_illegal),
    .ecall(ex_ecall),
    .ebreak(ex_ebreak),
    .mret(ex_mret),
    .csr_en(ex_csr_en),
    .csr_cmd(ex_csr_cmd)
);
//imm_gen
imm_gen u_imm_gen (
    //输入
    .instruction(if_ex_instruction_q),
    .imm_type(ex_imm_type),
    //输出
    .imm(ex_imm)
);
//regfile
regfile u_regfile (
    //输入
    .clk(clk),
    .rs1_addr(ex_rs1),
    .rs2_addr(ex_rs2),
    //输出
    .rs1_data(ex_rs1_data),
    .rs2_data(ex_rs2_data),
    //输入
    .rd_addr(ex_wb_rd_q),
    .rd_data(ex_wb_writeback_data),
    .rd_we(!reset && ex_wb_valid_q && ex_wb_reg_write_q &&
           (!ex_wb_mem_read_q ||
            wb_mem_done))
);
//alu
alu u_alu (
    //输入
    .a(ex_rs1_value),
    .b(ex_alu_src_imm ? ex_imm : ex_rs2_value),
    .op(ex_alu_op),
    //输出
    .result(ex_alu_result)
);
//branch_compare
branch_compare u_branch_compare (
    //输入
    .rs1_data(ex_rs1_value),
    .rs2_data(ex_rs2_value),
    //输出
    .equal(ex_branch_equal),
    .signed_less(ex_branch_signed_less),
    .unsigned_less(ex_branch_unsigned_less)
);
//csr_file
csr_file u_csr_file (
    .clk(clk), 
    .reset(reset),
    .csr_exec_i(csr_exec), 
    .csr_addr_i(ex_csr_addr), 
    .csr_cmd_i(ex_csr_cmd),
    .rs1_field_i(ex_rs1), 
    .rs1_data_i(ex_rs1_value),
    .csr_rdata_o(ex_csr_rdata), 
    .csr_supported_o(ex_csr_supported),
    .trap_valid_i(csr_trap_valid), 
    .trap_pc_i(if_ex_pc_q),
    .trap_cause_i(csr_trap_cause), 
    .trap_value_i(csr_trap_value),
    .mret_valid_i(csr_mret_exec), 
    .mtvec_o(csr_mtvec), 
    .mepc_o(csr_mepc)
);

//用于判断EX级当前指令是不是寄存器算术或立即数算术指令
wire ex_arithmetic = (ex_opcode == 7'b0010011)||(ex_opcode == 7'b0110011);
//用于判断EX级当前指令是不是合法的分支指令，是有效指令同时译码出branch有效                                   
wire ex_branch = if_ex_valid_q && ex_branch_en;
//用于判断EX级当前指令是否涉及到内存
wire ex_mem_access = if_ex_valid_q && (ex_mem_read || ex_mem_write);
//用来判断EX级当前的 Load/Store 地址是否满足数据宽度要求的对齐
reg ex_mem_aligned;
always @(*) begin
    if (ex_mem_read) begin//如果需要读内存
        case (ex_funct3)
            3'b000, 3'b100: ex_mem_aligned = 1'b1; // LB/LBU读哪个字节都是对的
            3'b001, 3'b101: ex_mem_aligned = !ex_alu_result[0]; // LH/LHU字节地址最后一位是0才可以
            3'b010: ex_mem_aligned = (ex_alu_result[1:0] == 2'b00); // LW字节地址最后两位是0才可以
            default: ex_mem_aligned = 1'b0;
        endcase
    end else if (ex_mem_write) begin//如果需要写内存
        case (ex_funct3)
            3'b000: ex_mem_aligned = 1'b1; // SB写哪个字节都是对的
            3'b001: ex_mem_aligned = !ex_alu_result[0]; // SH字节地址最后一位是0才可以
            3'b010: ex_mem_aligned = (ex_alu_result[1:0] == 2'b00); // SW字节地址最后两位是0才可以
            default: ex_mem_aligned = 1'b0;
        endcase
    end else begin
        ex_mem_aligned = 1'b1;
    end
end
//发现LS指令有错位
wire ex_ls_misaligned = ex_mem_access && !ex_mem_aligned;//涉及到读写内存但是内存的地址没有对齐
//判断本次Load/Store要访问1，2，4字节
wire [2:0] ex_mem_bytes = (ex_funct3[1:0] == 2'b10) ? 3'd4 :
                          (ex_funct3[1:0] == 2'b01) ? 3'd2 : 3'd1;
//计算最后一个被访问字节的地址，即 起始地址 + 字节数 − 1
wire [32:0] ex_mem_last_byte = {1'b0, ex_alu_result} + {30'b0, ex_mem_bytes} - 33'd1;

//这块的代码还没完全懂
// 仅普通 RAM 可以拆分访问。MMIO 和越界地址仍按原异常路径处理。
//访问未对齐，但最后一个字节仍在普通 RAM 内，可以由硬件完成
wire ex_mem_recover = ex_ls_misaligned && (ex_mem_last_byte < RAM_BYTES);
//访问未对齐且不能这样完成，触发异常
wire ex_ls_trap = ex_ls_misaligned && !ex_mem_recover;
//地址在 32 位字中的偏移量，加上访问字节数后超过 4，说明跨字，需要两笔请求
wire ex_mem_two_beats = ({1'b0, ex_alu_result[1:0]} + {1'b0, ex_mem_bytes}) > 4;
//8 位字节写掩码。低 4 位用于第一笔，高 4 位用于第二笔
wire [7:0] ex_store_byte_mask =
    ((ex_funct3 == 3'b010) ? 8'h0f : (ex_funct3 == 3'b001) ? 8'h03 : 8'h01)
    << ex_alu_result[1:0];
//按地址低两位，把 rs2 数据左移到对应字节位置；低 32 位用于第一笔，高 32 位用于第二笔
wire [63:0] ex_store_shifted = {32'b0, ex_rs2_value} << (8 * ex_alu_result[1:0]);

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
wire [63:0] ex_wb_load_pair = ex_wb_mem_second_q ?
    {mem_rdata, ex_wb_first_rdata_q} : {32'b0, mem_rdata};
wire [31:0] ex_wb_recovered_word =
    ex_wb_load_pair >> (8 * ex_wb_mem_addr_low_q);
always @(*) begin
    case (ex_wb_mem_addr_low_q)
        2'b00: ex_wb_load_byte = mem_rdata[7:0];
        2'b01: ex_wb_load_byte = mem_rdata[15:8];
        2'b10: ex_wb_load_byte = mem_rdata[23:16];
        2'b11: ex_wb_load_byte = mem_rdata[31:24];
        default: ex_wb_load_byte = 8'b0;
    endcase

    ex_wb_load_half = ex_wb_mem_recover_q ? ex_wb_recovered_word[15:0] :
                      ex_wb_mem_addr_low_q[1] ? mem_rdata[31:16] : mem_rdata[15:0];
    case (ex_wb_mem_funct3_q)
        3'b000: ex_wb_load_result = {{24{ex_wb_load_byte[7]}}, ex_wb_load_byte}; // LB
        3'b001: ex_wb_load_result = {{16{ex_wb_load_half[15]}}, ex_wb_load_half}; // LH
        3'b010: ex_wb_load_result = ex_wb_mem_recover_q ? ex_wb_recovered_word : mem_rdata; // LW
        3'b100: ex_wb_load_result = {24'b0, ex_wb_load_byte}; // LBU
        3'b101: ex_wb_load_result = {16'b0, ex_wb_load_half}; // LHU
        default: ex_wb_load_result = 32'b0;
    endcase
end
//写回数据选择器：决定EX/WB阶段要送给寄存器堆的值是哪一个
//Load的写回数据或者EX级提前计算好并保存的结果
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

//EX级BRANCH，JAL，JALR指令，指令是否有效以及跳转地址
//EX级BRANCH跳转地址：pc+立即数
wire [31:0] ex_branch_target = if_ex_pc_q + ex_imm;
//EX级JAL：当前指令有效且译码出JAL有效
wire        ex_jal  = if_ex_valid_q && ex_jal_en;
//EX级JALR：当前指令有效且译码出JALR有效
wire        ex_jalr = if_ex_valid_q && ex_jalr_en;
//EX级JAL地址：当前指令pc+立即数
wire [31:0] ex_jal_target = if_ex_pc_q + ex_imm;
//EX级JALR地址：rs1的值加立即数，最后一位置为0
wire [31:0] ex_jalr_sum = ex_rs1_value + ex_imm;
wire [31:0] ex_jalr_target = {ex_jalr_sum[31:1], 1'b0};
//表示EX级当前这条指令是否要改变取指方向：指令是jal，或者是jalr，或者是分支且满足分支条件
wire        ex_control_redirect = ex_jal || ex_jalr || (ex_branch && ex_branch_condition);
//改变取指方向的目标地址
wire [31:0] ex_redirect_target = ex_jalr ? ex_jalr_target : ex_jal  ? ex_jal_target  : ex_branch_target;
//计算跳转指令的返回地址
wire [31:0] ex_jump_link = if_ex_pc_q + 32'd4;
//表示当前 EX 级的跳转确实要发生，但跳转目标不是 4 字节对齐的指令地址
wire ex_instruction_misaligned = ex_control_redirect && (ex_redirect_target[1:0] != 2'b00);

// EX级的计算结果，CSR的旧值，返回地址（当前指令PC+4），U型立即数，当前指令PC+立即数或者ALU结果
wire [31:0] ex_result = ex_csr_en ? ex_csr_rdata :
                        (ex_jal || ex_jalr) ? ex_jump_link :
                        ex_lui_en ? ex_imm :
                        ex_auipc_en ? (if_ex_pc_q + ex_imm) :
                                      ex_alu_result;

// 当前EX级指令是否需要读取rs1或者rs2
//算数，分支，JALR，访存以及使用寄存器操作数的CSR指令需要rs1
wire ex_uses_rs1 = ex_arithmetic || ex_branch || ex_jalr || ex_mem_access ||
                   (ex_csr_en && !ex_csr_cmd[2]);
//寄存器型算数指令，分支和store需要rs2
wire ex_uses_rs2 = (ex_opcode == 7'b0110011) || ex_branch || ex_mem_write;

// WB -> EX 前递：Load 必须等响应返回且对齐，x0 永不前递。
//WB级中有有效指令，会写非x0寄存器，而且结果已经可用，若是Load必须等wb_mem_done=1
wire wb_forward_valid = !reset && ex_wb_valid_q &&
                        ex_wb_reg_write_q && (ex_wb_rd_q != 5'd0) &&
                        (!ex_wb_mem_read_q ||
                         wb_mem_done);
//EX 确实要用 rs1rs2，且它的编号等于 WB 要写的 rd，于是将 WB 结果前递给 rs1rs2
wire forward_rs1 = if_ex_valid_q && ex_uses_rs1 && wb_forward_valid &&
                   (ex_rs1 == ex_wb_rd_q);
wire forward_rs2 = if_ex_valid_q && ex_uses_rs2 && wb_forward_valid &&
                   (ex_rs2 == ex_wb_rd_q);

//EX 要读的 rs1 正好是 WB 即将写回的寄存器，于是直接用 ex_wb_writeback_data；否则用寄存器堆读出的 ex_rs1_data
assign ex_rs1_value = forward_rs1 ? ex_wb_writeback_data : ex_rs1_data;
assign ex_rs2_value = forward_rs2 ? ex_wb_writeback_data : ex_rs2_data;

// 有数据依赖且结果还不能前递时才暂停；访存等待优先保持整条流水线。
wire stall_raw = if_ex_valid_q && ex_wb_valid_q &&
                 ex_wb_reg_write_q && (ex_wb_rd_q != 5'd0) &&
                 !wb_forward_valid &&
                 ((ex_uses_rs1 && (ex_rs1 == ex_wb_rd_q)) ||
                  (ex_uses_rs2 && (ex_rs2 == ex_wb_rd_q)));
assign wb_mem_done = mem_ready && (!ex_wb_mem_two_beats_q || ex_wb_mem_second_q);
//WB级的LS是否完成，如果未完成则流水线必须等待
wire stall_mem = ex_wb_mem_access_q && !wb_mem_done;

// CSR 与异常在 EX 级生效；访存和 RAW 停顿期间保持不变。
assign csr_exec = !reset && if_ex_valid_q && ex_csr_en && !ex_illegal &&
                  !stall_mem && !stall_raw;
assign csr_mret_exec = !reset && if_ex_valid_q && ex_mret &&
                       !stall_mem && !stall_raw;
assign csr_trap_valid = !reset && if_ex_valid_q && !stall_mem && !stall_raw &&
                        (ex_ecall || ex_ebreak || ex_illegal ||
                         ex_instruction_misaligned || ex_ls_trap);
assign csr_trap_cause = ex_ecall ? 32'd11 :
                        ex_ebreak ? 32'd3 :
                        ex_illegal ? 32'd2 :
                        ex_instruction_misaligned ? 32'd0 :
                        ex_mem_read ? 32'd4 : 32'd6;
assign csr_trap_value = (ex_ecall || ex_ebreak) ? 32'b0 :
                        ex_illegal ? if_ex_instruction_q :
                        ex_instruction_misaligned ? ex_redirect_target :
                        ex_alu_result;


// 性能事件与下面 always 块采用同一优先级，避免冻结时重复计数。
assign profile_retire = !reset && ex_wb_valid_q &&
                        (!ex_wb_mem_access_q || wb_mem_done);
assign profile_mem_wait = !reset && stall_mem;
assign profile_raw_wait = !reset && !stall_mem && stall_raw;
assign profile_branch = !reset && !stall_mem && !stall_raw && ex_branch;
assign profile_branch_taken = profile_branch && ex_branch_condition;
assign profile_jump = !reset && !stall_mem && !stall_raw && (ex_jal || ex_jalr);

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
        ex_wb_mem_recover_q   <= 1'b0;
        ex_wb_mem_two_beats_q <= 1'b0;
        ex_wb_mem_second_q    <= 1'b0;
        ex_wb_first_rdata_q   <= 32'b0;
        ex_wb_second_wdata_q  <= 32'b0;
        ex_wb_second_wstrb_q  <= 4'b0;
        trap_valid_q          <= 1'b0;
        trap_pc_q             <= 32'b0;
        trap_instruction_q    <= 32'b0;
        trap_cause_q          <= 32'b0;
    end else if (stall_mem) begin
        debug_misaligned <= 1'b0;
        if (mem_ready && ex_wb_mem_two_beats_q && !ex_wb_mem_second_q) begin
            ex_wb_first_rdata_q <= mem_rdata;
            ex_wb_mem_second_q  <= 1'b1;
        end
    end else if (stall_raw) begin
        debug_misaligned  <= 1'b0;
        ex_wb_valid_q     <= 1'b0;
        ex_wb_reg_write_q <= 1'b0;
        ex_wb_mem_access_q <= 1'b0;
        ex_wb_mem_read_q   <= 1'b0;
        ex_wb_mem_write_q  <= 1'b0;
        ex_wb_mem_wstrb_q  <= 4'b0;
    end else if (if_ex_valid_q && (ex_ecall || ex_ebreak)) begin
        trap_valid_q       <= 1'b1;
        trap_pc_q          <= if_ex_pc_q;
        trap_instruction_q <= if_ex_instruction_q;
        trap_cause_q       <= ex_ecall ? 32'd11 : 32'd3;
        pc                 <= csr_mtvec;
        if_ex_valid_q      <= 1'b0;
        ex_wb_valid_q      <= 1'b0;
        ex_wb_reg_write_q  <= 1'b0;
        ex_wb_mem_access_q <= 1'b0;
        ex_wb_mem_read_q   <= 1'b0;
        ex_wb_mem_write_q  <= 1'b0;
        ex_wb_mem_wstrb_q  <= 4'b0;
        debug_misaligned   <= 1'b0;
    end else if (if_ex_valid_q && ex_illegal) begin
        trap_valid_q       <= 1'b1;
        trap_pc_q          <= if_ex_pc_q;
        trap_instruction_q <= if_ex_instruction_q;
        trap_cause_q       <= 32'd2;
        pc                 <= csr_mtvec;
        if_ex_valid_q      <= 1'b0;

        ex_wb_valid_q      <= 1'b0;
        ex_wb_reg_write_q  <= 1'b0;
        ex_wb_mem_access_q <= 1'b0;
        ex_wb_mem_read_q   <= 1'b0;
        ex_wb_mem_write_q  <= 1'b0;
        ex_wb_mem_wstrb_q  <= 4'b0;
        debug_misaligned   <= 1'b0;
    end else if (if_ex_valid_q && ex_instruction_misaligned) begin
        trap_valid_q       <= 1'b1;
        trap_pc_q          <= if_ex_pc_q;
        trap_instruction_q <= if_ex_instruction_q;
        trap_cause_q          <= 32'd0;
        pc                 <= csr_mtvec;
        if_ex_valid_q      <= 1'b0;

        ex_wb_valid_q      <= 1'b0;
        ex_wb_reg_write_q  <= 1'b0;
        ex_wb_mem_access_q <= 1'b0;
        ex_wb_mem_read_q   <= 1'b0;
        ex_wb_mem_write_q  <= 1'b0;
        ex_wb_mem_wstrb_q  <= 4'b0;
        debug_misaligned   <= 1'b0;
    end else if (ex_ls_trap) begin
        trap_valid_q       <= 1'b1;
        trap_pc_q          <= if_ex_pc_q;
        trap_instruction_q <= if_ex_instruction_q;
        trap_cause_q          <= ex_mem_read ? 32'd4 : 32'd6;
        pc                 <= csr_mtvec;
        if_ex_valid_q      <= 1'b0;

        ex_wb_valid_q      <= 1'b0;
        ex_wb_reg_write_q  <= 1'b0;
        ex_wb_mem_access_q <= 1'b0;
        ex_wb_mem_read_q   <= 1'b0;
        ex_wb_mem_write_q  <= 1'b0;
        ex_wb_mem_wstrb_q  <= 4'b0;
        debug_misaligned   <= 1'b1;
    end else if (if_ex_valid_q && ex_mret) begin
        // 返回也冲刷已取到的顺序指令；MRET 本身在 WB 级退休。
        debug_misaligned      <= 1'b0;
        pc                    <= csr_mepc;
        if_ex_valid_q         <= 1'b0;
        ex_wb_valid_q         <= 1'b1;
        ex_wb_pc_q            <= if_ex_pc_q;
        ex_wb_instruction_q   <= if_ex_instruction_q;
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
    //需要重新定位下一条指令pc的情况
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
    //一般的正常情况
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
                                ex_csr_en ||
                                ex_mem_read);
        ex_wb_result_q      <= ex_result;
        ex_wb_mem_access_q   <= ex_mem_access;
        ex_wb_mem_read_q     <= ex_mem_access && ex_mem_read;
        ex_wb_mem_write_q    <= ex_mem_access && ex_mem_write;
        ex_wb_mem_addr_q     <= ex_alu_result;
        ex_wb_mem_wdata_q    <= ex_mem_write ?
                                (ex_mem_recover ? ex_store_shifted[31:0] : ex_store_wdata) : 32'b0;
        ex_wb_mem_wstrb_q    <= ex_mem_write ?
                                (ex_mem_recover ? ex_store_byte_mask[3:0] : ex_store_wstrb) : 4'b0;
        ex_wb_second_wdata_q <= ex_store_shifted[63:32];
        ex_wb_second_wstrb_q <= ex_store_byte_mask[7:4];
        ex_wb_mem_funct3_q   <= ex_funct3;
        ex_wb_mem_addr_low_q <= ex_alu_result[1:0];
        ex_wb_load_aligned_q <= ex_mem_aligned;
        ex_wb_mem_recover_q   <= ex_mem_recover;
        ex_wb_mem_two_beats_q <= ex_mem_recover && ex_mem_two_beats;
        ex_wb_mem_second_q    <= 1'b0;
    end
end

assign mem_valid = !reset && ex_wb_valid_q && ex_wb_mem_access_q;
assign mem_write = mem_valid && ex_wb_mem_write_q;
assign mem_wstrb = mem_valid ? (ex_wb_mem_second_q ? ex_wb_second_wstrb_q : ex_wb_mem_wstrb_q) : 4'b0;
assign mem_addr  = mem_valid ? (ex_wb_mem_recover_q ?
                   ({ex_wb_mem_addr_q[31:2], 2'b00} + (ex_wb_mem_second_q ? 32'd4 : 32'd0)) :
                   ex_wb_mem_addr_q) : 32'b0;
assign mem_wdata = mem_valid ? (ex_wb_mem_second_q ? ex_wb_second_wdata_q : ex_wb_mem_wdata_q) : 32'b0;

endmodule
