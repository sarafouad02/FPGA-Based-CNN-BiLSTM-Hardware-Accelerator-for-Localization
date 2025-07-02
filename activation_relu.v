//==============================================================================
// Activation Function Module (ReLU)
//==============================================================================
module activation_relu #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_SZ = 12
)(
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire signed [2*DATA_WIDTH-1:0] din,
    output wire signed [DATA_WIDTH-1:0] dout,
    output reg valid
);

    reg signed [2*DATA_WIDTH-1:0] dout_reg ;
    localparam signed [2*DATA_WIDTH-1:0] SAT_POS = ((1 << (DATA_WIDTH-FRAC_SZ-1)) - 1) << FRAC_SZ;  // +7

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_reg <= 0;
            valid <= 1'b0;
        end else if (enable) begin
            dout_reg <= (din > 0) ? din : 0;
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end

     assign dout = (dout_reg>SAT_POS) ? SAT_POS[DATA_WIDTH-1:0] : dout_reg[DATA_WIDTH-1:0] ;

endmodule