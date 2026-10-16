`timescale 1ns/1ps

// Delays the real RAM's acceptance and delivery separately. Each CPU request
// is forwarded once even when its response is held for additional cycles.
module pipeline_mem_fixture #(
    parameter DIRECT = 0, PRE_DELAY = 0, POST_DELAY = 0, VARY = 0
)(input clk, reset, mem_valid, mem_write,
  input [3:0] mem_wstrb,
  input [31:0] mem_addr, mem_wdata,
  output mem_ready, output [31:0] mem_rdata);
    integer pre_count = 0, post_count = 0, transaction = 0;
    reg accepted = 0, response_seen = 0;
    wire ram_ready;
    wire [31:0] ram_rdata;
    wire ram_valid = DIRECT ? mem_valid :
        mem_valid && !accepted && pre_count >= PRE_DELAY + (VARY ? transaction % 3 : 0);

    sync_data_ram ram (
        .clk(clk), .reset(reset), .mem_valid(ram_valid), .mem_write(mem_write),
        .mem_wstrb(mem_wstrb), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(ram_ready), .mem_rdata(ram_rdata)
    );
    assign mem_ready = DIRECT ? ram_ready :
        response_seen && post_count >= POST_DELAY + (VARY ? transaction % 4 : 0);
    assign mem_rdata = ram_rdata;

    always @(posedge clk) begin
        if (reset) begin
            pre_count <= 0;
            post_count <= 0;
            transaction <= 0;
            accepted <= 0;
            response_seen <= 0;
        end else if (!DIRECT) begin
            if (mem_valid && mem_ready) begin
                pre_count <= 0;
                post_count <= 0;
                accepted <= 0;
                response_seen <= 0;
                transaction <= transaction + 1;
            end else begin
                if (mem_valid && !accepted) begin
                    if (ram_valid && ram.state == 0)
                        accepted <= 1;
                    else
                        pre_count <= pre_count + 1;
                end
                if (ram_ready && !response_seen) begin
                    response_seen <= 1;
                    post_count <= 0;
                end else if (response_seen && !mem_ready)
                    post_count <= post_count + 1;
            end
        end
    end
endmodule

module tb_pipeline_mem;
    parameter DIRECT = 0, PRE_DELAY = 0, POST_DELAY = 0, VARY = 0;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire [31:0] pc, instruction, mem_addr, mem_wdata, mem_rdata;
    wire mem_valid, mem_write, mem_ready, debug_misaligned;
    wire [3:0] mem_wstrb;
    reg [31:0] program_words [0:255];
    assign instruction = program_words[pc[9:2]];
    cpu_core_pipeline dut (
        .clk(clk), .reset(reset), .instruction(instruction), .pc(pc),
        .mem_valid(mem_valid), .mem_write(mem_write), .mem_wstrb(mem_wstrb),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata), .debug_misaligned(debug_misaligned)
    );
    pipeline_mem_fixture #(.DIRECT(DIRECT), .PRE_DELAY(PRE_DELAY),
                          .POST_DELAY(POST_DELAY), .VARY(VARY)) memory (
        .clk(clk), .reset(reset), .mem_valid(mem_valid), .mem_write(mem_write),
        .mem_wstrb(mem_wstrb), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata)
    );

    reg [31:0] expected_pc[0:255], expected_ins[0:255], expected_data[0:255];
    reg expected_we[0:255];
    reg [4:0] expected_rd[0:255];
    reg expected_write[0:255], expected_bad[0:255];
    reg [31:0] expected_addr[0:255], expected_wdata[0:255];
    reg [3:0] expected_strobe[0:255];
    reg [31:0] expected_memory[0:255], golden_regs[0:31];
    integer n, request_n, bad_n, expected_stores, expected_effective_stores;
    integer fd, rc, i, step = 0, request_index = 0, cycles = 0;
    integer accepts = 0, store_accepts = 0, effective_stores = 0, bad_pulses = 0;
    integer memory_holds = 0, dependency_bubbles = 0;
    integer forwarded_ex = 0, forwarded_loads = 0;
    reg request_active = 0;
    reg [68:0] held_request;
    reg [31:0] held_pc, held_if_pc, held_if_ins;
    reg held_if_valid, held_mem_wait;
    reg [179:0] held_wb;
    reg retire;
    string wave;

    initial begin
        if (!$value$plusargs("N=%d", n) || !$value$plusargs("REQUESTS=%d", request_n) ||
            !$value$plusargs("BAD=%d", bad_n) || !$value$plusargs("STORES=%d", expected_stores) ||
            !$value$plusargs("EFFECTIVE_STORES=%d", expected_effective_stores))
            $fatal(1, "missing fixture counts");
        if (!$value$plusargs("WAVE=%s", wave)) wave = "pipeline_mem.vcd";
        $dumpfile(wave); $dumpvars(0, tb_pipeline_mem);
        $readmemh("program.hex", program_words);
        $readmemh("initial.hex", memory.ram.mem);
        $readmemh("final.hex", expected_memory);
        for (i = 0; i < 32; i = i + 1) golden_regs[i] = 0;
        fd = $fopen("retire.txt", "r");
        if (!fd) $fatal(1, "missing retirement oracle");
        for (i = 0; i < n; i = i + 1) begin
            rc = $fscanf(fd, "%h %h %h %h %h\n", expected_pc[i], expected_ins[i],
                         expected_we[i], expected_rd[i], expected_data[i]);
            if (rc != 5) $fatal(1, "malformed retirement oracle");
        end
        $fclose(fd);
        fd = $fopen("requests.txt", "r");
        if (!fd) $fatal(1, "missing request oracle");
        for (i = 0; i < request_n; i = i + 1) begin
            rc = $fscanf(fd, "%h %h %h %h %h\n", expected_write[i], expected_addr[i],
                         expected_strobe[i], expected_wdata[i], expected_bad[i]);
            if (rc != 5) $fatal(1, "malformed request oracle");
        end
        $fclose(fd);
        repeat (3) @(negedge clk);
        if (mem_valid !== 0 || dut.u_regfile.rd_we !== 0)
            $fatal(1, "memory/writeback active in reset");
        reset = 0;
    end

    // Observe newly launched requests between edges. A ready edge ends a
    // transaction even if the following request keeps mem_valid asserted.
    always @(negedge clk) begin
        if (!reset) begin
            if (mem_valid) begin
                if (!request_active) begin
                    if (request_index >= request_n ||
                        mem_write !== expected_write[request_index] ||
                        mem_addr !== expected_addr[request_index] ||
                        mem_wstrb !== expected_strobe[request_index] ||
                        mem_wdata !== expected_wdata[request_index])
                        $fatal(1, "request mismatch index=%0d addr=%h data=%h mask=%h",
                               request_index, mem_addr, mem_wdata, mem_wstrb);
                    held_request = {mem_write, mem_wstrb, mem_addr, mem_wdata};
                    request_active = 1;
                    if (debug_misaligned !== expected_bad[request_index])
                        $fatal(1, "wrong alignment flag for request %0d", request_index);
                end else begin
                    if ({mem_write, mem_wstrb, mem_addr, mem_wdata} !== held_request)
                        $fatal(1, "request changed before completion");
                    if (debug_misaligned !== 0)
                        $fatal(1, "alignment pulse repeated while waiting");
                end
            end else if (request_active || debug_misaligned !== 0)
                $fatal(1, "request dropped or stray alignment flag");
            if (debug_misaligned) bad_pulses = bad_pulses + 1;
        end
    end

    always @(posedge clk) begin
        if (!reset) begin
            cycles = cycles + 1;
            if (cycles > 5000) $fatal(1, "pipeline timeout");
            if (^{pc, mem_valid, mem_ready, dut.u_regfile.rd_we} === 1'bx)
                $fatal(1, "unknown control signal");
            held_mem_wait = mem_valid && !mem_ready;
            held_pc = pc;
            held_if_valid = dut.if_ex_valid_q;
            held_if_pc = dut.if_ex_pc_q;
            held_if_ins = dut.if_ex_instruction_q;
            held_wb = {dut.ex_wb_valid_q, dut.ex_wb_pc_q, dut.ex_wb_instruction_q,
                dut.ex_wb_rd_q, dut.ex_wb_reg_write_q, dut.ex_wb_result_q,
                dut.ex_wb_mem_access_q, dut.ex_wb_mem_read_q, dut.ex_wb_mem_write_q,
                dut.ex_wb_mem_addr_q, dut.ex_wb_mem_wdata_q, dut.ex_wb_mem_wstrb_q,
                dut.ex_wb_mem_funct3_q, dut.ex_wb_mem_addr_low_q, dut.ex_wb_load_aligned_q};
            if (held_mem_wait) memory_holds = memory_holds + 1;
            if (!held_mem_wait && dut.stall_raw) dependency_bubbles = dependency_bubbles + 1;
            if (dut.ex_wb_mem_read_q && !mem_ready && (dut.forward_rs1 || dut.forward_rs2))
                $fatal(1, "Load forwarded before its response");
            if (!held_mem_wait && (dut.forward_rs1 || dut.forward_rs2)) begin
                forwarded_ex = forwarded_ex + 1;
                if (dut.ex_wb_mem_read_q) forwarded_loads = forwarded_loads + 1;
            end

            // Count the actual physical RAM acceptance, independently of CPU retirement.
            if (memory.ram.mem_valid && memory.ram.state == 0) begin
                accepts = accepts + 1;
                if (mem_write) begin
                    store_accepts = store_accepts + 1;
                    if (mem_wstrb != 0) effective_stores = effective_stores + 1;
                end
            end
            if (mem_valid && mem_ready) begin
                if (!request_active) $fatal(1, "response without a monitored request");
                if ({mem_write, mem_wstrb, mem_addr, mem_wdata} !== held_request)
                    $fatal(1, "request changed at response edge");
                request_index = request_index + 1;
                request_active = 0;
            end

            retire = dut.ex_wb_valid_q && (!dut.ex_wb_mem_access_q || mem_ready);
            if (dut.u_regfile.rd_we !== (retire && expected_we[step]))
                $fatal(1, "incorrect write enable step=%0d", step);
            if (retire) begin
                if (step >= n || dut.ex_wb_pc_q !== expected_pc[step] ||
                    dut.ex_wb_instruction_q !== expected_ins[step])
                    $fatal(1, "retirement order changed step=%0d pc=%h", step, dut.ex_wb_pc_q);
                if (expected_we[step]) begin
                    if (dut.ex_wb_rd_q !== expected_rd[step] ||
                        dut.u_regfile.rd_data !== expected_data[step])
                        $fatal(1, "writeback mismatch step=%0d rd=%0d actual=%h expected=%h",
                               step, dut.ex_wb_rd_q, dut.u_regfile.rd_data, expected_data[step]);
                    if (expected_rd[step] != 0) golden_regs[expected_rd[step]] = expected_data[step];
                end
                step = step + 1;
            end
            #1;
            if (held_mem_wait &&
                ({pc, dut.if_ex_valid_q, dut.if_ex_pc_q, dut.if_ex_instruction_q} !==
                 {held_pc, held_if_valid, held_if_pc, held_if_ins} ||
                 {dut.ex_wb_valid_q, dut.ex_wb_pc_q, dut.ex_wb_instruction_q,
                  dut.ex_wb_rd_q, dut.ex_wb_reg_write_q, dut.ex_wb_result_q,
                  dut.ex_wb_mem_access_q, dut.ex_wb_mem_read_q, dut.ex_wb_mem_write_q,
                  dut.ex_wb_mem_addr_q, dut.ex_wb_mem_wdata_q, dut.ex_wb_mem_wstrb_q,
                  dut.ex_wb_mem_funct3_q, dut.ex_wb_mem_addr_low_q, dut.ex_wb_load_aligned_q}
                  !== held_wb))
                $fatal(1, "pipeline state changed during a memory wait");
            for (i = 0; i < 32; i = i + 1)
                if (dut.u_regfile.regs[i] !== golden_regs[i])
                    $fatal(1, "unexpected register change x%0d actual=%h expected=%h",
                           i, dut.u_regfile.regs[i], golden_regs[i]);
            if (step == n) begin
                for (i = 0; i < 256; i = i + 1)
                    if (memory.ram.mem[i] !== expected_memory[i])
                        $fatal(1, "RAM mismatch word=%0d actual=%h expected=%h",
                               i, memory.ram.mem[i], expected_memory[i]);
                if (request_index != request_n || accepts != request_n ||
                    store_accepts != expected_stores || effective_stores != expected_effective_stores ||
                    bad_pulses != bad_n || memory_holds == 0 || dependency_bubbles != 0 ||
                    forwarded_ex == 0 || forwarded_loads == 0)
                    $fatal(1, "counts mismatch requests=%0d accepts=%0d stores=%0d effective=%0d bad=%0d",
                           request_index, accepts, store_accepts, effective_stores, bad_pulses);
                $display("PASS pipeline_mem instructions=%0d cycles=%0d requests=%0d physical_stores=%0d effective_stores=%0d misaligned=%0d holds=%0d raw_bubbles=%0d forwarded_ex=%0d forwarded_loads=%0d",
                    n, cycles, accepts, store_accepts, effective_stores, bad_pulses,
                    memory_holds, dependency_bubbles, forwarded_ex, forwarded_loads);
                $finish;
            end
        end
    end
endmodule
