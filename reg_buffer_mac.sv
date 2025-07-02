module reg_buffer_mac #(
    parameter IN_CHANNELS  = 4,
    parameter IMAGE_WIDTH  = 128,  
    parameter KERNEL_SIZE  = 3,    
    parameter DATA_WIDTH   = 16,
    parameter PADDING      = 1,
    parameter STRIDE       = 1,
    parameter MAX_POOL     = 0
)(
    input  logic clk,
    input  logic rst, start_lb,
    input  logic signed [DATA_WIDTH-1:0] window_out_lb [KERNEL_SIZE][KERNEL_SIZE],
    //input  logic frame_end_flag_lb, // Raised when window reaches end of padded frame
    input logic [$clog2(IN_CHANNELS)-1:0] output_channel_in,
    output logic [$clog2(IN_CHANNELS)-1:0] output_channel_out,
    output logic start_mac,

    output logic signed [DATA_WIDTH-1:0] window_out_mac [KERNEL_SIZE][KERNEL_SIZE]
);

integer i, j, k;

always @(posedge clk) begin 
    if (rst) begin
        
            for (j = 0; j < KERNEL_SIZE; j = j + 1) begin
                for (k = 0; k < KERNEL_SIZE ; k = k + 1) begin
                    window_out_mac[j][k] <= 0;
                end
            end
        
        start_mac <= 0;
        output_channel_out<=0;
        
    end 
    else begin
        
            for (j = 0; j < KERNEL_SIZE; j = j + 1) begin
                for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
                    window_out_mac[j][k] <= window_out_lb[j][k];
                end
            end
        
        start_mac <= start_lb;
        output_channel_out<=output_channel_in;
  
    end
end

endmodule
