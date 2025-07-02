module reg_relu_max_fifo# (
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
    input logic signed [DATA_WIDTH-1:0] output_data_relu,
    input logic max_fifo_en_relu,
    output logic signed [DATA_WIDTH-1:0] output_data_max_fifo,
    output logic max_fifo_en_max_fifo

);

integer i;

always @(posedge clk) begin 
    if (rst) begin
    
        	output_data_max_fifo<=0;
            max_fifo_en_max_fifo <= 0;
           
    end 
    else begin
         
        	output_data_max_fifo<=output_data_relu;
            max_fifo_en_max_fifo <= max_fifo_en_relu;
           
       end
end

endmodule