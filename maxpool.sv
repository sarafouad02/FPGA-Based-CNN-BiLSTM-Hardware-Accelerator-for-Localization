module max_pool_2x2 #(
    parameter DATA_WIDTH      = 16,  // Bit width of each pixel
    parameter MAX_POOL_KERNEL = 2    // Max pooling kernel size (2x2)
)(
    input  logic clk,
    input  logic rst,
    input logic  enable,
    input  logic  [DATA_WIDTH-1:0] maxpool_fifo_out [MAX_POOL_KERNEL][MAX_POOL_KERNEL], 
    output logic signed [DATA_WIDTH-1:0] pooled_pixel,
    output logic maxpool_done
);

    always_ff @(posedge clk) begin
        if (rst) begin
            
                pooled_pixel <= 0;
                maxpool_done <= 0;
            
        end else if (enable) begin
                // Compute max value within each 2x2 window
                pooled_pixel <= 
                    (maxpool_fifo_out[0][0] > maxpool_fifo_out[0][1]) ? 
                        ((maxpool_fifo_out[0][0] > maxpool_fifo_out[1][0]) ? 
                            ((maxpool_fifo_out[0][0] > maxpool_fifo_out[1][1]) ? 
                                maxpool_fifo_out[0][0] : maxpool_fifo_out[1][1]) 
                            : (maxpool_fifo_out[1][0] > maxpool_fifo_out[1][1] ? 
                                maxpool_fifo_out[1][0] : maxpool_fifo_out[1][1])
                        ) 
                        : ((maxpool_fifo_out[0][1] > maxpool_fifo_out[1][0]) ? 
                            ((maxpool_fifo_out[0][1] > maxpool_fifo_out[1][1]) ? 
                                maxpool_fifo_out[0][1] : maxpool_fifo_out[1][1]) 
                            : (maxpool_fifo_out[1][0] > maxpool_fifo_out[1][1] ? 
                                maxpool_fifo_out[1][0] : maxpool_fifo_out[1][1])
                        );

                maxpool_done <= 1;
        end else begin
            pooled_pixel <= 0;
            maxpool_done <= 0;
        end
    end

endmodule
