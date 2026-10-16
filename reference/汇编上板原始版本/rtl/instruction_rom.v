module instruction_rom #(
    parameter BOARD_DEMO = 0,
    parameter integer BOARD_DEMO_DELAY_COUNT = 6_750_000
)(
    input wire[31:0] pc,//输入指令地址
    output wire[31:0] instruction//输出指令
);

generate
    if (BOARD_DEMO) begin : g_board_demo
        // Same program as board_demo.S/program.hex, with a configurable delay
        // count for fast simulation. No external file is needed on the FPGA.
        localparam [31:0] DELAY_VALUE = BOARD_DEMO_DELAY_COUNT;
        localparam [19:0] DELAY_HI20 = (DELAY_VALUE + 32'd2048) >> 12;
        localparam [11:0] DELAY_LO12 = DELAY_VALUE[11:0];
        reg [31:0] demo_instruction;
        always @(*) begin
            case (pc[9:2])
                8'd0: demo_instruction = 32'h100000b7;
                8'd1: demo_instruction = 32'h00100113;
                8'd2: demo_instruction = 32'h0020a023;
                8'd3: demo_instruction = 32'h04f00113;
                8'd4: demo_instruction = 32'h0020a823;
                8'd5: demo_instruction = 32'h04b00113;
                8'd6: demo_instruction = 32'h0020a823;
                8'd7: demo_instruction = 32'h00a00113;
                8'd8: demo_instruction = 32'h0020a823;
                8'd9: demo_instruction = {DELAY_HI20, 5'd3, 7'b0110111};
                8'd10: demo_instruction = {DELAY_LO12, 5'd3, 3'b000, 5'd3, 7'b0010011};
                8'd11: demo_instruction = 32'hfff18193;
                8'd12: demo_instruction = 32'hfe019ee3;
                8'd13: demo_instruction = 32'hfd9ff06f;
                default: demo_instruction = 32'h00000013;
            endcase
        end
        assign instruction = demo_instruction;
    end else begin : g_file_program
        reg [31:0] imem [0:255];
        integer i;
        initial begin
            for (i = 0; i < 256; i = i + 1)
                imem[i] = 32'h00000013;
            $readmemh("program.hex", imem);
        end
        assign instruction = imem[pc[9:2]];
    end
endgenerate
endmodule
