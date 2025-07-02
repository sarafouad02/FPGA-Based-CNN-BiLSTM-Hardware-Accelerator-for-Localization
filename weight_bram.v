//==============================================================================
// Weight BRAM Module
//==============================================================================
module bram #(
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 4096,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter MEM_FILE = "weights.mem"
)(
    input wire clk,
    input wire rst_n,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire rd_en,
    output reg [DATA_WIDTH-1:0] dout,
    output reg valid
    
);

    reg [DATA_WIDTH-1:0] memory [DEPTH-1:0];


    // Synthesis-compatible memory initialization
    initial begin
        $readmemh(MEM_FILE, memory);
    end

    // Read operation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= 0;
            valid <= 1'b0;
        end else if (rd_en) begin
            dout <= memory[addr];
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end

endmodule


/*module weight_bram #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 12,
    parameter DEPTH = 4096
)(
    input wire clk,
    input wire rst_n,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire rd_en,
    output reg [DATA_WIDTH-1:0] dout,
    output reg valid,
    
    // Optional write interface for weight loading
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] din
);

    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    integer i;
    // Initialize weights (can be loaded from file or through write interface)
    initial begin
        // Initialize to small random values or load from file
        
        for (i = 0; i < DEPTH; i = i + 1) begin
            memory[i] = $random % 256 - 128; // Random values between -128 to 127
        end
    end

    // Write operation
    always @(posedge clk) begin
        if (wr_en) begin
            memory[addr] <= din;
        end
    end

    // Read operation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= 0;
            valid <= 1'b0;
        end else if (rd_en) begin
            dout <= memory[addr];
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end

endmodule*/