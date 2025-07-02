//==============================================================================
// FIFO Buffer
//==============================================================================
module fifo #(
    parameter DATA_WIDTH = 16,
    parameter FIFO_DEPTH = 512,
    parameter ADDR_WIDTH = $clog2(FIFO_DEPTH)
)(
    input wire clk,
    input wire rst_n,
    
    // Write interface
    input wire [DATA_WIDTH-1:0] wr_data,
    input wire wr_en,
    output wire full,
    
    // Read interface
    input wire rd_en,
    output reg [DATA_WIDTH-1:0] rd_data,
    output reg rd_valid,
    output wire empty
);

    // FIFO memory
    reg [DATA_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];

    // Read and write pointers (one extra MSB to differentiate full/empty)
    reg [ADDR_WIDTH:0] wr_ptr, rd_ptr;

    // Address extraction from pointers (removing MSB)
    wire [ADDR_WIDTH-1:0] wr_addr = wr_ptr[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr = rd_ptr[ADDR_WIDTH-1:0];

    // Full and empty detection
    assign full = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) && 
                  (wr_addr == rd_addr);
    assign empty = (wr_ptr == rd_ptr);

    // Write logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            fifo_mem[wr_addr] <= wr_data;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // Read logic + rd_valid generation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            rd_data <= 0;
            rd_valid <= 0;
        end else if (rd_en && !empty) begin
            rd_data <= fifo_mem[rd_addr];
            rd_ptr <= rd_ptr + 1;
            rd_valid <= 1;
        end else begin
            rd_valid <= 0;
        end
    end

endmodule
