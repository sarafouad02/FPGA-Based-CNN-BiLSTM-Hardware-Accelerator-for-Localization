`timescale 1ns/1ps

module tb_maxpool_buffer;

  // Parameters for the testbench. Using a small IMAGE_WIDTH for easier simulation.
  localparam DATA_WIDTH  = 16;
  localparam IMAGE_WIDTH = 8; // For simulation only

  // DUT interface signals
  logic                       clk;
  logic                       rst;
  logic                       en;         // Enable signal for incoming pixel data
  logic                       win_update; // Signal to update window pointer (stride control)
  logic [DATA_WIDTH-1:0]      pixel_in;
  logic                       valid_window;
  logic [DATA_WIDTH-1:0]      window [0:1][0:1];

  // Instantiate the DUT
  maxpool_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .IMAGE_WIDTH(IMAGE_WIDTH), 
    .KERNEL_SIZE(2), 
    .STRIDE     (2)
  ) dut (
    .clk(clk),
    .rst(rst),
    .en(en),
    .win_update(win_update),
    .pixel_in(pixel_in),
    .valid_window(valid_window),
    .window(window)
  );

  // Clock generation: 10ns period
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset generation: Assert reset at the beginning
  initial begin
    rst = 1;
    #20;
    rst = 0;
  end

  // Testbench stimulus
  initial begin
    integer i;
    // Initialize control signals
    en         = 0;
    win_update = 0;
    pixel_in   = 0;
    
    // Wait for reset de-assertion
    @(negedge rst);
    #10;
    
    $display("=== Starting Row0 Fill ===");
    // Fill row0: send IMAGE_WIDTH pixels with distinct values (1,2,...,IMAGE_WIDTH)
    for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
      @(posedge clk);
      en       = 1;
      pixel_in = i + 1;
      $display("Row0[%0d] <= %0d", i, pixel_in);
    end
    @(posedge clk);
    en = 0;
    
    // At this point, row0 is complete. Since row1 is not filled, valid_window should be low.
    #10;
    if (valid_window !== 1) begin
      $display("As expected, valid_window is LOW after row0 fill (row1 not ready).");
    end else begin
      $display("ERROR: valid_window should not be high yet!");
    end

    $display("=== Starting Row1 Fill ===");
    // Fill row1: use a different pattern (e.g., 101, 102, ... for clarity)
    for (i = 0; i < IMAGE_WIDTH; i = i + 1) begin
      @(posedge clk);
      en       = 1;
      pixel_in = 101 + i;
      $display("Row1[%0d] <= %0d", i, pixel_in);
    end
    @(posedge clk);
    en = 0;
    
    // Wait a few cycles for the data to settle
    #10;
    
    // Now both rows have sufficient data so valid_window should be high.
    if (valid_window !== 1) begin
      $display("ERROR: valid_window is LOW after both rows are filled!");
    end else begin
      $display("Valid window detected.");
    end

    // Check initial window (should be from columns 0 and 1)
    $display("Initial Window (win_ptr = 0):");
    $display("  row0[0] = %0d, row0[1] = %0d", window[0][0], window[0][1]);
    $display("  row1[0] = %0d, row1[1] = %0d", window[1][0], window[1][1]);

    // Apply window update to shift the window by stride=2.
    $display("=== Updating Window Pointer (Stride=2) ===");
    win_update = 1;
    @(posedge clk);
    win_update = 0;
    #10;
    $display("After 1st win_update (win_ptr should now be 2):");
    $display("  row0[2] = %0d, row0[3] = %0d", window[0][0], window[0][1]);
    $display("  row1[2] = %0d, row1[3] = %0d", window[1][0], window[1][1]);

    // Second window update
    win_update = 1;
    @(posedge clk);
    win_update = 0;
    #10;
    $display("After 2nd win_update (win_ptr should now be 4):");
    $display("  row0[4] = %0d, row0[5] = %0d", window[0][0], window[0][1]);
    $display("  row1[4] = %0d, row1[5] = %0d", window[1][0], window[1][1]);

    // Third update should push pointer to 6 (last valid window: columns 6 and 7)
    win_update = 1;
    @(posedge clk);
    win_update = 0;
    #10;
    $display("After 3rd win_update (win_ptr should now be 6):");
    $display("  row0[6] = %0d, row0[7] = %0d", window[0][0], window[0][1]);
    $display("  row1[6] = %0d, row1[7] = %0d", window[1][0], window[1][1]);

    // Fourth update: pointer should wrap around to 0
    win_update = 1;
    @(posedge clk);
    win_update = 0;
    #10;
    $display("After 4th win_update (win_ptr should wrap-around to 0):");
    $display("  row0[0] = %0d, row0[1] = %0d", window[0][0], window[0][1]);
    $display("  row1[0] = %0d, row1[1] = %0d", window[1][0], window[1][1]);

    $display("=== Testbench Completed ===");
    $finish;
  end

endmodule
