`timescale 1ns/1ps

module tb_conv2d_top_line_mac;

  //-------------------------------------------------------------------------
  // Parameter Declarations (for simulation, use a small image width)
  //-------------------------------------------------------------------------
  parameter IN_CHANNELS     = 4;
  parameter OUT_CHANNELS    = 8;
  parameter KERNEL_SIZE     = 3;
  parameter STRIDE          = 1;
  parameter PADDING         = 1;
  // Use a small image for simulation speed.
  parameter IMAGE_WIDTH     = 16;
  parameter DATA_WIDTH      = 16;
  // NUM_PIXELS = 1: one output pixel per window.
  parameter NUM_PIXELS      = 1;
  parameter MAX_POOL_KERNEL = 2;

  //-------------------------------------------------------------------------
  // Signal Declarations
  //-------------------------------------------------------------------------
  logic clk;
  logic rst;
  logic valid_in;
  logic pad_top;
  logic pad_bottom;
  logic start;
  logic next_channel;

  // Pixel input for each channel (row-wise input)
  logic signed [DATA_WIDTH-1:0] pixel_in ;

  // Kernel weights for the convolution kernel (3×3)
  logic signed [DATA_WIDTH-1:0] kernel_weights [KERNEL_SIZE][KERNEL_SIZE];

  // DUT outputs
  logic valid_out;
  logic signed [DATA_WIDTH-1:0] output_feature_map;

  //-------------------------------------------------------------------------
  // DUT Instantiation: conv2d_top
  //-------------------------------------------------------------------------
  conv2d_top #(
    .IN_CHANNELS(IN_CHANNELS),
    .OUT_CHANNELS(OUT_CHANNELS),
    .KERNEL_SIZE(KERNEL_SIZE),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .IMAGE_WIDTH(IMAGE_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_PIXELS(NUM_PIXELS),
    .MAX_POOL_KERNEL(MAX_POOL_KERNEL)
  ) DUT (
    .clk(clk),
    .rst(rst),
    .valid_in(valid_in),
    .pad_top(pad_top),
    .pad_bottom(pad_bottom),
    .start(start),
    .next_channel(next_channel),
    .pixel_in(pixel_in),
    .kernel_weights(kernel_weights),
    .valid_out(valid_out),
    .output_feature_map(output_feature_map)
  );

  //-------------------------------------------------------------------------
  // Clock Generation: 10 ns period (100 MHz)
  //-------------------------------------------------------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  //-------------------------------------------------------------------------
  // Stimulus Generation
  //-------------------------------------------------------------------------
  initial begin
    // Initialize control signals and inputs.
    rst         = 1;
    valid_in    = 0;
    pad_top     = 0;
    pad_bottom  = 0;
    start       = 0;
    next_channel= 0;
    for (int i = 0; i < IN_CHANNELS; i++) begin
      pixel_in[i] = 0;
    end

    // Initialize kernel weights with a known pattern:
    //   [ 1  2  3 ]
    //   [ 4  5  6 ]
    //   [ 7  8  9 ]
    kernel_weights[0][0] = 16'd1; kernel_weights[0][1] = 16'd1; kernel_weights[0][2] = 16'd1;
    kernel_weights[1][0] = 16'd1; kernel_weights[1][1] = 16'd1; kernel_weights[1][2] = 16'd1;
    kernel_weights[2][0] = 16'd1; kernel_weights[2][1] = 16'd1; kernel_weights[2][2] = 16'd1;

    // Hold reset for a few cycles
    #20;
    rst = 0;
    valid_in = 1;

    // For the very first row, enable top padding.
    pad_top = 1;
    #20;
    pad_top = 0;

    //-------------------------------------------------------------------------
    // Feed Pixel Data: Generate 3 rows (sufficient to fill a 3-row line buffer)
    //-------------------------------------------------------------------------
    // For each row, we drive IMAGE_WIDTH pixel values (one per clock cycle).
    for (int row = 0; row < 10; row++) begin
      $display("Starting row %0d...", row);
      for (int col = 0; col < IMAGE_WIDTH; col++) begin
        // For each channel, generate a test value.
        // Example: pixel value = (row * IMAGE_WIDTH + col) + channel index.
        
          pixel_in = (row + col) ;
        
        #10; // one clock period per pixel sample
      end
      // For the last row, assert bottom padding at the end.
      if (row == 9) begin
        pad_bottom = 1;
        #10;
        pad_bottom = 0;
      end
    end

    //-------------------------------------------------------------------------
    // Allow time for the internal pipeline (line buffer, reg buffers, MAC, etc.)
    // to process the data and produce an output.
    //-------------------------------------------------------------------------
    #200;

    // Check and display the result.
    if(valid_out)
      $display("At time %0t: Output feature map (conv2d_top) = %0d", $time, output_feature_map[0]);
    else
      $display("At time %0t: valid_out not asserted", $time);

    // Finish simulation after a short delay.
    #100;
    $finish;
  end

  //-------------------------------------------------------------------------
  // Monitor: Display key signals whenever they change.
  //-------------------------------------------------------------------------
  initial begin
    $monitor("Time: %0t | valid_out: %b | Output: %0d", 
              $time, valid_out, output_feature_map[0]);
  end

endmodule

