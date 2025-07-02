module buffer #(
    parameter IMAGE_WIDTH = 188,    // Number of entries (one full row)
    parameter DATA_WIDTH  = 16        // Bit-width of each data element
)(
    input  logic                   clk,
    input  logic                   rst_n,  // Active low reset
    input  logic                   wr_en,  // Write enable
    input  logic [DATA_WIDTH-1:0]  din,    // Data input
    input  logic                   rd_en,  // Read enable
    output logic [DATA_WIDTH-1:0]  dout,   // Data output
    output logic                   full,   // FIFO full flag
    output logic                   empty   // FIFO empty flag
);

    // Memory array for one row of IMAGE_WIDTH entries.
    logic [DATA_WIDTH-1:0] mem [0:IMAGE_WIDTH-1];

    // Pointers and counter:
    // Using $clog2 for pointer width; note that count requires one extra bit to count up to IMAGE_WIDTH.
    logic [$clog2(IMAGE_WIDTH)-1:0] wr_ptr, rd_ptr;
    logic [$clog2(IMAGE_WIDTH+1)-1:0] count;

    // Combinational assignments for status flags.
    assign full  = (count == IMAGE_WIDTH);
    assign empty = (count == 0);

    // Synchronous FIFO operation
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Asynchronous reset: Initialize pointers, count and output.
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
            dout   <= '0;
        end
        else begin
            // Write operation: if write enabled and FIFO is not full.
            if (wr_en && !full) begin
                mem[wr_ptr] <= din;
                // Wrap-around logic for pointer:
                if (wr_ptr == IMAGE_WIDTH - 1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1;
            end

            // Read operation: if read enabled and FIFO is not empty.
            if (rd_en && !empty) begin
                dout <= mem[rd_ptr];
                if (rd_ptr == IMAGE_WIDTH - 1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1;
            end

            // Update the counter based on simultaneous or individual operations.
            // If both read and write occur at the same time, the count remains unchanged.
            case ({(wr_en && !full), (rd_en && !empty)})
                2'b10: count <= count + 1; // Write only.
                2'b01: count <= count - 1; // Read only.
                // 2'b11: no net change.
                default: count <= count;
            endcase
        end
    end

endmodule