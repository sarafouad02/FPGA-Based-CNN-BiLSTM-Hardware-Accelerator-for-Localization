module reg_bnfifo_bn #(
    parameter DATA_WIDTH = 16
)(
    input  logic              clk,
    input  logic              rst,
    input  logic signed  [DATA_WIDTH-1:0] data_in, bn_mean_reg_in, bn_std_reg_in, bn_gamma_reg_in, bn_beta_reg_in,
    input  logic                  bn_en_in, rd_en_in, bn_fifo_empty_in,bn_fifo_full_in,
    output logic                  bn_en_out, rd_en_out, bn_fifo_empty_out, bn_fifo_full_out,
    output logic signed [DATA_WIDTH-1:0] data_out, bn_mean_reg_out, bn_std_reg_out, bn_gamma_reg_out, bn_beta_reg_out
);
    always_ff @(posedge clk) begin
        if(rst) begin
        	data_out <= '0;
        	bn_en_out <= 0;
        	rd_en_out <= 0;
            bn_fifo_empty_out <= 1; // empty flag needs to start at 1 for the batch norm
            bn_fifo_full_out <= 0;
            bn_mean_reg_out <= 0;
            bn_std_reg_out <= 0;
            bn_gamma_reg_out <= 0;
            bn_beta_reg_out <= 0;
        end else begin
        	data_out <= data_in;
        	bn_en_out <= bn_en_in;
        	rd_en_out <= rd_en_in;
            bn_fifo_empty_out <= bn_fifo_empty_in;
            bn_fifo_full_out <= bn_fifo_full_in;
            bn_mean_reg_out <= bn_mean_reg_in;
            bn_std_reg_out <= bn_std_reg_in;
            bn_gamma_reg_out <= bn_gamma_reg_in;
            bn_beta_reg_out <= bn_beta_reg_in;
        end
    end
endmodule
