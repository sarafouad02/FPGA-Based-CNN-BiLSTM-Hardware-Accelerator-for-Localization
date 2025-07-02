// `timescale 1ns/1ps
// module tb_conv2d_top;

//   //-------------------------------------------------------------------------
//   // Parameter Definitions (override top-level parameters for simulation)
//   //-------------------------------------------------------------------------
//   localparam IN_CHANNELS     = 4;
//   localparam OUT_CHANNELS    = 8;
//   localparam KERNEL_SIZE     = 3;
//   localparam STRIDE          = 1;
//   localparam PADDING         = 1;
//   localparam IMAGE_WIDTH     = 16; // Reduced for simulation
//   localparam DATA_WIDTH      = 16;
//   localparam NUM_PIXELS      = 1;  // Processing one pixel (or one window) at a time
//   localparam MAX_POOL_KERNEL = 2;

//   //-------------------------------------------------------------------------
//   // Testbench Signal Declarations
//   //-------------------------------------------------------------------------
//   logic clk, rst, valid_in, pad_top, pad_bottom, next_channel;
//   // pixel_in and other fixed point numbers are in Q4.12 format.
//   logic signed [DATA_WIDTH-1:0] pixel_in;
//   logic signed [DATA_WIDTH-1:0] kernel_weights [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];

//   // Outputs from conv2d_top
//   logic valid_out;
//   logic [$clog2(IN_CHANNELS)-1:0] current_channel;
//   logic signed [DATA_WIDTH-1:0] output_feature_map;
//   logic bram_en;
//   logic [DATA_WIDTH-1:0] bram_addr;

//   //-------------------------------------------------------------------------
//   // DUT Instantiation
//   //-------------------------------------------------------------------------
//   conv2d_top #(
//     .IN_CHANNELS     (IN_CHANNELS),
//     .OUT_CHANNELS    (OUT_CHANNELS),
//     .KERNEL_SIZE     (KERNEL_SIZE),
//     .STRIDE          (STRIDE),
//     .PADDING         (PADDING),
//     .IMAGE_WIDTH     (IMAGE_WIDTH),
//     .DATA_WIDTH      (DATA_WIDTH),
//     .NUM_PIXELS      (NUM_PIXELS),
//     .MAX_POOL_KERNEL (MAX_POOL_KERNEL)
//   ) dut (
//     .clk               (clk),
//     .rst               (rst),
//     .valid_in          (valid_in),
//     .pad_top           (pad_top),
//     .pad_bottom        (pad_bottom),
//     .next_channel      (next_channel),
//     .pixel_in          (pixel_in),
//     .kernel_weights    (kernel_weights),
//     .valid_out         (valid_out),
//     .current_channel   (current_channel),
//     .output_feature_map(output_feature_map),
//     .bram_en           (bram_en),
//     .bram_addr         (bram_addr)
//   );

//   integer i, j;
//   integer count;

//   //-------------------------------------------------------------------------
//   // Clock Generation: 10 ns period (5 ns high, 5 ns low)
//   //-------------------------------------------------------------------------
//   initial begin
//     clk = 0;
//     forever #5 clk = ~clk;
//   end

//   //-------------------------------------------------------------------------
//   // Reset Generation
//   //-------------------------------------------------------------------------
//   initial begin
//     rst = 1;
//     #15;
//     rst = 0;
//   end

//   //-------------------------------------------------------------------------
//   // Input Stimulus for Control Signals
//   //-------------------------------------------------------------------------
//   initial begin
//     // Initially, disable valid input and control signals
//     valid_in    = 0;
//     pad_top     = 0;  // Change to 1 if you want top row to be forced to zero
//     pad_bottom  = 0;  // Change to 1 if you want bottom row to be forced to zero
//     next_channel= 0;
    
//     // Start sending valid pixels and assert start for the convolution
//     #20;
//     valid_in = 1;
//     // next_channel can be driven as needed (here kept low)
//   end

//   //-------------------------------------------------------------------------
//   // Kernel Weights Initialization (in Q4.12 format)
//   //-------------------------------------------------------------------------
//   initial begin
//     // For example, set kernel weights to 1.0 (i.e. 4096 in Q4.12)
//     for(i = 0; i < KERNEL_SIZE; i = i + 1)
//       for(j = 0; j < KERNEL_SIZE; j = j + 1)
//         kernel_weights[i][j] = 16'd4096; // 1.0 in Q4.12
//   end

//   //-------------------------------------------------------------------------
//   // Pixel Input Stimulus (in Q4.12 format)
//   //-------------------------------------------------------------------------
//   // Simulate a stream of pixel values coming from the BRAM.
//   // The control unit in the top module will enable the line buffer when needed.
//   initial begin
//     pixel_in = 0;
//     count = 1;
//     forever begin
//       @(negedge clk);
//       if (bram_en) begin
//         // Scale count to Q4.12: multiply by 4096.
//         pixel_in = count * 16'd4096;
//         count = count + 1;
//       end else begin
//         pixel_in = 0;
//       end
//     end
//   end

//   //-------------------------------------------------------------------------
//   // Monitor Key Outputs for Debugging
//   //-------------------------------------------------------------------------
//   initial begin
//     $display("Time\t clk rst valid_in bram_en bram_addr output_feature_map");
//     forever begin
//       @(posedge clk);
//       $display("%0t\t %b   %b    %b       %b       %d", 
//                $time, rst, valid_in, bram_en, bram_addr, output_feature_map);
//     end
//   end

//   //-------------------------------------------------------------------------
//   // Simulation End
//   //-------------------------------------------------------------------------
//   initial begin
//     #10000; // Adjust simulation duration as necessary to see fill/update behavior.
//     $stop;
//   end

// endmodule


`timescale 1ns/1ps
module tb_conv2d_top;

  //-------------------------------------------------------------------------
  // Parameter Definitions (override top-level parameters for simulation)
  //-------------------------------------------------------------------------
  localparam IN_CHANNELS     = 4;
  localparam OUT_CHANNELS    = 8;
  localparam KERNEL_SIZE     = 3;
  localparam STRIDE          = 1;
  localparam PADDING         = 1;
  localparam IMAGE_WIDTH     = 16; // Reduced for simulation
  localparam DATA_WIDTH      = 16;
  localparam NUM_PIXELS      = 1;  // Processing one pixel (or one window) at a time
  localparam MAX_POOL_KERNEL = 2;

  //-------------------------------------------------------------------------
  // Testbench Signal Declarations
  //-------------------------------------------------------------------------
  logic clk, rst, valid_in, pad_top, pad_bottom, next_channel;
  logic signed [DATA_WIDTH-1:0] pixel_in;
  logic signed [DATA_WIDTH-1:0] kernel_weights [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];

  // Outputs from conv2d_top
  logic valid_out;
  logic [$clog2(IN_CHANNELS)-1:0] current_channel;
  logic signed [DATA_WIDTH-1:0] output_feature_map;
  logic bram_en;
  logic [DATA_WIDTH-1:0] bram_addr;

  //-------------------------------------------------------------------------
  // DUT Instantiation
  //-------------------------------------------------------------------------
  conv2d_top #(
    .IN_CHANNELS     (IN_CHANNELS),
    .OUT_CHANNELS    (OUT_CHANNELS),
    .KERNEL_SIZE     (KERNEL_SIZE),
    .STRIDE          (STRIDE),
    .PADDING         (PADDING),
    .IMAGE_WIDTH     (IMAGE_WIDTH),
    .DATA_WIDTH      (DATA_WIDTH),
    .NUM_PIXELS      (NUM_PIXELS),
    .MAX_POOL_KERNEL (MAX_POOL_KERNEL)
  ) dut (
    .clk               (clk),
    .rst               (rst),
    .valid_in          (valid_in),
    .pad_top           (pad_top),
    .pad_bottom        (pad_bottom),
    .next_channel      (next_channel),
    .pixel_in          (pixel_in),
    .kernel_weights    (kernel_weights),
    .valid_out         (valid_out),
    .current_channel   (current_channel),
    .output_feature_map(output_feature_map),
    .bram_en           (bram_en),
    .bram_addr         (bram_addr)
  );
 integer i, j;
 integer count;
  //-------------------------------------------------------------------------
  // Clock Generation: 10 ns period (5 ns high, 5 ns low)
  //-------------------------------------------------------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  //-------------------------------------------------------------------------
  // Reset Generation
  //-------------------------------------------------------------------------
  initial begin
    rst = 1;
    #15;
    rst = 0;
  end

  //-------------------------------------------------------------------------
  // Input Stimulus for Control Signals
  //-------------------------------------------------------------------------
  initial begin
    // Initially, disable valid input and control signals
    valid_in    = 0;
    pad_top     = 0;  // Change to 1 if you want top row to be forced to zero
    pad_bottom  = 0;  // Change to 1 if you want bottom row to be forced to zero
  
    next_channel= 0;
    
    // Start sending valid pixels and assert start for the convolution
    valid_in    = 1;
 
    // next_channel can be driven as needed (here kept low)
  end

  //-------------------------------------------------------------------------
  // Kernel Weights Initialization
  //-------------------------------------------------------------------------
  initial begin
   
    // For example, set kernel weights to a simple increasing pattern
    for(i = 0; i < KERNEL_SIZE; i = i + 1)
      for(j = 0; j < KERNEL_SIZE; j = j + 1)
        kernel_weights[i][j] = 1;
  end

  //-------------------------------------------------------------------------
  // Pixel Input Stimulus
  //-------------------------------------------------------------------------
  // Simulate a stream of pixel values coming from the BRAM.
  // The control unit in the top module will enable the line buffer when needed.
  initial begin
    pixel_in = 0;
    // Generate pixel stream continuously when valid_in is high.
    // This loop simulates enough pixels to cover both the fill phase and update phase.
    
    count = 1;
    forever begin
       @(negedge clk);
      if (bram_en) begin
        pixel_in = count;
        count = count + 1;
    end 
        else begin
            pixel_in=0;
        end

    end

  end

  //-------------------------------------------------------------------------
  // Monitor Key Outputs for Debugging
  //-------------------------------------------------------------------------
  initial begin
    $display("Time\t clk rst valid_in bram_en bram_addr output_feature_map");
    forever begin
      @(posedge clk);
      $display("%0t\t %b   %b    %b       %b       %d       ", 
               $time, rst, valid_in, bram_en, bram_addr, output_feature_map);
    end
  end

  //-------------------------------------------------------------------------
  // Simulation End
  //-------------------------------------------------------------------------
  initial begin
    #100000; // Adjust simulation duration as necessary to see fill/update behavior.
    $stop;
  end

endmodule





// module tb_conv2d_top;

//     // Parameters (using a smaller image width for simulation ease)
//     parameter IN_CHANNELS = 4;
//     parameter KERNEL_SIZE = 3;
//     parameter IMAGE_WIDTH = 12;  // Use a small width for simulation
//     parameter DATA_WIDTH = 16;
//     parameter NUM_PIXELS = 1;
//     parameter PADDING = 1;
//     parameter CLK_PERIOD = 10;   // 10 ns clock period

//     // Signals for conv2d_top
//     logic clk, rst, valid_in, pad_top, pad_bottom;
//     // Row-wise pixel input (one row per cycle for all channels)
//     logic signed [DATA_WIDTH-1:0] pixel_in;
//     // Kernel weights: one 3x3 weight per input channel (all set to 1 for simplicity)
//     logic signed [DATA_WIDTH-1:0] kernel_weights [KERNEL_SIZE][KERNEL_SIZE];
//     logic valid_out;
//     // Output feature map: NUM_PIXELS pixels per MAC cycle
//     logic signed [DATA_WIDTH-1:0] output_feature_map;

//     // Instantiate conv2d_top (which instantiates the line buffer and MAC unit)
//     conv2d_top #(
//         .IN_CHANNELS(IN_CHANNELS),
//         .OUT_CHANNELS(8),       // Not used directly in output in this top module
//         .KERNEL_SIZE(KERNEL_SIZE),
//         .STRIDE(1),
//         .PADDING(PADDING),
//         .IMAGE_WIDTH(IMAGE_WIDTH),
//         .DATA_WIDTH(DATA_WIDTH),
//         .NUM_PIXELS(NUM_PIXELS)
//     ) uut (
//         .clk(clk),
//         .rst(rst),
//         .valid_in(valid_in),
//         .pad_top(pad_top),
//         .pad_bottom(pad_bottom),
//         .pixel_in(pixel_in),
//         .kernel_weights(kernel_weights),
//         .valid_out(valid_out),
//         .output_feature_map(output_feature_map)
//     );

//     // Clock generation
//     always #(CLK_PERIOD/2) clk = ~clk;

//     // // Test Procedure
//     // initial begin
//     //     integer row, col, ch, i;
//     //     // Initialize signals
//     //     clk = 0;
//     //     rst = 1;
//     //     valid_in = 0;
//     //     pad_top = 0;
//     //     pad_bottom = 0;
//     //     // Initialize pixel_in to zero
//     //     for (ch = 0; ch < IN_CHANNELS; ch = ch + 1) begin
//     //         pixel_in[ch] = 0;
//     //     end

//     //     // Initialize kernel weights to all ones
//     //     for (ch = 0; ch < IN_CHANNELS; ch = ch + 1) begin
//     //         for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
//     //             kernel_weights[ch][i][0] = 1;
//     //             kernel_weights[ch][i][1] = 1;
//     //             kernel_weights[ch][i][2] = 1;
//     //         end
//     //     end

//     //     #20;
//     //     rst = 0;
//     //     valid_in = 1;

//     //     // Simulate the filling phase:
//     //     // We need to provide 3 rows of IMAGE_WIDTH pixels (one row per cycle).
//     //     // The line buffer will write into the valid region (with left/right padding preserved).
//     //     // Feed pixels into line buffer
//     //     for (int col = 0; col < 77; col++) begin
//     //         if (col == 0)begin
//     //             pad_top = 1;
//     //             #(10*IMAGE_WIDTH);
//     //         end else if(col == 69)begin
//     //             pad_bottom = 1;
//     //             #(10*IMAGE_WIDTH);
//     //         end
//     //         else begin
//     //             pad_top = 0;
//     //             pad_bottom = 0;
//     //         end
//     //         for (int ch = 0; ch < IN_CHANNELS; ch++) begin
//     //             pixel_in[ch] = col + ch * 10; // Assign unique values per channel
//     //         end
//     //         #10; // Wait for one clock cycle

//     //     end


//     //     // At this point, the buffer should be full.
//     //     // Now, allow additional cycles to exercise the sliding window update and MAC operation.
//     //     for (integer cycle = 0; cycle < 50; cycle = cycle + 1) begin
//     //         #(CLK_PERIOD);
//     //         if (valid_out) begin
//     //             $display("Cycle %0d: Output Feature Map: ", cycle);
//     //             for (i = 0; i < NUM_PIXELS; i = i + 1) begin
//     //                 $write("%0d ", output_feature_map[i]);
//     //             end
//     //             $display("");
//     //         end
//     //     end

//     //     $stop;
//     // end

// endmodule



// module tb_conv2d_top;

//     // Parameters
//     parameter IN_CHANNELS  = 4;
//     parameter OUT_CHANNELS = 16;  // Reduced for easier visualization
//     parameter KERNEL_SIZE  = 3;
//     parameter STRIDE       = 1;
//     parameter PADDING      = 1;
//     parameter IMAGE_WIDTH  = 10;  // Smaller width for testing
//     parameter DATA_WIDTH   = 16;
//     parameter CLK_PERIOD   = 10; // Clock period in ns
//     parameter NUM_PIXELS   = 3;  // Now handling 3 pixels per cycle

//     integer pass_count = 0;
//     integer fail_count = 0;

//     // Signals
//     logic clk, rst, valid_in, valid_out;
//     logic [DATA_WIDTH-1:0] pixel_in [IN_CHANNELS][KERNEL_SIZE]; // Now feeding 3 pixels per cycle
//     logic signed [DATA_WIDTH-1:0] kernel_weights [IN_CHANNELS][KERNEL_SIZE][KERNEL_SIZE];
//     logic signed [DATA_WIDTH-1:0] output_feature_map[NUM_PIXELS];
//     logic signed [DATA_WIDTH-1:0] expected_output[NUM_PIXELS];

//     // Instantiate the top module
//     conv2d_top #(
//         .IN_CHANNELS(IN_CHANNELS),
//         .OUT_CHANNELS(OUT_CHANNELS),
//         .KERNEL_SIZE(KERNEL_SIZE),
//         .STRIDE(STRIDE),
//         .PADDING(PADDING),
//         .IMAGE_WIDTH(IMAGE_WIDTH),
//         .DATA_WIDTH(DATA_WIDTH)
//     ) uut (
//         .clk(clk),
//         .rst(rst),
//         .valid_in(valid_in),
//         .pixel_in(pixel_in),
//         .kernel_weights(kernel_weights),
//         .valid_out(valid_out),
//         .output_feature_map(output_feature_map)
//     );

//     // Clock Generation
//     always begin
//         #(CLK_PERIOD/2) clk = ~clk;
//     end

//     // Compute Expected Output
//     task compute_expected_output();
//         integer c, i, j, p;
//         for (p = 0; p < NUM_PIXELS; p++) begin 
//             expected_output[p] = 0; // Reset expected output for each pixel
//             for (c = 0; c < IN_CHANNELS; c++) begin
//                 for (i = 0; i < KERNEL_SIZE; i++) begin
//                     for (j = 0; j < KERNEL_SIZE; j++) begin
//                         expected_output[p] += pixel_in[c][j] * kernel_weights[c][i][j]; 
//                     end
//                 end
//             end
          
//         end
//             #CLK_PERIOD;
//             #CLK_PERIOD;
//             check_results();
//     endtask

//     // Check Results
//     task check_results();
//         integer j;
//         for (j = 0; j < NUM_PIXELS; j++) begin
//             if (output_feature_map[j] !== expected_output[j]) begin
//                 $display("ERROR: Output mismatch at Pixel %0d. Expected: %0d, Got: %0d", 
//                          j, expected_output[j], output_feature_map[j]);
//                 fail_count++;
//             end else begin
//                 pass_count++;
//             end
//         end
//     endtask

//     // Test Procedure
//     initial begin
//         integer c, i, j, col;

//         // Initialize signals
//         clk = 0;
//         rst = 1;
//         valid_in = 0;

//         // Apply reset
//         #20 rst = 0;

//         // Load test kernel weights
//         for (c = 0; c < IN_CHANNELS; c++) begin
//             for (i = 0; i < KERNEL_SIZE; i++) begin
//                 for (j = 0; j < KERNEL_SIZE; j++) begin
//                     kernel_weights[c][i][j] = 1; // Assigning weights = 1 for easy checking
//                 end
//             end
//         end

//         // Simulate feeding 3 pixels per cycle, column-wise
//         for (col = 0; col < IMAGE_WIDTH; col++) begin
//             for (c = 0; c < IN_CHANNELS; c++) begin
//                 for (j = 0; j < KERNEL_SIZE; j++) begin
//                     if (col + j < IMAGE_WIDTH) 
//                         pixel_in[c][j] = col + j; // Assigning test values column-wise
//                     else
//                         pixel_in[c][j] = 0; // Padding beyond image width
//                 end
//             end

//             #CLK_PERIOD;
//             valid_in = 1;
//             // compute_expected_output(); // Compute expected output

        
//                 // check_results();
       
//         end

//         valid_in = 0;

//         // Wait for processing to complete
//         #500;
//         $display("Final Results: %0d Passed, %0d Failed", pass_count, fail_count);
//         $stop;
//     end

// endmodule
