`timescale 1ns/1ps

module tb_board_rom_consistency;
    reg [31:0] pc;
    wire [31:0] instruction;
    reg [31:0] expected [0:255];
    integer word_index;

    instruction_rom #(.BOARD_DEMO(1)) dut (
        .pc          (pc),
        .instruction (instruction)
    );

    initial begin
        $readmemh("program.hex", expected);
        for (word_index = 0; word_index < 256; word_index = word_index + 1) begin
            pc = word_index * 4;
            #1;
            if (instruction !== expected[word_index])
                $fatal(1, "FAIL board ROM word %0d: inline=%h hex=%h",
                       word_index, instruction, expected[word_index]);
        end
        $display("PASS board ROM matches all 256 program.hex words");
        $finish;
    end
endmodule
