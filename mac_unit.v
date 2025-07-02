//==============================================================================
// MAC (Multiply-Accumulate) Unit with Neuron Completion Detection
//==============================================================================
module mac_unit #(
    parameter DATA_WIDTH = 16,
    parameter NUM_ACCUMS = 128  // Number of accumulations per neuron
)(
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire acc_clear,
    input wire signed [DATA_WIDTH-1:0] a,      // Input data
    input wire signed [DATA_WIDTH-1:0] b,      // Weight
    output wire signed [2*DATA_WIDTH-1:0] result,
    output wire valid
);

    // Internal registers
    reg signed [2*DATA_WIDTH-1:0] mult_result;
    reg signed [2*DATA_WIDTH-1:0] accumulator;
    reg valid_reg;
    reg enable_d1;  // Delayed enable for pipeline timing
    reg [$clog2(NUM_ACCUMS):0] accum_counter;  // Counter for accumulations
    
    // Pipeline the enable signal for proper timing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_d1 <= 1'b0;
        end else begin
            enable_d1 <= enable;
        end
    end
    
    // Multiplication stage - combinatorial for this cycle, registered next cycle
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_result <= 0;
        end else if (enable) begin
            mult_result <= a * b;  // Capture multiplication result
        end
    end
    
    // Accumulation counter - tracks number of accumulations performed
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_counter <= 0;
        end else if (acc_clear) begin
            accum_counter <= 0;
        end else if (enable_d1) begin
            if (accum_counter == NUM_ACCUMS - 1) begin
                accum_counter <= 0;  // Reset counter when neuron is complete
            end else begin
                accum_counter <= accum_counter + 1;
            end
        end
    end
    
    // Accumulation stage - uses previous cycle's multiplication result
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 0;
        end else if (acc_clear) begin
            accumulator <= 0;
        end else if (enable_d1) begin  // Use delayed enable for accumulation
            accumulator <= accumulator + mult_result;
        end
    end
    
    // Valid signal generation - asserted when all accumulations for neuron are done
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_reg <= 1'b0;
        end else if (acc_clear) begin
            valid_reg <= 1'b0;  // Clear valid immediately when accumulator is cleared
        end else if (enable_d1 && (accum_counter == NUM_ACCUMS - 1)) begin
            valid_reg <= 1'b1;  // Assert valid when final accumulation completes
        end else if (valid_reg) begin
            valid_reg <= 1'b0;  // Clear valid after one cycle (pulse)
        end
    end
    
    assign result = accumulator;
    assign valid = valid_reg;

endmodule


/*module mac_unit #(
    parameter DATA_WIDTH = 16
)(
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire acc_clear,
    input wire signed [DATA_WIDTH-1:0] a,      // Input data
    input wire signed [DATA_WIDTH-1:0] b,      // Weight
    output wire signed [2*DATA_WIDTH-1:0] result,
    output wire valid
);
    // Internal registers
    reg signed [2*DATA_WIDTH-1:0] mult_result;
    reg signed [2*DATA_WIDTH-1:0] accumulator;
    reg valid_reg;
    reg enable_d1;  // Delayed enable for pipeline timing
    
    // Pipeline the enable signal for proper timing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_d1 <= 1'b0;
        end else begin
            enable_d1 <= enable;
        end
    end
    
    // Multiplication stage - combinatorial for this cycle, registered next cycle
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_result <= 0;
        end else if (enable) begin
            mult_result <= a * b;  // Capture multiplication result
        end
    end
    
    // Accumulation stage - uses previous cycle's multiplication result
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 0;
        end else if (acc_clear) begin
            accumulator <= 0;
        end else if (enable_d1) begin  // Use delayed enable for accumulation
            accumulator <= accumulator + mult_result;
        end 
       
    end

     // Valid signal generation - asserted when accumulation completes
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_reg <= 1'b0;
        end else if (acc_clear) begin
            valid_reg <= 1'b0;  // Clear valid immediately when accumulator is cleared
        end else begin  // Valid asserted in cycle 2 when accumulation happens
            valid_reg <= enable_d1;
        end
    end
    
    assign result = accumulator;
    assign valid = valid_reg;
endmodule*/











