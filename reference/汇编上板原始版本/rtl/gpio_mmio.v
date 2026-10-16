module gpio_mmio (
    input wire clk,
    input wire reset,

    //CPU访存接口
    input wire mem_valid,
    input wire mem_write,
    input wire[3:0] mem_wstrb,
    input wire[31:0] mem_addr,
    input wire[31:0] mem_wdata,

    output reg mem_ready,
    output reg[31:0] mem_rdata,

    input wire[7:0] gpio_in,
    output wire[7:0] gpio_out
);

localparam GPIO_OUT_ADDR = 32'h1000_0000;
localparam GPIO_IN_ADDR  = 32'h1000_0004;

localparam IDLE = 1'b0;
localparam RESP = 1'b1;


reg state;
reg [7:0] gpio_out_reg;

assign gpio_out = gpio_out_reg;

always@(posedge clk)begin
    if(reset)begin
        state <= IDLE;
        mem_ready <= 1'b0;
        mem_rdata <= 32'b0;
        gpio_out_reg <= 8'b0;
    end
    else begin
        case(state)
            IDLE:begin
                mem_ready<=1'b0;
                if(mem_valid)begin
                    case(mem_addr[31:2])
                        GPIO_OUT_ADDR[31:2]:begin
                            mem_rdata <= {24'b0, gpio_out_reg};

                            if (mem_write && mem_wstrb[0])
                                gpio_out_reg <= mem_wdata[7:0];
                        end
                        GPIO_IN_ADDR[31:2]:begin
                            mem_rdata <= {24'b0, gpio_in};
                        end
                        default:begin
                            mem_rdata<=32'b0;
                        end
                    endcase
                    mem_ready <= 1'b1;
                    state     <= RESP;
                end               
            end
            RESP:begin
                mem_ready <= 1'b0;
                state     <= IDLE;
            end
            default:begin
                mem_ready <= 1'b0;
                state     <= IDLE;
            end
        endcase
    end
end
endmodule