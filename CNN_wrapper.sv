module CNN_wrapper #(
	parameter DATA_WIDTH = 16,
    
    // Layer 1 parameters
    parameter L1_INPUT_SIZE = 6,
    parameter L1_OUTPUT_SIZE = 100,
    parameter L1_WEIGHT_DEPTH = L1_INPUT_SIZE*L1_OUTPUT_SIZE,  
    parameter L1_WEIGHT_FILE = "fc1_weight.mem",
    parameter L1_BIAS_FILE = "fc1_bias.mem",
    
    // Layer 2 parameters  
    parameter L2_INPUT_SIZE = L1_OUTPUT_SIZE,
    parameter L2_OUTPUT_SIZE = 50,
    parameter L2_WEIGHT_DEPTH = L2_INPUT_SIZE*L2_OUTPUT_SIZE,   
    parameter L2_WEIGHT_FILE = "fc2_weight.mem",
    parameter L2_BIAS_FILE = "fc2_bias.mem",

    
    // Layer 3 parameters
    parameter L3_INPUT_SIZE = L2_OUTPUT_SIZE,
    parameter L3_OUTPUT_SIZE = 3,       
    parameter L3_WEIGHT_DEPTH = L3_INPUT_SIZE*L3_OUTPUT_SIZE,    
    parameter L3_WEIGHT_FILE = "fc3_weight.mem",
    parameter L3_BIAS_FILE = "fc3_bias.mem",
    
    // FIFO parameters
    parameter INPUT_FIFO_DEPTH = 32,
    parameter FIFO1_DEPTH = 256,
    parameter FIFO2_DEPTH = 128,
    parameter OUTPUT_FIFO_DEPTH = 16,
    
    // Activation control
    parameter L1_ENABLE_ACTIVATION = 1,
    parameter L2_ENABLE_ACTIVATION = 1,
    parameter L3_ENABLE_ACTIVATION = 0,


    parameter KERNEL_SIZE  = 3,
    parameter STRIDE       = 1,
    parameter PADDING      = 1,
    parameter MAX_POOL_KERNEL = 2,
    parameter FRAC_SZ = 12,
    parameter IMAGE_WIDTH     = 64,
    parameter IMAGE_HEIGHT    = 64,
    parameter NUM_IMAGES      = 4,
    parameter TOP_BOTTOM_PADDING = 1,
    parameter IN_CHANNELS     =4,
    parameter OUT_CHANNELS    = 4
	)(
	input  wire clk,
    input  wire rst_n,

    // CONV layers interface 
    input  wire ENABLE_PE,
    input  wire [DATA_WIDTH-1:0] bram_image_in,
    input  wire write_pixel_ready,
    output wire bram_en,
    output wire num_shifts_flag_pe1 ,
    
    // FC layers interface
    input  wire fc_network_enable ,
    input  wire fc_output_ready,
    input  wire fc_l1_activation_enable,
    input  wire fc_l2_activation_enable,
    input  wire fc_l3_activation_enable,
    input  wire fc_pipeline_reset,
    output wire fc_pipeline_busy,
    output wire fc_pipeline_stalled,
    output wire fc_pipeline_ready,
    output wire fc_l1_busy,
    output wire fc_l2_busy,
    output wire fc_l3_busy,
    output wire signed [DATA_WIDTH-1:0] fc_output_data,
    output wire fc_output_valid
	);

	logic signed [DATA_WIDTH-1:0] conv_output ;
	wire conv_valid ;
	wire fc_input_ready ;


	cnn_pipeline_wrapper #(
		.DATA_WIDTH        (DATA_WIDTH), 
		.KERNEL_SIZE       (KERNEL_SIZE), 
		.STRIDE            (STRIDE) , 
		.PADDING           (PADDING) ,
		.FRAC_SZ           (FRAC_SZ) , 
		.IMAGE_WIDTH       (IMAGE_WIDTH), 
		.IMAGE_HEIGHT      (IMAGE_HEIGHT), 
		.NUM_IMAGES        (NUM_IMAGES), 
		.TOP_BOTTOM_PADDING(TOP_BOTTOM_PADDING), 
		.IN_CHANNELS       (IN_CHANNELS), 
		.OUT_CHANNELS      (OUT_CHANNELS), 
		.MAX_POOL_KERNEL   (MAX_POOL_KERNEL)
		) CNN_dut (
		.clk                (clk),
		.rst                (rst_n),
		.bram_image_in      (bram_image_in),
		.write_pixel_ready  (write_pixel_ready),
		.ENABLE_PE          (ENABLE_PE),
		.output_feature_map (conv_output),
		.num_shifts_flag_pe1(num_shifts_flag_pe1),
		.maxpool_done6      (conv_valid)
		) ;

	pipelined_fc_network #(
		.DATA_WIDTH          (DATA_WIDTH),
		.FRAC_SZ             (FRAC_SZ), 
		.L1_INPUT_SIZE       (L1_INPUT_SIZE), 
		.L1_OUTPUT_SIZE      (L1_OUTPUT_SIZE), 
		.L1_WEIGHT_DEPTH     (L1_WEIGHT_DEPTH), 
		.L1_WEIGHT_FILE      (L1_WEIGHT_FILE), 
		.L1_BIAS_FILE        (L1_BIAS_FILE),
		.L2_INPUT_SIZE       (L2_INPUT_SIZE), 
		.L2_OUTPUT_SIZE      (L2_OUTPUT_SIZE), 
		.L2_WEIGHT_DEPTH     (L2_WEIGHT_DEPTH), 
		.L2_WEIGHT_FILE      (L2_WEIGHT_FILE), 
		.L2_BIAS_FILE        (L2_BIAS_FILE),
		.L3_INPUT_SIZE       (L3_INPUT_SIZE), 
		.L3_OUTPUT_SIZE      (L3_OUTPUT_SIZE), 
		.L3_WEIGHT_DEPTH     (L3_WEIGHT_DEPTH), 
		.L3_WEIGHT_FILE      (L3_WEIGHT_FILE), 
		.L3_BIAS_FILE        (L3_BIAS_FILE),
		.INPUT_FIFO_DEPTH    (INPUT_FIFO_DEPTH), 
		.FIFO1_DEPTH         (FIFO1_DEPTH), 
		.FIFO2_DEPTH         (FIFO2_DEPTH), 
		.OUTPUT_FIFO_DEPTH   (OUTPUT_FIFO_DEPTH), 
		.L1_ENABLE_ACTIVATION(L1_ENABLE_ACTIVATION), 
		.L2_ENABLE_ACTIVATION(L2_ENABLE_ACTIVATION),
		.L3_ENABLE_ACTIVATION(L3_ENABLE_ACTIVATION)
		) FC_dut (
		.clk                 (clk),
		.rst_n               (!rst_n),
		.input_data          (conv_output),
		.input_valid         (conv_valid),
		.network_enable      (fc_network_enable),
		.input_ready         (fc_input_ready),  // Input FIFO not full 
		.output_ready        (fc_output_ready),
		.output_data         (fc_output_data),
		.output_valid        (fc_output_valid),
		.l1_activation_enable(fc_l1_activation_enable),
		.l2_activation_enable(fc_l2_activation_enable),
		.l3_activation_enable(fc_l3_activation_enable),
		.pipeline_reset      (fc_pipeline_reset),
		.pipeline_busy       (fc_pipeline_busy),
		.pipeline_stalled    (fc_pipeline_stalled),
		.pipeline_ready      (fc_pipeline_ready),
		.l1_busy             (fc_l1_busy),
		.l2_busy             (fc_l2_busy),
		.l3_busy             (fc_l3_busy)
		) ;

endmodule 