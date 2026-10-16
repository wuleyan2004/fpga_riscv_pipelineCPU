`timescale 1ns/1ps

module tb_modules;
    reg clk = 0;
    always #5 clk = ~clk;

    reg [31:0] a, b;
    reg [3:0] alu_op;
    wire [31:0] alu_result;
    alu u_alu(.a(a), .b(b), .op(alu_op), .result(alu_result));

    wire equal, signed_less, unsigned_less;
    branch_compare u_compare(.rs1_data(a), .rs2_data(b),
        .equal(equal), .signed_less(signed_less), .unsigned_less(unsigned_less));

    reg [31:0] instruction;
    reg [2:0] imm_type;
    wire [31:0] imm;
    imm_gen u_imm(.instruction(instruction), .imm_type(imm_type), .imm(imm));

    reg [31:0] decode_instruction;
    wire reg_write, alu_src_imm, mem_read, mem_write;
    wire branch_en, jal_en, jalr_en, lui_en, auipc_en;
    wire illegal, ecall, ebreak, mret, csr_en;
    wire [2:0] csr_cmd;
    wire [3:0] decode_alu_op;
    wire [2:0] decode_imm_type;
    decoder u_decoder(
        .opcode(decode_instruction[6:0]),
        .funct3(decode_instruction[14:12]),
        .funct7(decode_instruction[31:25]),
        .instruction(decode_instruction),
        .reg_write(reg_write), .alu_src_imm(alu_src_imm),
        .alu_op(decode_alu_op), .mem_read(mem_read), .mem_write(mem_write),
        .imm_type(decode_imm_type), .branch_en(branch_en), .jal_en(jal_en),
        .jalr_en(jalr_en), .lui_en(lui_en), .auipc_en(auipc_en),
        .illegal(illegal), .ecall(ecall), .ebreak(ebreak),
        .mret(mret), .csr_en(csr_en), .csr_cmd(csr_cmd)
    );
    wire [23:0] decoded = {reg_write, alu_src_imm, decode_alu_op,
        mem_read, mem_write, decode_imm_type, branch_en, jal_en,
        jalr_en, lui_en, auipc_en, illegal, ecall, ebreak,
        mret, csr_en, csr_cmd};

    reg [4:0] rs1_addr = 0, rs2_addr = 0, rd_addr = 0;
    reg [31:0] rd_data = 0;
    reg rd_we = 0;
    wire [31:0] rs1_data, rs2_data;
    regfile u_regfile(.clk(clk), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(rs1_data), .rs2_data(rs2_data), .rd_addr(rd_addr),
        .rd_data(rd_data), .rd_we(rd_we));

    string alu_file, branch_file, imm_file, decode_file;
    integer fd, rc, j, alu_count = 0, branch_count = 0;
    integer imm_count = 0, decode_count = 0;
    reg [31:0] expected_word;
    reg [2:0] expected_branch;
    reg [23:0] expected_decode;

    initial begin
        if (!$value$plusargs("ALU=%s", alu_file) ||
            !$value$plusargs("BRANCH=%s", branch_file) ||
            !$value$plusargs("IMM=%s", imm_file) ||
            !$value$plusargs("DECODE=%s", decode_file))
            $fatal(1, "missing module vector files");

        fd = $fopen(alu_file, "r");
        if (!fd) $fatal(1, "cannot open ALU vectors");
        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%h %h %h %h\n", a, b, alu_op, expected_word);
            if (rc == 4) begin
                #1;
                if (alu_result !== expected_word)
                    $fatal(1, "ALU vector %0d a=%h b=%h op=%h got=%h expected=%h",
                        alu_count, a, b, alu_op, alu_result, expected_word);
                alu_count = alu_count + 1;
            end else if (rc != -1) $fatal(1, "malformed ALU vector");
        end
        $fclose(fd);

        fd = $fopen(branch_file, "r");
        if (!fd) $fatal(1, "cannot open branch vectors");
        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%h %h %h\n", a, b, expected_branch);
            if (rc == 3) begin
                #1;
                if ({equal, signed_less, unsigned_less} !== expected_branch)
                    $fatal(1, "branch vector %0d a=%h b=%h", branch_count, a, b);
                branch_count = branch_count + 1;
            end else if (rc != -1) $fatal(1, "malformed branch vector");
        end
        $fclose(fd);

        fd = $fopen(imm_file, "r");
        if (!fd) $fatal(1, "cannot open immediate vectors");
        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%h %h %h\n", instruction, imm_type, expected_word);
            if (rc == 3) begin
                #1;
                if (imm !== expected_word)
                    $fatal(1, "immediate vector %0d ins=%h type=%h got=%h expected=%h",
                        imm_count, instruction, imm_type, imm, expected_word);
                imm_count = imm_count + 1;
            end else if (rc != -1) $fatal(1, "malformed immediate vector");
        end
        $fclose(fd);

        fd = $fopen(decode_file, "r");
        if (!fd) $fatal(1, "cannot open decoder vectors");
        while (!$feof(fd)) begin
            rc = $fscanf(fd, "%h %h\n", decode_instruction, expected_decode);
            if (rc == 2) begin
                #1;
                if (decoded !== expected_decode)
                    $fatal(1, "decoder vector %0d ins=%h got=%h expected=%h",
                        decode_count, decode_instruction, decoded, expected_decode);
                decode_count = decode_count + 1;
            end else if (rc != -1) $fatal(1, "malformed decoder vector");
        end
        $fclose(fd);

        @(negedge clk);
        rd_addr = 5'd1; rd_data = 32'h89abcdef; rd_we = 1;
        @(posedge clk); #1;
        rs1_addr = 5'd1; rs2_addr = 5'd1;
        #1;
        if (rs1_data !== 32'h89abcdef || rs2_data !== 32'h89abcdef)
            $fatal(1, "regfile write/read x1 failed");
        @(negedge clk);
        rd_addr = 5'd0; rd_data = 32'hffffffff;
        @(posedge clk); #1;
        rs1_addr = 0; rs2_addr = 1;
        #1;
        if (rs1_data !== 0 || rs2_data !== 32'h89abcdef)
            $fatal(1, "regfile x0 or x1 failed");
        @(negedge clk);
        rd_we = 0; rd_addr = 5'd1; rd_data = 0;
        @(posedge clk); #1;
        if (rs2_data !== 32'h89abcdef)
            $fatal(1, "regfile write-disable failed");

        for (j=0; j<32; j=j+1) begin
            @(negedge clk);
            rd_we=1; rd_addr=j; rd_data=32'h12340000+j;
            @(posedge clk); #1;
            rs1_addr=j; rs2_addr=j;
            #1;
            if (rs1_data !== (j==0 ? 32'b0 : 32'h12340000+j) ||
                rs2_data !== (j==0 ? 32'b0 : 32'h12340000+j))
                $fatal(1, "regfile address %0d failed", j);
        end
        @(negedge clk);
        rd_we=0; rd_addr=1; rd_data=0;
        rs1_addr=1; rs2_addr=31;
        @(posedge clk); #1;
        if (rs1_data !== 32'h12340001 || rs2_data !== 32'h1234001f)
            $fatal(1, "regfile independent reads or write-disable failed");

        if (alu_count < 1000 || branch_count < 1000 ||
            imm_count < 12000 || decode_count < 130000)
            $fatal(1, "module vector count too small");
        $display("PASS modules alu=%0d branch=%0d immediate=%0d decoder=%0d regfile=32_addresses",
            alu_count, branch_count, imm_count, decode_count);
        $finish;
    end
endmodule
