//==============================================================================
// Top-level Fully Connected Layer with Bias Support (Modified)
//==============================================================================
module fc_layer_top #(
    parameter DATA_WIDTH = 16,
    parameter INPUT_SIZE = 12,
    parameter OUTPUT_SIZE = 100,
    parameter WEIGHT_DEPTH = 4096,
    parameter WEIGHT_ADDR_WIDTH = $clog2(WEIGHT_DEPTH),
    parameter BIAS_DEPTH = OUTPUT_SIZE,
    parameter BIAS_ADDR_WIDTH = $clog2(BIAS_DEPTH),
    parameter WEIGHT_MEM_FILE = "weights.mem",
    parameter BIAS_MEM_FILE = "biases.mem",      // New parameter for bias memory file
    parameter ENABLE_ACTIVATION = 1,
    parameter FRAC_SZ = 12
)(
    input wire clk,
    input wire rst_n,
    
    // Control interface
    input wire start,
    input wire activation_enable_runtime,
    output wire done,
    output wire busy,
    
    // Input interface
    input input_empty,
    input input_data_valid,
    input signed [DATA_WIDTH-1:0] input_fifo_data,
    output input_rd_en,

    // Output interface
    input output_full,
    output output_wr_en,
    output signed [DATA_WIDTH-1:0] controller_output_data,
    // Debug interface
    output wire [3:0] debug_state  // Updated width for new states
);

    // Internal signals
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    wire weight_rd_en, weight_valid;
    wire signed [DATA_WIDTH-1:0] weight_data;
    
    // Bias signals (New)
    wire [BIAS_ADDR_WIDTH-1:0] bias_addr;
    wire bias_rd_en, bias_valid;
    wire signed [DATA_WIDTH-1:0] bias_data;
    
    wire mac_enable, mac_acc_clear, mac_valid;
    wire signed [DATA_WIDTH-1:0] mac_a, mac_b;
    wire signed [2*DATA_WIDTH-1:0] mac_result;
    
    wire activation_enable, activation_valid;
    wire signed [2*DATA_WIDTH-1:0] activation_input;
    wire signed [DATA_WIDTH-1:0] activation_output;
    
    // Determine if activation should be used (parameter AND runtime control)
    wire use_activation = ENABLE_ACTIVATION & activation_enable_runtime;

    // Weight BRAM
    bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .DEPTH(WEIGHT_DEPTH),
        .MEM_FILE(WEIGHT_MEM_FILE)
    ) u_weight_bram (
        .clk(clk),
        .rst_n(rst_n),
        .addr(weight_addr),
        .rd_en(weight_rd_en),
        .dout(weight_data),
        .valid(weight_valid)
    );

    // Bias BRAM (New)
    bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(BIAS_ADDR_WIDTH),
        .DEPTH(BIAS_DEPTH),
        .MEM_FILE(BIAS_MEM_FILE)
    ) u_bias_bram (
        .clk(clk),
        .rst_n(rst_n),
        .addr(bias_addr),
        .rd_en(bias_rd_en),
        .dout(bias_data),
        .valid(bias_valid)
    );

    // MAC Unit
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_ACCUMS(INPUT_SIZE)
    ) u_mac_unit (
        .clk(clk),
        .rst_n(rst_n),
        .enable(mac_enable),
        .acc_clear(mac_acc_clear),
        .a(mac_a),
        .b(mac_b),
        .result(mac_result),
        .valid(mac_valid)
    );

    // Activation Function (ReLU) - only instantiated when ENABLE_ACTIVATION=1
    generate
        if (ENABLE_ACTIVATION) begin : gen_activation
            activation_relu #(
                .DATA_WIDTH(DATA_WIDTH),
                .FRAC_SZ(FRAC_SZ)
            ) u_activation (
                .clk(clk),
                .rst_n(rst_n),
                .enable(activation_enable),
                .din(activation_input),
                .dout(activation_output),
                .valid(activation_valid)
            );
        end else begin : gen_no_activation
            assign activation_output = {DATA_WIDTH{1'b0}};
            assign activation_valid = 1'b0;
        end
    endgenerate

    // Controller with bias support (handles all bias logic internally)
    fc_controller #(
        .DATA_WIDTH(DATA_WIDTH),
        .INPUT_SIZE(INPUT_SIZE),
        .OUTPUT_SIZE(OUTPUT_SIZE),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .BIAS_ADDR_WIDTH(BIAS_ADDR_WIDTH),    // New parameter
        .ENABLE_ACTIVATION(ENABLE_ACTIVATION), 
        .FRAC_SZ(FRAC_SZ)
    ) u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .use_activation(use_activation),
        .done(done),
        .busy(busy),
        .input_empty(input_empty),
        .input_data(input_fifo_data),
        .input_valid(input_data_valid),
        .input_rd_en(input_rd_en),
        .weight_addr(weight_addr),
        .weight_rd_en(weight_rd_en),
        .weight_data(weight_data),
        .weight_valid(weight_valid),
        // Bias interface (New)
        .bias_addr(bias_addr),
        .bias_rd_en(bias_rd_en),
        .bias_data(bias_data),
        .bias_valid(bias_valid),
        // MAC interface
        .mac_enable(mac_enable),
        .mac_acc_clear(mac_acc_clear),
        .mac_input_a(mac_a),
        .mac_input_b(mac_b),
        .mac_result(mac_result),
        .mac_valid(mac_valid),
        // Activation interface
        .activation_enable(activation_enable),
        .activation_input(activation_input),
        .activation_output(activation_output),
        .activation_valid(activation_valid),
        // Output interface
        .output_full(output_full),
        .output_data(controller_output_data),
        .output_wr_en(output_wr_en)
    );

    
    // Debug output
    assign debug_state = u_controller.current_state;

endmodule




//==============================================================================
// Top-level Fully Connected Layer with Optional Activation (Simplified)
//==============================================================================
/*module fc_layer_top #(
    parameter DATA_WIDTH = 16,
    parameter INPUT_SIZE = 12,
    parameter OUTPUT_SIZE = 100,
    parameter WEIGHT_DEPTH = 4096,
    parameter WEIGHT_ADDR_WIDTH = $clog2(WEIGHT_DEPTH),
    parameter WEIGHT_MEM_FILE = "weights.mem",
    parameter ENABLE_ACTIVATION = 1 , // 1 = Enable activation, 0 = Bypass activation
    parameter FRAC_SZ = 12
)(
    input wire clk,
    input wire rst_n,
    
    // Control interface
    input wire start,
    input wire activation_enable_runtime,  // Runtime control for activation
    output wire done,
    output wire busy,
    
    // Input interface
    input input_empty,
    input input_data_valid,
    input [DATA_WIDTH-1:0] input_fifo_data,
    output input_rd_en,

    // Output interface
    input output_full,
    output output_wr_en,
    output [DATA_WIDTH-1:0] controller_output_data,
    
    // Debug interface
    //output wire [15:0] debug_input_idx,
    //output wire [15:0] debug_output_idx,
    output wire [2:0] debug_state
);

    // Internal signals
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    wire weight_rd_en, weight_valid;
    wire [DATA_WIDTH-1:0] weight_data;
    
    wire mac_enable, mac_acc_clear, mac_valid;
    wire signed [DATA_WIDTH-1:0] mac_a, mac_b;
    wire signed [2*DATA_WIDTH-1:0] mac_result;
    
    wire activation_enable, activation_valid;
    wire signed [2*DATA_WIDTH-1:0] activation_input;
    wire signed [DATA_WIDTH-1:0] activation_output;
    
    // Determine if activation should be used (parameter AND runtime control)
    wire use_activation = ENABLE_ACTIVATION & activation_enable_runtime;

    // Weight BRAM
    weight_bram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .DEPTH(WEIGHT_DEPTH),
        .MEM_FILE(WEIGHT_MEM_FILE)
    ) u_weight_bram (
        .clk(clk),
        .rst_n(rst_n),
        .addr(weight_addr),
        .rd_en(weight_rd_en),
        .dout(weight_data),
        .valid(weight_valid)
    );

    // MAC Unit
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_ACCUMS(INPUT_SIZE)
    ) u_mac_unit (
        .clk(clk),
        .rst_n(rst_n),
        .enable(mac_enable),
        .acc_clear(mac_acc_clear),
        .a(mac_a),
        .b(mac_b),
        .result(mac_result),
        .valid(mac_valid)
    );

    // Activation Function (ReLU) - only instantiated when ENABLE_ACTIVATION=1
    generate
        if (ENABLE_ACTIVATION) begin : gen_activation
            activation_relu #(
                .DATA_WIDTH(DATA_WIDTH),
                .FRAC_SZ(FRAC_SZ)
            ) u_activation (
                .clk(clk),
                .rst_n(rst_n),
                .enable(activation_enable),
                .din(activation_input),
                .dout(activation_output),
                .valid(activation_valid)
            );
        end else begin : gen_no_activation
            // When activation is disabled at compile time, tie off unused signals
            assign activation_output = {DATA_WIDTH{1'b0}};
            assign activation_valid = 1'b0;
        end
    endgenerate

    // Controller with activation control (handles all bypass logic internally)
    fc_controller #(
        .DATA_WIDTH(DATA_WIDTH),
        .INPUT_SIZE(INPUT_SIZE),
        .OUTPUT_SIZE(OUTPUT_SIZE),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .ENABLE_ACTIVATION(ENABLE_ACTIVATION), 
        .FRAC_SZ(FRAC_SZ)
    ) u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .use_activation(use_activation),
        .done(done),
        .busy(busy),
        .input_empty(input_empty),
        .input_data(input_fifo_data),
        .input_valid(input_data_valid),
        .input_rd_en(input_rd_en),
        .weight_addr(weight_addr),
        .weight_rd_en(weight_rd_en),
        .weight_data(weight_data),
        .weight_valid(weight_valid),
        .mac_enable(mac_enable),
        .mac_acc_clear(mac_acc_clear),
        .mac_input_a(mac_a),
        .mac_input_b(mac_b),
        .mac_result(mac_result),
        .mac_valid(mac_valid),
        .activation_enable(activation_enable),
        .activation_input(activation_input),
        .activation_output(activation_output),
        .activation_valid(activation_valid),
        .output_full(output_full),
        .output_data(controller_output_data),
        .output_wr_en(output_wr_en)
    );

endmodule*/

