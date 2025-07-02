
// first tb
// `timescale 1ns / 1ps

// module tb_line_buffer;
//     // Parameters
//     parameter IN_CHANNELS  = 4;
//     parameter IMAGE_WIDTH  = 9; // Reduced for testing
//     parameter KERNEL_SIZE  = 3;
//     parameter DATA_WIDTH   = 16;
//     parameter NUM_PIXELS   = 3;

//     // Signals
//     logic clk;
//     logic rst;
//     logic [DATA_WIDTH-1:0] pixel_in [IN_CHANNELS];
//     logic signed [DATA_WIDTH-1:0] window_out [IN_CHANNELS][KERNEL_SIZE][KERNEL_SIZE+NUM_PIXELS-1];
//     logic frame_end_flag, pad_top, pad_bottom;
    
//     // DUT Instantiation
//     line_buffer #(
//         .IN_CHANNELS(IN_CHANNELS),
//         .IMAGE_WIDTH(IMAGE_WIDTH),
//         .KERNEL_SIZE(KERNEL_SIZE),
//         .DATA_WIDTH(DATA_WIDTH)
//     ) dut (
//         .clk(clk),
//         .rst(rst),
//         .pixel_in(pixel_in),
//         .window_out(window_out),
//         .frame_end_flag(frame_end_flag), 
//         .pad_top(pad_top),
//         .pad_bottom(pad_bottom)
//     );

//     // Clock Generation
//     always #5 clk = ~clk; // 10ns period

//     // Test Procedure
//     initial begin
//         // Initialize
//         clk = 0;
//         rst = 1;
//         for (int i = 0; i < IN_CHANNELS; i++) pixel_in[i] = 0;
//         #20 rst = 0;

//         // Feed pixels into line buffer
//         for (int col = 0; col < 77; col++) begin
//             if (col == 0)begin
//                 pad_top = 1;
//                 #(10*IMAGE_WIDTH);
//             end else if(col == 69)begin
//                 pad_bottom = 1;
//                 #(10*IMAGE_WIDTH);
//             end
//             else begin
//                 pad_top = 0;
//                 pad_bottom = 0;
//             end
//             for (int ch = 0; ch < IN_CHANNELS; ch++) begin
//                 pixel_in[ch] = col + ch * 10; // Assign unique values per channel
//             end
//             #10; // Wait for one clock cycle

//         end

//         // Observe shifting and overwriting behavior
//         for (int col = 0; col < IMAGE_WIDTH; col += NUM_PIXELS) begin
//             #10;
//             $display("Window Output at col_index_window=%0d", col);
//             for (int ch = 0; ch < IN_CHANNELS; ch++) begin
//                 for (int j = 0; j < KERNEL_SIZE; j++) begin
//                     $write("Ch%0d Row%0d: ", ch, j);
//                     for (int k = 0; k < KERNEL_SIZE+NUM_PIXELS-1; k++) begin
//                         $write("%0d ", window_out[ch][j][k]);
//                     end
//                     $write("\n");
//                 end
//             end
//             $display("----------------------");
//         end

//         // Check Frame End Flag
//         if (frame_end_flag) begin
//             $display("Frame end flag is asserted. Window has reached end of image width.");
//         end else begin
//             $display("Frame end flag is NOT asserted yet.");
//         end

//         #20;
//         $stop;
//     end
// endmodule

//new tb

`timescale 1ns/1ps

module tb_line_buffer;

  //-------------------------------------------------------------------------
  // Parameter Declarations (use smaller image width for simulation)
  //-------------------------------------------------------------------------
  parameter IN_CHANNELS = 4;
  parameter IMAGE_WIDTH = 16;    // Reduced for simulation speed
  parameter KERNEL_SIZE = 3;
  parameter DATA_WIDTH  = 16;
  parameter NUM_PIXELS  = 1;     // Window width = KERNEL_SIZE + NUM_PIXELS - 1 = 5
  parameter PADDING     = 1;
  parameter STRIDE      = 1;
  parameter MAX_POOL    = 0;

  localparam WINDOW_WIDTH = KERNEL_SIZE + NUM_PIXELS - 1; 

  //-------------------------------------------------------------------------
  // Signal Declarations
  //-------------------------------------------------------------------------
  logic clk;
  logic rst;
  // Single pixel input (channel-by-channel)
  logic signed [DATA_WIDTH-1:0] pixel_in;
  // Padding control signals
  logic pad_top;
  logic pad_bottom;
  // Outputs from the line buffer
  logic signed [DATA_WIDTH-1:0] window_out [KERNEL_SIZE][WINDOW_WIDTH];
  logic [DATA_WIDTH-1:0] col_index_window;

  //-------------------------------------------------------------------------
  // DUT Instantiation: line_buffer module
  //-------------------------------------------------------------------------
  line_buffer #(
    .IN_CHANNELS(IN_CHANNELS),
    .IMAGE_WIDTH(IMAGE_WIDTH),
    .KERNEL_SIZE(KERNEL_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_PIXELS(NUM_PIXELS),
    .PADDING(PADDING),
    .STRIDE(STRIDE),
    .MAX_POOL(MAX_POOL)
  ) dut (
    .clk(clk),
    .rst(rst),
    .pixel_in(pixel_in),
    .pad_top(pad_top),
    .pad_bottom(pad_bottom),
    .window_out(window_out),
    .col_index_window(col_index_window)
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
  // We use an incrementing counter for pixel_in.
  // Because the module fills the memory channel-by-channel, each complete column
  // in a row requires IN_CHANNELS cycles. For IMAGE_WIDTH columns, one row takes
  // IMAGE_WIDTH*IN_CHANNELS cycles. With KERNEL_SIZE rows, the fill phase lasts
  // roughly KERNEL_SIZE * IMAGE_WIDTH * IN_CHANNELS cycles (here ~3*16*4 = 192 cycles).
  // We will also toggle pad_top and pad_bottom:
  //   - pad_top is asserted during the fill of the first row.
  //   - pad_bottom is asserted during the fill of the last row.
  integer cycle_count;
  integer total_cycles;
  reg [15:0] pixel_counter;

  initial begin
    // Initialize signals.
    rst          = 1;
    pad_top      = 0;
    pad_bottom   = 0;
    pixel_in     = 0;
    pixel_counter = 0;
    cycle_count   = 0;
    // Run enough cycles to cover fill (and a bit more for update/output).
    total_cycles  = 500;

    // Hold reset for 20 ns.
    #20;
    rst = 0;

    //-------------------------------------------------------------------------
    // Drive pixel_in over many cycles.
    //-------------------------------------------------------------------------
    // For the first row (fill row index == 0), assert pad_top.
    // With IMAGE_WIDTH=16 and IN_CHANNELS=4, one row takes 16*4 = 64 cycles.
    // Here we assert pad_top for roughly the first 70 cycles.
    for (cycle_count = 0; cycle_count < total_cycles; cycle_count = cycle_count + 1) begin
      // Assert pad_top during the fill of row 0.
      if (cycle_count < 70)
        pad_top = 1;
      else
        pad_top = 0;

      // Assert pad_bottom during fill of last row.
      // (Assuming row index reaches KERNEL_SIZE-1 near cycle 128.)
      if (cycle_count >= 128 && cycle_count < 192)
        pad_bottom = 0;
      else
        pad_bottom = 0;

      // Drive a new pixel value.
      pixel_in = pixel_counter;
      pixel_counter = pixel_counter + 1;

      // Wait one clock period (10 ns).
      #10;
    end

    // Allow additional time for update phase and window output generation.
    #100;

    //-------------------------------------------------------------------------
    // Display final results.
    //-------------------------------------------------------------------------
    $display("===============================================");
    $display("Final col_index_window = %0d", col_index_window);
    $display("Output Window for Selected Channel (3x5):");
    for (int j = 0; j < KERNEL_SIZE; j = j + 1) begin
      $write("Row %0d: ", j);
      for (int k = 0; k < WINDOW_WIDTH; k = k + 1) begin
        $write("%0d ", window_out[j][k]);
      end
      $write("\n");
    end
    $display("===============================================");

    #50;
    $stop;
  end

  //-------------------------------------------------------------------------
  // Optional Monitor: Print key signals on each clock cycle.
  //-------------------------------------------------------------------------
  initial begin
    $monitor("Time=%0t | rst=%b | pad_top=%b | pad_bottom=%b | pixel_in=%0d | col_index_window=%0d", 
             $time, rst, pad_top, pad_bottom, pixel_in, col_index_window);
  end

endmodule
