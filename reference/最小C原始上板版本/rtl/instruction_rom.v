module instruction_rom #(
    parameter C_PROGRAM = 0,
    parameter BOARD_DEMO = 0,
    parameter integer BOARD_DEMO_DELAY_COUNT = 6_750_000
)(
    input wire[31:0] pc,//输入指令地址
    output wire[31:0] instruction//输出指令
);

generate
    if (C_PROGRAM) begin : g_c_program
        // software/build_c_demo.py 从 ELF .text 生成；上板不依赖外部 hex 路径。
        reg [31:0] c_instruction;
        always @(*) begin
            case (pc[9:2])
    // BEGIN GENERATED C ROM
                8'd0: c_instruction = 32'h00001197;
                8'd1: c_instruction = 32'h80018193;
                8'd2: c_instruction = 32'h00000117;
                8'd3: c_instruction = 32'h3f810113;
                8'd4: c_instruction = 32'h00000213;
                8'd5: c_instruction = 32'h00000297;
                8'd6: c_instruction = 32'h17c28293;
                8'd7: c_instruction = 32'h00000317;
                8'd8: c_instruction = 32'hfe430313;
                8'd9: c_instruction = 32'h00000397;
                8'd10: c_instruction = 32'hff438393;
                8'd11: c_instruction = 32'h00737c63;
                8'd12: c_instruction = 32'h0002ae03;
                8'd13: c_instruction = 32'h01c32023;
                8'd14: c_instruction = 32'h00428293;
                8'd15: c_instruction = 32'h00430313;
                8'd16: c_instruction = 32'hfedff06f;
                8'd17: c_instruction = 32'h00000297;
                8'd18: c_instruction = 32'hfd428293;
                8'd19: c_instruction = 32'h00000317;
                8'd20: c_instruction = 32'hfd430313;
                8'd21: c_instruction = 32'h0062f863;
                8'd22: c_instruction = 32'h0002a023;
                8'd23: c_instruction = 32'h00428293;
                8'd24: c_instruction = 32'hff5ff06f;
                8'd25: c_instruction = 32'h00000513;
                8'd26: c_instruction = 32'h00000593;
                8'd27: c_instruction = 32'h00000097;
                8'd28: c_instruction = 32'h030080e7;
                8'd29: c_instruction = 32'h0000006f;
                8'd30: c_instruction = 32'hff010113;
                8'd31: c_instruction = 32'h00a12423;
                8'd32: c_instruction = 32'h00100793;
                8'd33: c_instruction = 32'h00f12623;
                8'd34: c_instruction = 32'h00812503;
                8'd35: c_instruction = 32'h00c12783;
                8'd36: c_instruction = 32'h01010113;
                8'd37: c_instruction = 32'h00f50533;
                8'd38: c_instruction = 32'h00008067;
                8'd39: c_instruction = 32'hff010113;
                8'd40: c_instruction = 32'h00912223;
                8'd41: c_instruction = 32'h000004b7;
                8'd42: c_instruction = 32'h0144a703;
                8'd43: c_instruction = 32'h00112623;
                8'd44: c_instruction = 32'h00812423;
                8'd45: c_instruction = 32'h01212023;
                8'd46: c_instruction = 32'h00500793;
                8'd47: c_instruction = 32'h08f71a63;
                8'd48: c_instruction = 32'h00000437;
                8'd49: c_instruction = 32'h01c42783;
                8'd50: c_instruction = 32'h08079463;
                8'd51: c_instruction = 32'h00000937;
                8'd52: c_instruction = 32'h01892783;
                8'd53: c_instruction = 32'h06079e63;
                8'd54: c_instruction = 32'h0144a503;
                8'd55: c_instruction = 32'h00000097;
                8'd56: c_instruction = 32'hf9c080e7;
                8'd57: c_instruction = 32'h00a42e23;
                8'd58: c_instruction = 32'h01c42703;
                8'd59: c_instruction = 32'h00600793;
                8'd60: c_instruction = 32'h06f71063;
                8'd61: c_instruction = 32'h06300793;
                8'd62: c_instruction = 32'h00f4aa23;
                8'd63: c_instruction = 32'h00100793;
                8'd64: c_instruction = 32'h00f92c23;
                8'd65: c_instruction = 32'h01c42703;
                8'd66: c_instruction = 32'h100007b7;
                8'd67: c_instruction = 32'h00e7a023;
                8'd68: c_instruction = 32'h000007b7;
                8'd69: c_instruction = 32'h10000737;
                8'd70: c_instruction = 32'h00078793;
                8'd71: c_instruction = 32'h01070713;
                8'd72: c_instruction = 32'h0007c683;
                8'd73: c_instruction = 32'h02069063;
                8'd74: c_instruction = 32'h00000513;
                8'd75: c_instruction = 32'h00c12083;
                8'd76: c_instruction = 32'h00812403;
                8'd77: c_instruction = 32'h00412483;
                8'd78: c_instruction = 32'h00012903;
                8'd79: c_instruction = 32'h01010113;
                8'd80: c_instruction = 32'h00008067;
                8'd81: c_instruction = 32'h00178793;
                8'd82: c_instruction = 32'h00d70023;
                8'd83: c_instruction = 32'hfd5ff06f;
                8'd84: c_instruction = 32'h100007b7;
                8'd85: c_instruction = 32'h08000713;
                8'd86: c_instruction = 32'h00e7a023;
                8'd87: c_instruction = 32'h000007b7;
                8'd88: c_instruction = 32'h10000737;
                8'd89: c_instruction = 32'h00c78793;
                8'd90: c_instruction = 32'h01070713;
                8'd91: c_instruction = 32'h0007c683;
                8'd92: c_instruction = 32'h00069663;
                8'd93: c_instruction = 32'h00100513;
                8'd94: c_instruction = 32'hfb5ff06f;
                8'd95: c_instruction = 32'h00178793;
                8'd96: c_instruction = 32'h00d70023;
                8'd97: c_instruction = 32'hfe9ff06f;
    // END GENERATED C ROM
                default: c_instruction = 32'h00000013;
            endcase
        end
        assign instruction = c_instruction;
    end else if (BOARD_DEMO) begin : g_board_demo
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
