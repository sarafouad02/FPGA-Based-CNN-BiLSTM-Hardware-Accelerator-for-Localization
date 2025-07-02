`timescale 1ns/1ps

module cnn_pipeline_wrapper_tb;

  // Parameters must match the wrapper’s
  localparam DATA_WIDTH         = 16;
  localparam KERNEL_SIZE        = 3;
  localparam STRIDE             = 1;
  localparam PADDING            = 1;
  localparam MAX_POOL_KERNEL    = 2;
  localparam FRAC_SZ            = 12;
  localparam IMAGE_WIDTH        = 64;
  localparam IMAGE_HEIGHT       = 64;
  localparam NUM_IMAGES         = 4;
  localparam TOP_BOTTOM_PADDING = 1;
  localparam IN_CHANNELS        =4;
  localparam OUT_CHANNELS      = 4;
  
   // Layer 1 parameters
    parameter L1_INPUT_SIZE = 6;
    parameter L1_OUTPUT_SIZE = 100;
    parameter L1_WEIGHT_DEPTH = L1_INPUT_SIZE*L1_OUTPUT_SIZE;  
    parameter L1_WEIGHT_FILE = "fc1_weight.mem";
    parameter L1_BIAS_FILE = "fc1_bias.mem";

    
    // Layer 2 parameters  
    parameter L2_INPUT_SIZE = L1_OUTPUT_SIZE;
    parameter L2_OUTPUT_SIZE = 50;
    parameter L2_WEIGHT_DEPTH = L2_INPUT_SIZE*L2_OUTPUT_SIZE ; 
    parameter L2_WEIGHT_FILE = "fc2_weight.mem";
    parameter L2_BIAS_FILE = "fc2_bias.mem";

    
    // Layer 3 parameters
    parameter L3_INPUT_SIZE = L2_OUTPUT_SIZE;
    parameter L3_OUTPUT_SIZE = 3;       
    parameter L3_WEIGHT_DEPTH = L3_INPUT_SIZE*L3_OUTPUT_SIZE;    
    
    parameter L3_WEIGHT_FILE = "fc3_weight.mem";
    parameter L3_BIAS_FILE = "fc3_bias.mem";
    
    // FIFO parameters
    parameter INPUT_FIFO_DEPTH = 512;
    parameter FIFO1_DEPTH = 512;
    parameter FIFO2_DEPTH = 512;
    parameter OUTPUT_FIFO_DEPTH = 512;
    
    // Activation control
    parameter L1_ENABLE_ACTIVATION = 1;
    parameter L2_ENABLE_ACTIVATION = 1;
    parameter L3_ENABLE_ACTIVATION = 0;


  // Clock & reset
  logic clk;
  logic rst_n;      // active-high reset for wrapper

  // Control
  logic start_tb;
  logic ENABLE_PE;

  // Weight memories (we’ll fill with ones for simplicity)
  // logic signed [DATA_WIDTH-1:0]
    // w1 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
    // w2 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
    // w3 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
    // w4 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
    // w5 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
    // w6 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];

  // // Outputs from wrapper
  // logic bram_en, num_shifts_flag_pe1 , write_pixel_ready, maxpool_done6;
  // logic [DATA_WIDTH-1:0] bram_image_in;
   logic [DATA_WIDTH-1:0] mem[IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES];

  //logic signed [DATA_WIDTH-1:0]  output_feature_map;

  // File handles for PE outputs
  integer fd_pe1, fd_pe2, fd_pe3, fd_pe4, fd_pe5, fd_pe6 , fd_pe1_float;
  integer fd_fc1, fd_fc2, fd_fc3;

    // CONV interface
   
    reg [DATA_WIDTH-1:0] bram_image_in;
    reg write_pixel_ready;
    wire [$clog2(4)-1:0] current_channel_out;
    wire num_shifts_flag_pe1;
    
    // FC interface
    reg fc_network_enable;
    reg fc_output_ready;
    reg fc_l1_activation_enable;
    reg fc_l2_activation_enable;
    reg fc_l3_activation_enable;
    reg fc_pipeline_reset;
    wire fc_pipeline_busy;
    wire fc_pipeline_stalled;
    wire fc_pipeline_ready;
    wire fc_l1_busy;
    wire fc_l2_busy;
    wire fc_l3_busy;
    wire signed [DATA_WIDTH-1:0] fc_output_data;
    wire fc_output_valid;
    
    // Counters
    integer input_count;
    integer output_count;
    
    // // Clock generation
    // always #(CLK_PERIOD/2) clk = ~clk;
    
    // DUT instantiation
    CNN_wrapper #(
        .DATA_WIDTH(DATA_WIDTH), 
        .KERNEL_SIZE(KERNEL_SIZE), 
        .NUM_IMAGES(NUM_IMAGES) , 
        .IMAGE_WIDTH(IMAGE_WIDTH), 
        .IMAGE_HEIGHT(IMAGE_HEIGHT), 
        .STRIDE(STRIDE), 
        .FRAC_SZ(FRAC_SZ),
        .PADDING(PADDING), 
        .MAX_POOL_KERNEL(MAX_POOL_KERNEL) , 
        .TOP_BOTTOM_PADDING(TOP_BOTTOM_PADDING), 
        .IN_CHANNELS(IN_CHANNELS), 
        .OUT_CHANNELS(OUT_CHANNELS), 
        ////////////////////////////////
        .L1_INPUT_SIZE(L1_INPUT_SIZE), 
        .L1_OUTPUT_SIZE(L1_OUTPUT_SIZE) , 
        .L1_WEIGHT_DEPTH(L1_WEIGHT_DEPTH), 
        .L1_WEIGHT_FILE(L1_WEIGHT_FILE), 
        .L1_BIAS_FILE(L1_BIAS_FILE), 
        .L2_INPUT_SIZE(L2_INPUT_SIZE), 
        .L2_OUTPUT_SIZE(L2_OUTPUT_SIZE), 
        .L2_WEIGHT_DEPTH(L2_WEIGHT_DEPTH),
        .L2_WEIGHT_FILE(L2_WEIGHT_FILE), 
        .L2_BIAS_FILE(L2_BIAS_FILE), 
        .L3_INPUT_SIZE(L3_INPUT_SIZE) , 
        .L3_OUTPUT_SIZE(L3_OUTPUT_SIZE), 
        .L3_WEIGHT_DEPTH(L3_WEIGHT_DEPTH) , 
        .L3_WEIGHT_FILE(L3_WEIGHT_FILE), 
        .L3_BIAS_FILE(L3_BIAS_FILE), 
        .INPUT_FIFO_DEPTH(INPUT_FIFO_DEPTH), 
        .FIFO1_DEPTH(FIFO1_DEPTH), 
        .FIFO2_DEPTH(FIFO2_DEPTH), 
        .OUTPUT_FIFO_DEPTH(OUTPUT_FIFO_DEPTH), 
        .L1_ENABLE_ACTIVATION(L1_ENABLE_ACTIVATION), 
        .L2_ENABLE_ACTIVATION(L2_ENABLE_ACTIVATION), 
        .L3_ENABLE_ACTIVATION(L3_ENABLE_ACTIVATION)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ENABLE_PE(ENABLE_PE),
        .bram_image_in(bram_image_in),
        .write_pixel_ready(write_pixel_ready),
        .num_shifts_flag_pe1(num_shifts_flag_pe1),
        .fc_network_enable(fc_network_enable),
        .fc_output_ready(fc_output_ready),
        .fc_l1_activation_enable(fc_l1_activation_enable),
        .fc_l2_activation_enable(fc_l2_activation_enable),
        .fc_l3_activation_enable(fc_l3_activation_enable),
        .fc_pipeline_reset(fc_pipeline_reset),
        .fc_pipeline_busy(fc_pipeline_busy),
        .fc_pipeline_stalled(fc_pipeline_stalled),
        .fc_pipeline_ready(fc_pipeline_ready),
        .fc_l1_busy(fc_l1_busy),
        .fc_l2_busy(fc_l2_busy),
        .fc_l3_busy(fc_l3_busy),
        .fc_output_data(fc_output_data),
        .fc_output_valid(fc_output_valid)
    );
  // Clock generation: 20 ns period → 50 MHz
  initial begin
    clk = 0;
    forever #10 clk = ~clk;
  end

  int i, j;
  // Stimulus + file opens
  initial begin
    // 1) Reset & init
    rst_n       = 1;
    start_tb  = 0;
    ENABLE_PE = 0;
    write_pixel_ready = 0;
    fc_network_enable = 0;
    fc_output_ready = 1;
    fc_l1_activation_enable = 1;
    fc_l2_activation_enable = 1;
    fc_l3_activation_enable = 0;
    fc_pipeline_reset = 0;
    input_count = 0;
    output_count = 0;

    // Hold reset
    #100;
    rst_n = 0;

    // Small settle
    #50;

    // Open output files for each PE
    fd_pe1 = $fopen("pe1_output.mem", "w");
    fd_pe2 = $fopen("pe2_output.mem", "w");
    fd_pe3 = $fopen("pe3_output.mem", "w");
    fd_pe4 = $fopen("pe4_output.mem", "w");
    fd_pe5 = $fopen("pe5_output.mem", "w");
    fd_pe6 = $fopen("pe6_output.mem", "w");

    // Open FC files
    fd_fc1 = $fopen("fc1_output.mem","w");
    fd_fc2 = $fopen("fc2_output.mem","w");
    fd_fc3 = $fopen("fc3_output.mem","w");



    // Start streaming
    start_tb  = 1;
    ENABLE_PE = 1;
    fc_network_enable = 1;
     
    #20;
    start_tb = 0;
   

    // Load BRAM 2
    $readmemh("combined_combined_frames_0003_0004.mem", mem);
    #20;

    write_pixel_ready = 1;
    #20;
    write_pixel_ready = 0;

    for (int i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES; i++) begin
      @(posedge clk);
      bram_image_in = mem[i];
      
    end

    // Wait for first PE flag, reload, etc. (as in your TB)
    wait (num_shifts_flag_pe1);
    $display(">>> file done");
    ENABLE_PE = 0; #20;// ENABLE_PE = 1;
    #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES*100)*20);


  // // Start streaming 2
  //   start_tb  = 1;
  //   ENABLE_PE = 1;
  //   #20;
  //   start_tb = 0;


  //   // Load BRAM 3
  //   $readmemh("combined_combined_frames_0005_0006.mem", mem);
  //   #20;

  //   write_pixel_ready = 1;
  //   #20;
  //   write_pixel_ready = 0;

  //   for (int i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES; i++) begin
  //     @(posedge clk);
  //     bram_image_in = mem[i];
  //   end

  //   // Wait for first PE flag, reload, etc. (as in your TB)
  //   wait (num_shifts_flag_pe1);
  //   $display(">>> file done");
  //   ENABLE_PE = 0; #20;// ENABLE_PE = 1;
  //   #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)*20);

  //   // Start streaming 3
  //   start_tb  = 1;
  //   ENABLE_PE = 1;
  //   #20;
  //   start_tb = 0;


  //   // Load BRAM 4
  //   $readmemh("combined_combined_frames_0007_0008.mem", mem);
  //   #20;

  //   write_pixel_ready = 1;
  //   #20;
  //   write_pixel_ready = 0;

  //   for (int i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES; i++) begin
  //     @(posedge clk);
  //     bram_image_in = mem[i];
      
  //   end

  //   // Wait for first PE flag, reload, etc. (as in your TB)
  //   wait (num_shifts_flag_pe1);
  //   $display(">>> file done");
  //   ENABLE_PE = 0; #20;// ENABLE_PE = 1;
  //   #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)*20);


  // // Start streaming 4
  //   start_tb  = 1;
  //   ENABLE_PE = 1;
  //   #20;
  //   start_tb = 0;


  //   // Load BRAM 5
  //   $readmemh("combined_combined_frames_0009_0010.mem", mem);
  //   #20;

  //   write_pixel_ready = 1;
  //   #20;
  //   write_pixel_ready = 0;

  //   for (int i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES; i++) begin
  //     @(posedge clk);
  //     bram_image_in = mem[i];
  //   end

  //   // Wait for first PE flag, reload, etc. (as in your TB)
  //   wait (num_shifts_flag_pe1);
  //   $display(">>> file done");
  //   ENABLE_PE = 0; #20;// ENABLE_PE = 1;
  //   #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)*20);

  //   // Start streaming 5
  //   start_tb  = 1;
  //   ENABLE_PE = 1;
  //   #20;
  //   start_tb = 0;


  //   // Load BRAM 6
  //   $readmemh("combined_combined_frames_0011_0012.mem", mem);
  //   #20;

  //   write_pixel_ready = 1;
  //   #20;
  //   write_pixel_ready = 0;

  //   for (int i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES; i++) begin
  //     @(posedge clk);
  //     bram_image_in = mem[i];
      
  //   end

  //   // Wait for first PE flag, reload, etc. (as in your TB)
  //   wait (num_shifts_flag_pe1);
  //   $display(">>> file done");
  //   ENABLE_PE = 0; #20;// ENABLE_PE = 1;
  //   #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)*20);


  // // Start streaming 6
  //   start_tb  = 1;
  //   ENABLE_PE = 1;
  //   #20;
  //   start_tb = 0;


  //   // Load BRAM 7
  //   $readmemh("combined_combined_frames_0013_0014.mem", mem);
  //   #20;

  //   write_pixel_ready = 1;
  //   #20;
  //   write_pixel_ready = 0;

  //   for (int i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES; i++) begin
  //     @(posedge clk);
  //     bram_image_in = mem[i];
  //   end

  //   // Wait for first PE flag, reload, etc. (as in your TB)
  //   wait (num_shifts_flag_pe1);
  //   $display(">>> file done");
  //   ENABLE_PE = 0; #20;// ENABLE_PE = 1;
  //   #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)*20);

  //   // Start streaming 7
  //   start_tb  = 1;
  //   ENABLE_PE = 1;
  //   #20;
  //   start_tb = 0;


  //   // Load BRAM 8
  //   $readmemh("combined_combined_frames_0015_0016.mem", mem);
  //   #20;

  //   write_pixel_ready = 1;
  //   #20;
  //   write_pixel_ready = 0;

  //   for (int i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES; i++) begin
  //     @(posedge clk);
  //     bram_image_in = mem[i];
      
  //   end

  //   // Wait for first PE flag, reload, etc. (as in your TB)
  //   wait (num_shifts_flag_pe1);
  //   $display(">>> file done");
  //   ENABLE_PE = 0; #20;// ENABLE_PE = 1;
  //   #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)*20);


  // // Start streaming 8
  //   start_tb  = 1;
  //   ENABLE_PE = 1;
  //   #20;
  //   start_tb = 0;


  //   // Load BRAM 9
  //   $readmemh("combined_combined_frames_0017_0018.mem", mem);
  //   #20;

  //   write_pixel_ready = 1;
  //   #20;
  //   write_pixel_ready = 0;

  //   for (int i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES; i++) begin
  //     @(posedge clk);
  //     bram_image_in = mem[i];
  //   end

  //   // Wait for first PE flag, reload, etc. (as in your TB)
  //   wait (num_shifts_flag_pe1);
  //   $display(">>> file done");
  //   ENABLE_PE = 0; #20;// ENABLE_PE = 1;
  //   #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)*20);

  //   // Start streaming 9
  //   start_tb  = 1;
  //   ENABLE_PE = 1;
  //   #20;
  //   start_tb = 0;


  //   // Load BRAM 10
  //   $readmemh("combined_combined_frames_0019_0020.mem", mem);
  //   #20;

  //   write_pixel_ready = 1;
  //   #20;
  //   write_pixel_ready = 0;

  //   for (int i = 0; i < IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES; i++) begin
  //     @(posedge clk);
  //     bram_image_in = mem[i];
  //   end

  //   // Wait for first PE flag, reload, etc. (as in your TB)
  //   wait (num_shifts_flag_pe1);
  //   $display(">>> file done");
  //   ENABLE_PE = 0; #20;// ENABLE_PE = 1;
  //   #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)*20);

  //   // Start streaming 10
  //   start_tb  = 1;
  //   ENABLE_PE = 1;
  //   #20;
  //   start_tb = 0;

  //   // Wait for first PE flag, reload, etc. (as in your TB)
  //   wait (num_shifts_flag_pe1);
  //   $display(">>> file done");
  //   ENABLE_PE = 0; #20;// ENABLE_PE = 1;
  //   #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)*20);


  //   // Generous wait for rest of pipeline
  //   #((IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES*100)*20);

    
    $stop;
  end

  // On each PE’s maxpool_done, capture its stage_out into its .mem
  always_ff @(posedge clk) begin
    if (dut.CNN_dut.maxpool_done1) $fwrite(fd_pe1, "%0d\n", dut.CNN_dut.stage_out[0]);
    if (dut.CNN_dut.maxpool_done2) $fwrite(fd_pe2, "%0d\n", dut.CNN_dut.stage_out[1]);
    if (dut.CNN_dut.maxpool_done3) $fwrite(fd_pe3, "%0d\n", dut.CNN_dut.stage_out[2]);
    if (dut.CNN_dut.maxpool_done4) $fwrite(fd_pe4, "%0d\n", dut.CNN_dut.stage_out[3]);
    if (dut.CNN_dut.maxpool_done5) $fwrite(fd_pe5, "%0d\n", dut.CNN_dut.stage_out[4]);
    if (dut.CNN_dut.maxpool_done6) $fwrite(fd_pe6, "%0d\n", dut.CNN_dut.stage_out[5]);
  end
  // On each PE’s maxpool_done, capture its stage_out into its .mem

  // Capture FC layer 1 outputs when they’re written into fifo1
  always_ff @(posedge clk) begin
    if (dut.FC_dut.l1_output_wr_en)
      $fwrite(fd_fc1, "%0d\n", dut.FC_dut.l1_output_data);
  end

  // Capture FC layer 2 outputs when they’re written into fifo2
  always_ff @(posedge clk) begin
    if (dut.FC_dut.l2_output_wr_en)
      $fwrite(fd_fc2, "%0d\n", dut.FC_dut.l2_output_data);
  end

  // Capture FC layer 3 outputs when they’re written into output fifo
  always_ff @(posedge clk) begin
    if (dut.FC_dut.l3_output_wr_en)
      $fwrite(fd_fc3, "%0d\n", dut.FC_dut.l3_output_data);
  end
 

  // Close files at the end
  final begin
    $fclose(fd_pe1);
    $fclose(fd_pe2);
    $fclose(fd_pe3);
    $fclose(fd_pe4);
    $fclose(fd_pe5);
    $fclose(fd_pe6);
    $fclose(fd_fc1);
    $fclose(fd_fc2);
    $fclose(fd_fc3);
  end


endmodule




// `timescale 1ns/1ps

// module cnn_pipeline_wrapper_tb;

//   // Parameters must match the wrapper’s
//   localparam DATA_WIDTH      = 16;
//   localparam KERNEL_SIZE     = 3;
//   localparam STRIDE          = 1;
//   localparam PADDING         = 1;
//   localparam MAX_POOL_KERNEL = 2;
//   localparam FRAC_SZ         = 0;
//   localparam IMAGE_WIDTH     = 15;
//   localparam IMAGE_HEIGHT    = 9;
//   localparam NUM_IMAGES      = 4;
//   localparam TOP_BOTTOM_PADDING = 1;

//   // Clock & reset
//   logic clk;
//   logic rst;      // active-high reset for wrapper
//   logic rst_n;    // active-low for System_ControlUnit

//   // Control
//   logic start_tb;
//   // logic pad_top, pad_bottom;

//   // Weight memories (we’ll fill with zeros for simplicity)
//   logic signed [DATA_WIDTH-1:0]
//     w1 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
//     w2 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
//     w3 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
//     w4 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
//     w5 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
//     w6 [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];

//   // Outputs from wrapper
//   logic                       bram_en, ENABLE_PE, finished_4_images, num_shifts_flag_pe1;
//   logic [$clog2(NUM_IMAGES)-1:0] current_channel_out;
//   logic signed [DATA_WIDTH-1:0] output_feature_map;

//   // Instantiate DUT
//   cnn_pipeline_wrapper #(
//     .DATA_WIDTH      (DATA_WIDTH),
//     .KERNEL_SIZE     (KERNEL_SIZE),
//     .STRIDE          (STRIDE),
//     .PADDING         (PADDING),
//     .MAX_POOL_KERNEL (MAX_POOL_KERNEL),
//     .FRAC_SZ         (FRAC_SZ), 
//     .NUM_IMAGES     (NUM_IMAGES), 
//     .IMAGE_WIDTH    (IMAGE_WIDTH), 
//     .IMAGE_HEIGHT   (IMAGE_HEIGHT), 
//     .TOP_BOTTOM_PADDING(TOP_BOTTOM_PADDING)
//   ) uut (
//     .clk                (clk),
//     .rst                (rst),
//     .weights_l1         (w1),
//     .weights_l2         (w2),
//     .weights_l3         (w3),
//     .weights_l4         (w4),
//     .weights_l5         (w5),
//     .weights_l6         (w6), 
//     .ENABLE_PE          (ENABLE_PE),
//     .bram_en            (bram_en),
//     .current_channel_out(current_channel_out), 
//     .finished_4_images  (finished_4_images), 
//     .num_shifts_flag_pe1(num_shifts_flag_pe1),
//     .output_feature_map (output_feature_map)
//   );

//   // Tie-through start/rst_n into the internal System_ControlUnit
//   // The wrapper drives start via an internal signal; we catch it below
//   // by poking the wrapper’s ready_signal_to_sys_CU1 net with start_tb.
//   // For this test, we’ll poke the internal signal via VPI, but
//   // for simplicity assume the wrapper exposes start directly in your build.
//   // If not, you may need to modify your wrapper to expose start.

//   //------------------------------------------------------------------------------
//   // Clock generation: 20 ns period → 50 MHz
//   //------------------------------------------------------------------------------
//   initial begin
//     clk = 0;
//     forever #10 clk = ~clk;
//   end

//   //------------------------------------------------------------------------------
//   // Stimulus
//   //------------------------------------------------------------------------------
//   initial begin
//   // 1) Initial reset & signals
//   rst         = 1;
//   rst_n       = 0;
//   start_tb    = 0;
//   ENABLE_PE   = 0;

//   // 2) Initialize all weights to 1
//   foreach (w1[i,j]) w1[i][j] = 1;
//   foreach (w2[i,j]) w2[i][j] = 1;
//   foreach (w3[i,j]) w3[i][j] = 1;
//   foreach (w4[i,j]) w4[i][j] = 1;
//   foreach (w5[i,j]) w5[i][j] = 1;
//   foreach (w6[i,j]) w6[i][j] = 1;

//   // 3) Hold reset for 100 ns
//   #100;
//   rst   = 0;
//   rst_n = 1;

//   // 4) Load initial BRAM contents
//   $readmemh("output_small.hex", uut.BRAM_IMG.mem);

//   // 5) Small settle time
//   #50;

//   // 6) Kick off the first pass
//   start_tb  = 1;
//   ENABLE_PE = 1;
//   #20;
//   start_tb  = 0;

//   // 7) Let the pipeline drain (generous margin)
//   // #((IMAGE_WIDTH * IMAGE_HEIGHT * NUM_IMAGES * 100) * 20);

//   $display(">>> First pass complete. Waiting for num_shifts_flag_pe1...");

//   // 8) Wait for the flag from PE1
//   wait (num_shifts_flag_pe1);

//   // 9) Toggle ENABLE_PE low→high, then reload BRAM
//   ENABLE_PE = 0;
//   #20;
//   // ENABLE_PE = 1;

//   // $display(">>> Detected num_shifts_flag_pe1. Reloading BRAM...");

//   // $readmemh("output_small.hex", uut.BRAM_IMG.mem);
// ////////////////////////////////////////////////////////////////////////////////////////////
// // 5) Small settle time
//   // #50;

//   // // 6) Kick off the first pass
//   // start_tb  = 1;
//   // ENABLE_PE = 1;
//   // #20;
//   // start_tb  = 0;

//   // // 7) Let the pipeline drain (generous margin)
//   // // #((IMAGE_WIDTH * IMAGE_HEIGHT * NUM_IMAGES * 100) * 20);

//   // $display(">>> First pass complete. Waiting for num_shifts_flag_pe1...");

//   // // 8) Wait for the flag from PE1
//   // wait (num_shifts_flag_pe1);

//   // // 9) Toggle ENABLE_PE low→high, then reload BRAM
//   // ENABLE_PE = 0;
//   // #20;
//   // ENABLE_PE = 1;

//   // $display(">>> Detected num_shifts_flag_pe1. Reloading BRAM...");

//   // $readmemh("output_small.hex", uut.BRAM_IMG.mem);

//   // wait (num_shifts_flag_pe1);

//   // // 9) Toggle ENABLE_PE low→high, then reload BRAM
//   // ENABLE_PE = 0;
//   // #20;
//   // ENABLE_PE = 1;
//   // wait (num_shifts_flag_pe1);

//   // // 9) Toggle ENABLE_PE low→high, then reload BRAM
//   // ENABLE_PE = 0;
//   // #20;

//   // 10) Optionally run a second pass or finish
//   #((IMAGE_WIDTH * IMAGE_HEIGHT * NUM_IMAGES * 1000) * 20);

//   $display(">>> Simulation complete. Final feature = %0d", output_feature_map);
//   $stop;
// end



//  initial begin
//     // … your existing reset / start / reload code …

//     // Open one file per PE
//     fd_pe1 = $fopen("pe1_output.mem", "w");
//     fd_pe2 = $fopen("pe2_output.mem", "w");
//     fd_pe3 = $fopen("pe3_output.mem", "w");
//     fd_pe4 = $fopen("pe4_output.mem", "w");
//     fd_pe5 = $fopen("pe5_output.mem", "w");
//     fd_pe6 = $fopen("pe6_output.mem", "w");
//   end

//   //----------------------------------------------------------------------  
//   // On each PE’s maxpool_done, grab its internal output_feature_map
//   //----------------------------------------------------------------------  
//   always_ff @(posedge clk) begin
//     if (uut.maxpool_done1) begin
//       // Assuming stage_out[0] is visible hierarchically as uut.stage_out[0]
//       $fwrite(fd_pe1, "%0h\n", uut.stage_out[0]);
//     end
//     if (uut.maxpool_done2) begin
//       $fwrite(fd_pe2, "%0h\n", uut.stage_out[1]);
//     end
//     if (uut.maxpool_done3) begin
//       $fwrite(fd_pe3, "%0h\n", uut.stage_out[2]);
//     end
//     if (uut.maxpool_done4) begin
//       $fwrite(fd_pe4, "%0h\n", uut.stage_out[3]);
//     end
//     if (uut.maxpool_done5) begin
//       $fwrite(fd_pe5, "%0h\n", uut.stage_out[4]);
//     end
//     if (uut.maxpool_done6) begin
//       $fwrite(fd_pe6, "%0h\n", uut.stage_out[5]);
//     end
//   end

//   //----------------------------------------------------------------------  
//   // At the end of simulation, close all files
//   //----------------------------------------------------------------------  
//   final begin
//     $fclose(fd_pe1);
//     $fclose(fd_pe2);
//     $fclose(fd_pe3);
//     $fclose(fd_pe4);
//     $fclose(fd_pe5);
//     $fclose(fd_pe6);
//   end



//   //------------------------------------------------------------------------------
//   // Hook up `start_tb` to the internal System_ControlUnit
//   //------------------------------------------------------------------------------
//   // If your wrapper doesn’t expose `start` directly, insert a driver here:
//   // e.g. force uut.Sys_CU.start = start_tb; 
//   // in an initial block or via bind. For now we assume it’s exposed as:
//   // .start(start_tb) on System_ControlUnit instantiation.
//   //------------------------------------------------------------------------------

// endmodule


// `timescale 1ns / 1ps

// module cnn_pipeline_wrapper_tb;

//   // Parameters
//   parameter DATA_WIDTH   = 16;
//   parameter KERNEL_SIZE  = 3;
//   parameter STRIDE       = 1;
//   parameter PADDING      = 1;
//   parameter MAX_POOL_KERNEL = 2;
//   parameter FRAC_SZ = 0;

//   // Clock and reset
//   logic clk;
//   logic rst;

//   // Inputs to the DUT
//   logic valid_in;
//   logic pad_top;
//   logic pad_bottom;
//   logic next_channel;
//   logic signed [DATA_WIDTH-1:0] pixel_in;
//   logic bram_en;
//   logic signed [DATA_WIDTH-1:0] weights_l1 [KERNEL_SIZE][KERNEL_SIZE];
//   logic signed [DATA_WIDTH-1:0] weights_l2 [KERNEL_SIZE][KERNEL_SIZE];
//   logic signed [DATA_WIDTH-1:0] weights_l3 [KERNEL_SIZE][KERNEL_SIZE];
//   logic signed [DATA_WIDTH-1:0] weights_l4 [KERNEL_SIZE][KERNEL_SIZE];
//   logic signed [DATA_WIDTH-1:0] weights_l5 [KERNEL_SIZE][KERNEL_SIZE];
//   logic signed [DATA_WIDTH-1:0] weights_l6 [KERNEL_SIZE][KERNEL_SIZE];

//   // Outputs from the DUT
//   logic valid_out;
//   logic [$clog2(4)-1:0] current_channel_out;
//   logic signed [DATA_WIDTH-1:0] output_feature_map;
//    int i, j;
//    integer count;
//   // Clock generation
//   initial clk = 0;
//   always #5 clk = ~clk; // 100MHz

//   // Instantiate the DUT
//   cnn_pipeline_wrapper #(
//     .DATA_WIDTH(DATA_WIDTH),
//     .KERNEL_SIZE(KERNEL_SIZE),
//     .STRIDE(STRIDE),
//     .PADDING(PADDING),
//     .MAX_POOL_KERNEL(MAX_POOL_KERNEL),
//     .FRAC_SZ(FRAC_SZ)
//   ) dut (
//     .clk(clk),
//     .rst(rst),
//     .valid_in(valid_in),
//     .pad_top(pad_top),
//     .pad_bottom(pad_bottom),
//     .next_channel(next_channel),
//     .pixel_in(pixel_in),
//     .weights_l1(weights_l1),
//     .weights_l2(weights_l2),
//     .weights_l3(weights_l3),
//     .weights_l4(weights_l4),
//     .weights_l5(weights_l5),
//     .weights_l6(weights_l6),
//     .valid_out(valid_out),
//     .bram_en(bram_en),
//     .current_channel_out(current_channel_out),
//     .output_feature_map(output_feature_map)
//   );

//   // Stimulus
//   initial begin
//     rst = 1;
//     valid_in = 0;
//     pad_top = 0;
//     pad_bottom = 0;
//     next_channel = 0;
//     pixel_in = 0;
//     #20;
//     rst = 0;

//     // Initialize weights with simple patterns
 
//     for (i = 0; i < KERNEL_SIZE; i++) begin
//       for (j = 0; j < KERNEL_SIZE; j++) begin
//         weights_l1[i][j] = 1;
//         weights_l2[i][j] = 2;
//         weights_l3[i][j] = 3;
//         weights_l4[i][j] = 4;
//         weights_l5[i][j] = 5;
//         weights_l6[i][j] = 6;
//       end
//     end

//     // Wait for pipeline output
//    end

//       initial begin
//     pixel_in = 0;
//     // Generate pixel stream continuously when valid_in is high.
//     // This loop simulates enough pixels to cover both the fill phase and update phase.
    
//     count = 0;
//       forever begin
//        @(negedge clk);
//       if (bram_en) begin
//         pixel_in = $urandom_range(1,32);
//         count = (count + 1 )%(2*DATA_WIDTH);
//     end 
//         else begin
//             pixel_in=0;
//         end

//     end

//   end
// initial begin
//     #1000000; // Adjust simulation duration as necessary to see fill/update behavior.
//     $stop;
//   end

// endmodule
