module reg_bn_relu # (
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
    input logic signed [DATA_WIDTH-1:0] bn_output_bn,
    input logic relu_en_bn, 
    output logic relu_en_relu, 
    output logic signed [DATA_WIDTH-1:0] bn_output_relu 
);

integer i;

always @(posedge clk) begin 
    if (rst) begin
            relu_en_relu<=0;
        	bn_output_relu<=0;
       
    end 
    else begin
            relu_en_relu<=relu_en_bn;
        	bn_output_relu<=bn_output_bn;
          
       end
end

endmodule
