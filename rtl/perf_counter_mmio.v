// CoreMark 诊断计数器。写 CTRL=1 清零并开始，写 CTRL=0 停止并保持结果。
// 32 位计数器自然回绕；27 MHz 下连续计时约 159 秒后 cycles 回绕。
module perf_counter_mmio (
    input  wire        clk,
    input  wire        reset,
    input  wire        mem_valid,
    input  wire        mem_write,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    output wire        mem_ready,
    output reg  [31:0] mem_rdata,
    input  wire        retire,
    input  wire        mem_wait,
    input  wire        raw_wait,
    input  wire        branch,
    input  wire        branch_taken,
    input  wire        jump
);
    localparam CTRL         = 32'h1000_0030;
    localparam CYCLES       = 32'h1000_0034;
    localparam RETIRED      = 32'h1000_0038;
    localparam MEM_WAIT     = 32'h1000_003c;
    localparam RAW_WAIT     = 32'h1000_0040;
    localparam BRANCHES     = 32'h1000_0044;
    localparam TAKEN        = 32'h1000_0048;
    localparam BRANCH_COST  = 32'h1000_004c;
    localparam JUMP_COST    = 32'h1000_0050;

    reg running_q;
    reg response_q;
    reg [31:0] cycles_q, retired_q, mem_wait_q, raw_wait_q;
    reg [31:0] branches_q, taken_q, branch_cost_q, jump_cost_q;
    assign mem_ready = response_q;

    always @(posedge clk) begin
        if (reset) begin
            running_q <= 1'b0;
            response_q <= 1'b0;
            mem_rdata <= 32'b0;
            cycles_q <= 32'b0;
            retired_q <= 32'b0;
            mem_wait_q <= 32'b0;
            raw_wait_q <= 32'b0;
            branches_q <= 32'b0;
            taken_q <= 32'b0;
            branch_cost_q <= 32'b0;
            jump_cost_q <= 32'b0;
        end else begin
            if (running_q) begin
                cycles_q <= cycles_q + 32'd1;
                if (retire) retired_q <= retired_q + 32'd1;
                if (mem_wait) mem_wait_q <= mem_wait_q + 32'd1;
                if (raw_wait) raw_wait_q <= raw_wait_q + 32'd1;
                if (branch) branches_q <= branches_q + 32'd1;
                if (branch_taken) begin
                    taken_q <= taken_q + 32'd1;
                    // 本流水线每次控制重定向会清空 IF/EX，代价为一个取指空拍。
                    branch_cost_q <= branch_cost_q + 32'd1;
                end
                if (jump) jump_cost_q <= jump_cost_q + 32'd1;
            end
            if (response_q) begin
                response_q <= 1'b0;
            end else if (mem_valid) begin
                response_q <= 1'b1;
                if (mem_write && mem_addr == CTRL) begin
                    running_q <= mem_wdata[0];
                    if (mem_wdata[0]) begin
                        cycles_q <= 32'b0;
                        retired_q <= 32'b0;
                        mem_wait_q <= 32'b0;
                        raw_wait_q <= 32'b0;
                        branches_q <= 32'b0;
                        taken_q <= 32'b0;
                        branch_cost_q <= 32'b0;
                        jump_cost_q <= 32'b0;
                    end
                end
                if (mem_write) mem_rdata <= 32'b0;
                else case (mem_addr)
                    CTRL:        mem_rdata <= {31'b0, running_q};
                    CYCLES:      mem_rdata <= cycles_q;
                    RETIRED:     mem_rdata <= retired_q;
                    MEM_WAIT:    mem_rdata <= mem_wait_q;
                    RAW_WAIT:    mem_rdata <= raw_wait_q;
                    BRANCHES:    mem_rdata <= branches_q;
                    TAKEN:       mem_rdata <= taken_q;
                    BRANCH_COST: mem_rdata <= branch_cost_q;
                    JUMP_COST:   mem_rdata <= jump_cost_q;
                    default:     mem_rdata <= 32'b0;
                endcase
            end
        end
    end
endmodule
