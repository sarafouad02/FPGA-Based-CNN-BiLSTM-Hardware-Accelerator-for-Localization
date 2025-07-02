module reg_maxfifo_maxpool# ( 
    parameter KERNEL_SIZE  = 2,    
    parameter DATA_WIDTH   = 16
)(
    input  logic                      clk,
    input  logic                      rst,
    input logic                      maxpool_en_maxfifo,
    // 2x2 window output: first index = row (0 or 1), second index = column (0 or 1)
    input logic [DATA_WIDTH-1:0]     window_maxfifo [KERNEL_SIZE][KERNEL_SIZE],

    output logic                      maxpool_en_maxpool,
    // 2x2 window output: first index = row (0 or 1), second index = column (0 or 1)
    output logic [DATA_WIDTH-1:0]     window_maxpool [KERNEL_SIZE][KERNEL_SIZE]
);

integer i, j, k;

always @(posedge clk) begin 
    if (rst) begin
        
            for (j = 0; j < KERNEL_SIZE; j = j + 1) begin
                for (k = 0; k < KERNEL_SIZE ; k = k + 1) begin
                    window_maxpool[j][k] <= 0;
                end
            end
        

        maxpool_en_maxpool   <= 0;
    end 
    else begin
        
            for (j = 0; j < KERNEL_SIZE; j = j + 1) begin
                for (k = 0; k < KERNEL_SIZE ; k = k + 1) begin
                    window_maxpool[j][k] <= window_maxfifo[j][k];
                end
            end
        
  
        maxpool_en_maxpool   <= maxpool_en_maxfifo;
    end
end

endmodule
