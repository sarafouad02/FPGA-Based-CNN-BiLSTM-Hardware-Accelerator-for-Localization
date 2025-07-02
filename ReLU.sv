module relu #(
    parameter DATA_WIDTH   = 16
)(
    input  logic signed [DATA_WIDTH-1:0] input_data,
    input enable,
    output logic signed [DATA_WIDTH-1:0] output_data,
    output logic done
);

    always_comb begin
        if(enable) begin
            output_data = (input_data > 0) ? input_data : 0;
            done = 1;
        end 
        else begin
            output_data = 0;
            done = 0;
        end
        
    end

endmodule
