`timescale 1ns/1ps

module tb_mac_array;

  // Parameters must match the DUT
  parameter IN_CHANNELS  = 4;
  parameter KERNEL_SIZE  = 3;
  parameter DATA_WIDTH   = 16;
  parameter NUM_PIXELS   = 1;
  parameter FRAC_SZ      = 14;

  // Clock, reset, control signals
  logic clk;
  logic rst;
  logic start;

  // Input arrays
  logic signed [DATA_WIDTH-1:0] input_feature_map [KERNEL_SIZE][KERNEL_SIZE];
  logic signed [DATA_WIDTH-1:0] kernel_weights   [KERNEL_SIZE][KERNEL_SIZE];
  logic [DATA_WIDTH-1:0] col_index_window;

  // Outputs
  logic signed [DATA_WIDTH-1:0] mac_output;
  logic done;

  // Instantiate the DUT
  mac_array #(
    .IN_CHANNELS(IN_CHANNELS),
    .KERNEL_SIZE(KERNEL_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_PIXELS(NUM_PIXELS),
    .FRAC_SZ(FRAC_SZ)
  ) dut (
    .clk(clk),
    .rst(rst),
    .start(start),
    .input_feature_map(input_feature_map),
    .kernel_weights(kernel_weights),
    .col_index_window(col_index_window),
    .mac_output(mac_output),
    .done(done)
  );

  // Clock generation: 6ns period
  always #3 clk = ~clk;

  // Golden-model storage
  int signed golden_array [NUM_PIXELS];
  logic signed [DATA_WIDTH-1:0] expected;
   // Random stimulus for each channel
  int signed featmap [IN_CHANNELS][KERNEL_SIZE][KERNEL_SIZE+NUM_PIXELS-1];
  int signed kern    [IN_CHANNELS][KERNEL_SIZE][KERNEL_SIZE];
  int signed sum = 0;
   int signed psum = 0;
  // Counters
  int error_count;
  int total_tests;

  localparam signed [31:0] SAT_POS = ((1 << (DATA_WIDTH-FRAC_SZ-1)) - 1) << FRAC_SZ;  // +7
  localparam signed [31:0] SAT_NEG = -(((1 << (DATA_WIDTH-FRAC_SZ-1)) - 1) << FRAC_SZ); // -7

  // Saturated output logic
  logic signed [DATA_WIDTH-1:0] sat_out;

  initial begin
    // Initialize signals
    clk = 0;
    rst = 1;
    start = 0;
    col_index_window = '0;
    error_count = 0;
    total_tests = 100;

    // Reset pulse
    repeat (2) @(posedge clk);
    rst = 0;

    // Main test loop
    for (int t = 0; t < total_tests; t++) begin

     
      rst = 1; @(posedge clk); @(posedge clk); rst = 0;

      // Generate random Q4.12 fixed-point values
      foreach (featmap[ch,i,j]) begin
        featmap[ch][i][j] = 16'h03D7;


        //$urandom_range(-(1<<(DATA_WIDTH-1)), (1<<(DATA_WIDTH-1))-1);
      end
       // Use constant weight = 1.0 (Q4.12 representation)
      foreach (kern[ch,i,j]) begin
        kern[ch][i][j] = 16'h03D7;


      end

      // Compute golden model per pixel
      for (int p = 0; p < NUM_PIXELS; p++) begin
        sum = 0;
        for (int ch = 0; ch < IN_CHANNELS; ch++) begin
         psum=0;
          for (int i = 0; i < KERNEL_SIZE; i++) begin
            for (int j = 0; j < KERNEL_SIZE; j++) begin
              psum += featmap[ch][i][j + p] * kern[ch][i][j];

            end
          end
          @(posedge clk);
          // Adjust back from Q8.24 to Q4.12
          psum = psum >>> FRAC_SZ;
          @(posedge clk);
          sum  += psum;
          @(posedge clk);
        end
        golden_array[p] = sum;
      end

      // -------- Apply inputs to DUT --------
      // Channel 0 applied for two cycles: first to fill pipeline, second to assert start
      //for (int c = 0; c < 2; c++) begin
        // Drive channel 0 data
        for (int i = 0; i < KERNEL_SIZE; i++) begin
          for (int j = 0; j < KERNEL_SIZE+NUM_PIXELS-1; j++)
            input_feature_map[i][j] = featmap[0][i][j];
          for (int j = 0; j < KERNEL_SIZE; j++)
            kernel_weights[i][j] = kern[0][i][j];
        end
        // Assert start only on second cycle
        start = 1;
        @(posedge clk);
        start =0;
      //end

      // Apply remaining channels sequentially
      for (int ch = 1; ch < IN_CHANNELS; ch++) begin
        for (int i = 0; i < KERNEL_SIZE; i++) begin
          for (int j = 0; j < KERNEL_SIZE+NUM_PIXELS-1; j++)
            input_feature_map[i][j] = featmap[ch][i][j];
          for (int j = 0; j < KERNEL_SIZE; j++)
            kernel_weights[i][j] = kern[ch][i][j];
        end
        // start = 0;
        @(posedge clk);
      end

      // Wait for 'done' from DUT
      wait (done);
      @(posedge clk);


    if (!done)
      sat_out = '0;
    else if (golden_array[0] > SAT_POS)
      sat_out = SAT_POS[DATA_WIDTH-1:0];
    else if (golden_array[0] < SAT_NEG)
      sat_out = SAT_NEG[DATA_WIDTH-1:0];
    else
      sat_out = golden_array[0][DATA_WIDTH-1:0];
  


      // Check output (pixel 0)
      expected = sat_out;
      if (mac_output !== expected) begin
        $display("[ERROR] Test %0d: Expected %0d, Got %0d", t, expected, mac_output);
        error_count++;
      end else begin
        $display("[PASS] Test %0d: %0d", t, mac_output);
      end

    end // for t

    // Summary
    $display("Testbench finished: %0d tests, %0d errors", total_tests, error_count);
    $finish;
  end

endmodule





// `timescale 1ns/1ps
// module tb_mac_array;

//   //-------------------------------------------------------------------------
//   // Parameter Definitions
//   //-------------------------------------------------------------------------
//   localparam IN_CHANNELS = 4;
//   localparam KERNEL_SIZE = 3;
//   localparam DATA_WIDTH  = 16;
//   localparam NUM_PIXELS  = 1;
//   localparam IMAGE_WIDTH = 188;
//   localparam PADDING     = 1;

//   //-------------------------------------------------------------------------
//   // Signal Declarations
//   //-------------------------------------------------------------------------
//   logic clk, rst;
//   logic start;
//   // Although col_index_window is not used in the computation, we drive it to 0.
//   logic [DATA_WIDTH-1:0] col_index_window;  
//   // input_feature_map: dimensions [KERNEL_SIZE][KERNEL_SIZE+NUM_PIXELS-1]
//   logic signed [DATA_WIDTH-1:0] input_feature_map [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
//   // kernel_weights: dimensions [KERNEL_SIZE][KERNEL_SIZE]
//   logic signed [DATA_WIDTH-1:0] kernel_weights [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
//   // mac_output is intended as an array of NUM_PIXELS outputs.
//   logic signed [DATA_WIDTH-1:0] mac_output;
//   logic done;

//   //-------------------------------------------------------------------------
//   // DUT Instantiation
//   //-------------------------------------------------------------------------
//   mac_array #(
//       .IN_CHANNELS(IN_CHANNELS),
//       .KERNEL_SIZE(KERNEL_SIZE),
//       .DATA_WIDTH(DATA_WIDTH),
//       .NUM_PIXELS(NUM_PIXELS),
//       .IMAGE_WIDTH(IMAGE_WIDTH),
//       .PADDING(PADDING)
//   ) dut (
//       .clk(clk),
//       .rst(rst),
//       .start(start),
//       .input_feature_map(input_feature_map),
//       .kernel_weights(kernel_weights),
//       .col_index_window(col_index_window),
//       .mac_output(mac_output),
//       .done(done)
//   );

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
//     #20;
//     rst = 0;
//   end

//   //-------------------------------------------------------------------------
//   // Kernel Weights and col_index_window Initialization
//   //-------------------------------------------------------------------------
//   integer i, j, k;
//   initial begin
//     // Set kernel_weights to all ones.
//     for (i = 0; i < KERNEL_SIZE; i = i + 1)
//       for (j = 0; j < KERNEL_SIZE; j = j + 1)
//          kernel_weights[i][j] = 1;
//     // Drive col_index_window to zero.
//     col_index_window = 0;
//   end

//   //-------------------------------------------------------------------------
//   // Input Feature Map and Start Signal Stimulus
//   //-------------------------------------------------------------------------
//   // The accumulation in mac_array is initiated in IDLE with a start pulse. Then,
//   // over successive clock cycles (while in ACCUMULATE state) the module adds the current
//   // partial sum. We mimic separate channels by changing the entire input_feature_map each cycle.
//   initial begin
//     // Initialize start low.
//     start = 0;
//     // Wait for reset deassertion.
//     @(negedge rst);
//     #10;
    
//     // --- Channel 0 (IDLE phase) ---
//     // Set entire input_feature_map to 1.
//     for (i = 0; i < KERNEL_SIZE; i = i + 1)
//       for (j = 0; j < KERNEL_SIZE+NUM_PIXELS-1; j = j + 1)
//          input_feature_map[i][j] = 1;
//     $display("Time %0t: Channel 0 input_feature_map set to 1", $time);
    
//     // Pulse start to capture channel 0's data.
//     start = 1;
   
    
//     // --- Channel 1 (First ACCUMULATE cycle) ---
//     @(posedge clk);
//     for (i = 0; i < KERNEL_SIZE; i = i + 1)
//       for (j = 0; j < KERNEL_SIZE+NUM_PIXELS-1; j = j + 1)
//          input_feature_map[i][j] = 2;
//     $display("Time %0t: Channel 1 input_feature_map set to 2", $time);
    
//     // --- Channel 2 (Second ACCUMULATE cycle) ---
//     @(posedge clk);
//     for (i = 0; i < KERNEL_SIZE; i = i + 1)
//       for (j = 0; j < KERNEL_SIZE+NUM_PIXELS-1; j = j + 1)
//          input_feature_map[i][j] = 3;
//     $display("Time %0t: Channel 2 input_feature_map set to 3", $time);
    
//     // --- Channel 3 (If applicable) ---
//     // With the current FSM the DONE state is reached after processing channel 2 (accumulated over 3 channels:
//     // channel 0 in IDLE plus channels 1 and 2 in ACCUMULATE). Therefore, channel 3 may not be accumulated.
//     @(posedge clk);
//     for (i = 0; i < KERNEL_SIZE; i = i + 1)
//       for (j = 0; j < KERNEL_SIZE+NUM_PIXELS-1; j = j + 1)
//          input_feature_map[i][j] = 4;
//     $display("Time %0t: Channel 3 input_feature_map set to 4", $time);
    
//     //-------------------------------------------------------------------------
//     // Wait for the module to assert done.
//     //-------------------------------------------------------------------------
//     // wait(done == 1);
//     // @(posedge clk);
//     // $display("Time %0t: MAC accumulation DONE.", $time);
//     // for (k = 0; k < NUM_PIXELS; k = k + 1)
//     //    $display("mac_output[%0d] = %0d", k, mac_output[k]);
    
//     //-------------------------------------------------------------------------
//     // Expected Result Calculation:
//     // For a kernel of ones and an input_feature_map filled with a constant X,
//     // each partial sum is: partial_sum = 9 * X.
//     // With the values driven:
//     //   Channel 0: 1  -> partial_sum = 9
//     //   Channel 1: 2  -> partial_sum = 18
//     //   Channel 2: 3  -> partial_sum = 27
//     // Total accumulated = 9 + 18 + 27 = 54.
//     // (Channel 3 is not processed by the current FSM.)
//     // //-------------------------------------------------------------------------
//     // if ((mac_output[0] == 54) && (mac_output[1] == 54) && (mac_output[2] == 54))
//     //   $display("TEST PASS: Accumulated result is as expected (54).");
//     // else
//     //   $display("TEST FAIL: Accumulated result is not as expected.");
    
//     #500;
//     $stop;
//   end

// endmodule



// module tb_mac_array;

//     // Parameters
//     parameter IN_CHANNELS  = 4;
//     parameter OUT_CHANNELS = 8;  // Reduced for easier visualization
//     parameter KERNEL_SIZE  = 3;
//     parameter DATA_WIDTH   = 16;
//     parameter CLK_PERIOD   = 10; // Clock period: 10 ns

//     // Signals
//     logic clk, rst;
//     logic signed [DATA_WIDTH-1:0] input_feature_map [IN_CHANNELS][KERNEL_SIZE][KERNEL_SIZE];
//     logic signed [DATA_WIDTH-1:0] kernel_weights [OUT_CHANNELS][IN_CHANNELS][KERNEL_SIZE][KERNEL_SIZE];
//     logic signed [DATA_WIDTH-1:0] mac_output [OUT_CHANNELS];

//     // Instantiate the MAC array module
//     mac_array #(
//         .IN_CHANNELS(IN_CHANNELS),
//         .OUT_CHANNELS(OUT_CHANNELS),
//         .KERNEL_SIZE(KERNEL_SIZE),
//         .DATA_WIDTH(DATA_WIDTH)
//     ) uut (
//         .clk(clk),
//         .rst(rst),
//         .input_feature_map(input_feature_map),
//         .kernel_weights(kernel_weights),
//         .mac_output(mac_output)
//     );

//     // Clock Generation
//     always begin
//         #(CLK_PERIOD/2) clk = ~clk;
//     end

//     // Test Procedure
//     initial begin
//         integer o, c, i, j;

//         // Initialize Signals
//         clk = 0;
//         rst = 1;
//  // Apply input values
//         for (c = 0; c < IN_CHANNELS; c++) begin
//             for (i = 0; i < KERNEL_SIZE; i++) begin
//                 for (j = 0; j < KERNEL_SIZE; j++) begin
//                     input_feature_map[c][i][j] = 0; // Some sample values
//                 end
//             end
//         end

//         // Apply kernel values
//         for (o = 0; o < OUT_CHANNELS; o++) begin
//             for (c = 0; c < IN_CHANNELS; c++) begin
//                 for (i = 0; i < KERNEL_SIZE; i++) begin
//                     for (j = 0; j < KERNEL_SIZE; j++) begin
//                         kernel_weights[o][c][i][j] = 0; // Some weights
//                     end
//                 end
//             end
//         end

//         // Reset module
//         #20 rst = 0;  

//         // Apply input values
//         for (c = 0; c < IN_CHANNELS; c++) begin
//             for (i = 0; i < KERNEL_SIZE; i++) begin
//                 for (j = 0; j < KERNEL_SIZE; j++) begin
//                     input_feature_map[c][i][j] = j; // Some sample values
//                 end
//             end
//         end

//         // Apply kernel values
//         for (o = 0; o < OUT_CHANNELS; o++) begin
//             for (c = 0; c < IN_CHANNELS; c++) begin
//                 for (i = 0; i < KERNEL_SIZE; i++) begin
//                     for (j = 0; j < KERNEL_SIZE; j++) begin
//                         kernel_weights[o][c][i][j] = j; // Some weights
//                     end
//                 end
//             end
//         end

//         // Wait for MAC operations
//         #50;

//         // Print results
//         $display("MAC Output:");
//         for (o = 0; o < OUT_CHANNELS; o++) begin
//             $display("Output Channel %0d: %0d", o, mac_output[o]);
//         end

//         $stop;
//     end

// endmodule

