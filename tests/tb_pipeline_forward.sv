`timescale 1ns/1ps

module tb_pipeline_forward;
    parameter DIRECT = 1, PRE_DELAY = 0, POST_DELAY = 0;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [31:0] rom[0:255];
    wire [31:0] pc, instruction, mem_addr, mem_wdata, mem_rdata;
    wire mem_valid, mem_write, mem_ready, misaligned;
    wire [3:0] mem_wstrb;
    assign instruction = rom[pc[9:2]];
    cpu_core_pipeline dut (
        .clk(clk), .reset(reset), .instruction(instruction), .pc(pc),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_ready(mem_ready),
        .mem_rdata(mem_rdata), .debug_misaligned(misaligned)
    );
    pipeline_mem_fixture #(.DIRECT(DIRECT), .PRE_DELAY(PRE_DELAY),
                          .POST_DELAY(POST_DELAY)) memory (
        .clk(clk), .reset(reset), .mem_valid(mem_valid), .mem_write(mem_write),
        .mem_wstrb(mem_wstrb), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata)
    );
    integer i, cycles = 0, stores = 0, raw_bubbles = 0;
    integer branch_rs1 = 0, branch_rs2 = 0, load_branches = 0, load_jalr = 0;
    integer both_ports = 0, load_waits = 0;
    reg [31:0] held_pc;
    reg [68:0] held_request;
    reg waiting, done;
    string wave;

    initial begin
        if (!$value$plusargs("WAVE=%s", wave)) wave = "forward.vcd";
        $dumpfile(wave); $dumpvars(0, tb_pipeline_forward);
        $readmemh("program.hex", rom);
        for (i = 0; i < 256; i = i + 1) memory.ram.mem[i] = 0;
        repeat (3) @(negedge clk);
        reset = 0;
    end

    always @(posedge clk) begin
        if (reset) begin
            if (dut.wb_forward_valid || dut.forward_rs1 || dut.forward_rs2)
                $fatal(1, "forwarding active in reset");
        end else begin
            cycles = cycles + 1;
            if (cycles > 1500) $fatal(1, "forward test timeout PC=%h", pc);
            if (misaligned) $fatal(1, "unexpected misaligned request");
            if ((!dut.ex_wb_valid_q || !dut.ex_wb_reg_write_q || dut.ex_wb_rd_q == 0) &&
                (dut.forward_rs1 || dut.forward_rs2)) $fatal(1, "invalid WB forwarded");
            if (!dut.if_ex_valid_q && (dut.forward_rs1 || dut.forward_rs2))
                $fatal(1, "invalid EX used forwarding");
            waiting = mem_valid && !mem_ready;
            held_pc = pc;
            held_request = {mem_write, mem_wstrb, mem_addr, mem_wdata};
            if (waiting && dut.ex_wb_mem_read_q) begin
                load_waits = load_waits + 1;
                if (dut.wb_forward_valid || dut.forward_rs1 || dut.forward_rs2 || dut.u_regfile.rd_we)
                    $fatal(1, "Load result used before response");
            end
            if (!dut.stall_mem) begin
                if (dut.stall_raw) raw_bubbles = raw_bubbles + 1;
                if (dut.forward_rs1 && dut.forward_rs2) both_ports = both_ports + 1;
                if (dut.ex_branch) begin
                    if (dut.forward_rs1) branch_rs1 = branch_rs1 + 1;
                    if (dut.forward_rs2) branch_rs2 = branch_rs2 + 1;
                    if (dut.ex_wb_mem_read_q && (dut.forward_rs1 || dut.forward_rs2))
                        load_branches = load_branches + 1;
                end
                if (dut.ex_jalr && dut.ex_wb_mem_read_q && dut.forward_rs1)
                    load_jalr = load_jalr + 1;
            end
            if (memory.ram.mem_valid && memory.ram.state == 0 && mem_write)
                stores = stores + 1;
            done = mem_valid && mem_ready && mem_write && mem_addr == 0;
            #1;
            if (waiting && (pc !== held_pc ||
                {mem_write, mem_wstrb, mem_addr, mem_wdata} !== held_request))
                $fatal(1, "request or PC changed before ready");
            if (done) begin
                if (memory.ram.mem[0] !== 123 || stores != 5 ||
                    memory.ram.mem[3] !== 0 || memory.ram.mem[19] !== 0)
                    $fatal(1, "wrong path or incorrect Store: signature=%h stores=%0d",
                           memory.ram.mem[0], stores);
                if (dut.u_regfile.regs[0] !== 0 || dut.u_regfile.regs[1] !== 7 ||
                    dut.u_regfile.regs[2] !== 12 || dut.u_regfile.regs[3] !== 24 ||
                    dut.u_regfile.regs[4] !== 14 || dut.u_regfile.regs[5] !== 2 ||
                    dut.u_regfile.regs[11] !== 15 || dut.u_regfile.regs[12] !== 14 ||
                    dut.u_regfile.regs[29] !== 32'h56 || dut.u_regfile.regs[31] !== 32'h55)
                    $fatal(1, "arithmetic/Load/x0/no-op result incorrect");
                if (dut.u_regfile.regs[13] !== dut.u_regfile.regs[14] ||
                    dut.u_regfile.regs[15] !== dut.u_regfile.regs[13] - 4 ||
                    dut.u_regfile.regs[17] !== dut.u_regfile.regs[16] + 1 ||
                    memory.ram.mem[1] !== dut.u_regfile.regs[15] ||
                    memory.ram.mem[2] !== dut.u_regfile.regs[17])
                    $fatal(1, "jump link or Load -> JALR incorrect");
                if (raw_bubbles != 0 || branch_rs1 < 12 || branch_rs2 < 6 ||
                    both_ports < 2 || load_branches != 2 || load_jalr != 1 || load_waits == 0)
                    $fatal(1, "missing forwarding coverage");
                $display("PASS pipeline_forward cycles=%0d raw_bubbles=%0d branch_rs1=%0d branch_rs2=%0d load_branches=%0d load_jalr=%0d both_ports=%0d load_waits=%0d stores=%0d",
                         cycles, raw_bubbles, branch_rs1, branch_rs2, load_branches,
                         load_jalr, both_ports, load_waits, stores);
                $finish;
            end
        end
    end
endmodule
