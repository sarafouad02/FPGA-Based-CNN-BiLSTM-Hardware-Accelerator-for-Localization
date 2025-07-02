module reg_mac_bnfifo # (
	parameter IN_CHANNELS  = 4,
    parameter IMAGE_WIDTH  = 128,  
    parameter KERNEL_SIZE  = 3,    
    parameter DATA_WIDTH   = 16,
    parameter PADDING      = 1,
    parameter STRIDE       = 1,
    parameter MAX_POOL     = 0
)(
    input  logic clk,
    input  logic rst,
    input logic signed [DATA_WIDTH-1:0] mac_output_mac,
    input logic bnfifo_wr, bnfifo_rd,


    output logic bnfifo_wr_out, bnfifo_rd_out,
    output logic signed [DATA_WIDTH-1:0] mac_output_bnfifo
);

integer i, j, k;

always @(posedge clk) begin 
    if (rst) begin
            bnfifo_wr_out<=0;
        	mac_output_bnfifo<=0;
            bnfifo_rd_out<=0;
    end 
    else begin
            bnfifo_wr_out<=bnfifo_wr;
            bnfifo_rd_out<=bnfifo_rd;
        	mac_output_bnfifo<=mac_output_mac;
          
       end
end

endmodule
