//==============================================================================
// Updated Pipelined FC Network with Separate Pipeline Controller
//==============================================================================
module pipelined_fc_network #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_SZ = 12,
    
    // Layer 1 parameters
    parameter L1_INPUT_SIZE = 6,
    parameter L1_OUTPUT_SIZE = 100,
    parameter L1_WEIGHT_DEPTH = L1_INPUT_SIZE*L1_OUTPUT_SIZE,  
    parameter L1_WEIGHT_FILE = "layer1_weights.mem",
    parameter L1_BIAS_FILE = "layer1_biases.mem",
    
    // Layer 2 parameters  
    parameter L2_INPUT_SIZE = L1_OUTPUT_SIZE,
    parameter L2_OUTPUT_SIZE = 50,
    parameter L2_WEIGHT_DEPTH = L2_INPUT_SIZE*L2_OUTPUT_SIZE,   
    parameter L2_WEIGHT_FILE = "layer2_weights.mem",
    parameter L2_BIAS_FILE = "layer2_biases.mem",
    
    // Layer 3 parameters
    parameter L3_INPUT_SIZE = L2_OUTPUT_SIZE,
    parameter L3_OUTPUT_SIZE = 3,       
    parameter L3_WEIGHT_DEPTH = L3_INPUT_SIZE*L3_OUTPUT_SIZE,    
    parameter L3_WEIGHT_FILE = "layer3_weights.mem",
    parameter L3_BIAS_FILE = "layer3_biases.mem",
    
    // FIFO parameters
    parameter INPUT_FIFO_DEPTH = 32,
    parameter FIFO1_DEPTH = 256,
    parameter FIFO2_DEPTH = 128,
    parameter OUTPUT_FIFO_DEPTH = 16,
    
    // Activation control
    parameter L1_ENABLE_ACTIVATION = 1,
    parameter L2_ENABLE_ACTIVATION = 1,
    parameter L3_ENABLE_ACTIVATION = 0
)(
    input wire clk,
    input wire rst_n,
    
    // Network control
    input wire network_enable,
    input wire pipeline_reset,
    input wire l1_activation_enable,
    input wire l2_activation_enable,
    input wire l3_activation_enable,
    
    // Input interface
    input wire signed [DATA_WIDTH-1:0] input_data,
    input wire input_valid,
    output wire input_ready,
    
    // Output interface
    output wire signed [DATA_WIDTH-1:0] output_data,
    output wire output_valid,
    input wire output_ready,
    
    // Status outputs
    output wire l1_busy,
    output wire l2_busy, 
    output wire l3_busy,
    output wire pipeline_busy,
    output wire pipeline_stalled,
    output wire pipeline_ready
);

    // Calculated parameters
    localparam NUM_LAYERS = 3;
    localparam L1_WEIGHT_ADDR_WIDTH = $clog2(L1_WEIGHT_DEPTH);
    localparam L2_WEIGHT_ADDR_WIDTH = $clog2(L2_WEIGHT_DEPTH);
    localparam L3_WEIGHT_ADDR_WIDTH = $clog2(L3_WEIGHT_DEPTH);

    // Pipeline controller signals
    wire [NUM_LAYERS-1:0] layer_start;
    wire [NUM_LAYERS-1:0] layer_busy_vec;
    wire [NUM_LAYERS-1:0] layer_done_vec;
    wire [NUM_LAYERS-2:0] inter_fifo_empty_vec;
    
    // FIFO signals
    wire input_fifo_full, input_fifo_empty;
    wire signed [DATA_WIDTH-1:0] input_fifo_data;
    wire input_fifo_rd_en, input_fifo_rd_valid;
    
    wire fifo1_full, fifo1_empty;
    wire signed [DATA_WIDTH-1:0] fifo1_data;
    wire fifo1_rd_en, fifo1_rd_valid;
    
    wire fifo2_full, fifo2_empty;
    wire signed [DATA_WIDTH-1:0] fifo2_data;
    wire fifo2_rd_en, fifo2_rd_valid;
    
    wire output_fifo_full, output_fifo_empty;
    wire signed [DATA_WIDTH-1:0] output_fifo_wr_data;
    wire output_fifo_rd_en, output_fifo_rd_valid;

    // Layer control signals
    wire l1_start, l1_done;
    wire l2_start, l2_done;
    wire l3_start, l3_done;
    
    // Layer output signals
    wire signed [DATA_WIDTH-1:0] l1_output_data, l2_output_data, l3_output_data;
    wire l1_output_wr_en, l2_output_wr_en, l3_output_wr_en;

    // Pipeline controller signal mapping
    assign layer_busy_vec = {l3_busy, l2_busy, l1_busy};
    assign layer_done_vec = {l3_done, l2_done, l1_done};
    assign inter_fifo_empty_vec = {fifo2_empty, fifo1_empty};
    
    assign l1_start = layer_start[0];
    assign l2_start = layer_start[1];
    assign l3_start = layer_start[2];

    //==========================================================================
    // Pipeline Controller Instance
    //==========================================================================
    pipeline_controller #(
        .NUM_LAYERS(NUM_LAYERS),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_pipeline_controller (
        .clk(clk),
        .rst_n(rst_n),
        .network_enable(network_enable),
        .pipeline_reset(pipeline_reset),
        .layer_busy(layer_busy_vec),
        .layer_done(layer_done_vec),
        .input_fifo_empty(input_fifo_empty),
        .inter_fifo_empty(inter_fifo_empty_vec),
        .output_fifo_full(output_fifo_full),
        .layer_start(layer_start),
        .pipeline_busy(pipeline_busy),
        .pipeline_stalled(pipeline_stalled),
        .pipeline_ready(pipeline_ready)
    );

    //==========================================================================
    // Input FIFO - Buffers incoming data for Layer 1
    //==========================================================================
    fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(INPUT_FIFO_DEPTH)
    ) u_input_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_data(input_data),
        .wr_en(input_valid && !input_fifo_full),
        .full(input_fifo_full),
        .rd_en(input_fifo_rd_en),
        .rd_data(input_fifo_data),
        .rd_valid(input_fifo_rd_valid),
        .empty(input_fifo_empty)
    );

    //==========================================================================
    // Inter-layer FIFO 1 - Between Layer 1 and Layer 2
    //==========================================================================
    fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO1_DEPTH)
    ) u_fifo1 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_data(l1_output_data),
        .wr_en(l1_output_wr_en && !fifo1_full),
        .full(fifo1_full),
        .rd_en(fifo1_rd_en),
        .rd_data(fifo1_data),
        .rd_valid(fifo1_rd_valid),
        .empty(fifo1_empty)
    );

    //==========================================================================
    // Inter-layer FIFO 2 - Between Layer 2 and Layer 3
    //==========================================================================
    fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO2_DEPTH)
    ) u_fifo2 (
        .clk(clk),
        .rst_n(rst_n),
        .wr_data(l2_output_data),
        .wr_en(l2_output_wr_en && !fifo2_full),
        .full(fifo2_full),
        .rd_en(fifo2_rd_en),
        .rd_data(fifo2_data),
        .rd_valid(fifo2_rd_valid),
        .empty(fifo2_empty)
    );

    //==========================================================================
    // Output FIFO - Buffers final output data
    //==========================================================================
    fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(OUTPUT_FIFO_DEPTH)
    ) u_output_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_data(l3_output_data),
        .wr_en(l3_output_wr_en && !output_fifo_full),
        .full(output_fifo_full),
        .rd_en(output_fifo_rd_en),
        .rd_data(output_data),
        .rd_valid(output_valid),
        .empty(output_fifo_empty)
    );

    //==========================================================================
    // Layer 1 - First fully connected layer
    //==========================================================================
    fc_layer_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .INPUT_SIZE(L1_INPUT_SIZE),
        .OUTPUT_SIZE(L1_OUTPUT_SIZE),
        .WEIGHT_DEPTH(L1_WEIGHT_DEPTH),
        .WEIGHT_ADDR_WIDTH(L1_WEIGHT_ADDR_WIDTH),
        .WEIGHT_MEM_FILE(L1_WEIGHT_FILE),
        .ENABLE_ACTIVATION(L1_ENABLE_ACTIVATION), 
        .FRAC_SZ(FRAC_SZ), 
        .BIAS_DEPTH(L1_OUTPUT_SIZE),
        .BIAS_MEM_FILE(L1_BIAS_FILE)
    ) u_layer1 (
        .clk(clk),
        .rst_n(rst_n),
        .start(l1_start),
        .activation_enable_runtime(l1_activation_enable),
        .done(l1_done),
        .busy(l1_busy),
        .input_empty(input_fifo_empty),
        .input_data_valid(input_fifo_rd_valid),
        .input_fifo_data(input_fifo_data),
        .input_rd_en(input_fifo_rd_en),
        .output_full(fifo1_full),
        .output_wr_en(l1_output_wr_en),
        .controller_output_data(l1_output_data)
    );

    //==========================================================================
    // Layer 2 - Second fully connected layer
    //==========================================================================
    fc_layer_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .INPUT_SIZE(L2_INPUT_SIZE),
        .OUTPUT_SIZE(L2_OUTPUT_SIZE),
        .WEIGHT_DEPTH(L2_WEIGHT_DEPTH),
        .WEIGHT_ADDR_WIDTH(L2_WEIGHT_ADDR_WIDTH),
        .WEIGHT_MEM_FILE(L2_WEIGHT_FILE),
        .ENABLE_ACTIVATION(L2_ENABLE_ACTIVATION),
        .FRAC_SZ(FRAC_SZ), 
        .BIAS_DEPTH(L2_OUTPUT_SIZE), 
        .BIAS_MEM_FILE(L2_BIAS_FILE)
    ) u_layer2 (
        .clk(clk),
        .rst_n(rst_n),
        .start(l2_start),
        .activation_enable_runtime(l2_activation_enable),
        .done(l2_done),
        .busy(l2_busy),
        .input_empty(fifo1_empty),
        .input_data_valid(fifo1_rd_valid),
        .input_fifo_data(fifo1_data),
        .input_rd_en(fifo1_rd_en),
        .output_full(fifo2_full),
        .output_wr_en(l2_output_wr_en),
        .controller_output_data(l2_output_data)
    );

    //==========================================================================
    // Layer 3 - Third fully connected layer
    //==========================================================================
    fc_layer_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .INPUT_SIZE(L3_INPUT_SIZE),
        .OUTPUT_SIZE(L3_OUTPUT_SIZE),
        .WEIGHT_DEPTH(L3_WEIGHT_DEPTH),
        .WEIGHT_ADDR_WIDTH(L3_WEIGHT_ADDR_WIDTH),
        .WEIGHT_MEM_FILE(L3_WEIGHT_FILE),
        .ENABLE_ACTIVATION(L3_ENABLE_ACTIVATION),
        .FRAC_SZ(FRAC_SZ),
        .BIAS_DEPTH(L3_OUTPUT_SIZE), 
        .BIAS_MEM_FILE(L3_BIAS_FILE)
    ) u_layer3 (
        .clk(clk),
        .rst_n(rst_n),
        .start(l3_start),
        .activation_enable_runtime(l3_activation_enable),
        .done(l3_done),
        .busy(l3_busy),
        .input_empty(fifo2_empty),
        .input_data_valid(fifo2_rd_valid),
        .input_fifo_data(fifo2_data),
        .input_rd_en(fifo2_rd_en),
        .output_full(output_fifo_full),
        .output_wr_en(l3_output_wr_en),
        .controller_output_data(l3_output_data)
    );

    //==========================================================================
    // Interface Control
    //==========================================================================
    
    // Input ready: Can accept data when input FIFO is not full
    assign input_ready = !input_fifo_full;
    
    // Output FIFO read enable: Read when output is ready and FIFO has data
    assign output_fifo_rd_en = output_ready && !output_fifo_empty;

endmodule


