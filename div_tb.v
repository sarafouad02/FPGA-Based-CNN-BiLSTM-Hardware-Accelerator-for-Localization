`timescale 1ns/1ps
module Div_tb;

  // Parameters for the divider.
  localparam DATA_WIDTH = 16;
  localparam STEP       = 4;

  reg clk;
  reg reset;   // active-low reset
  reg start;
  reg [DATA_WIDTH-1:0] dividend;
  reg [DATA_WIDTH-1:0] divisor;
  wire [DATA_WIDTH-1:0] quotient;
  wire [DATA_WIDTH-1:0] remainder;
  wire done;

  // Instantiate the divider.
  Div #(DATA_WIDTH, STEP) dut (
    .clk(clk),
    .reset(reset),
    .start(start),
    .dividend(dividend),
    .divisor(divisor),
    .quotient(quotient),
    .remainder(remainder),
    .done(done)
  );

  // Clock generation: 10 ns period.
  always #5 clk = ~clk;

  initial begin
    // // Dump waves for debugging (if using a waveform viewer)
    // $dumpfile("tb_Div.vcd");
    // $dumpvars(0, tb_Div);
    
    // Initialize signals.
    clk = 0;
    start = 0;
    reset = 0; // apply reset (active low)

    // Apply reset.
    #20;
    reset = 1;

    // Test Case 1: 100 / 3
    @(posedge  clk);
    dividend = 16'd100;
    divisor  = 16'd4;
    start    = 1;
    @(posedge clk);
    start    = 0;
    wait(done);
    $display("Test 1: %d / %d = quotient: %d, remainder: %d", dividend, divisor, quotient, remainder);
    #20;

    // Test Case 2: 37 / 7
    @(negedge clk);
    dividend = 16'd50;
    divisor  = 16'd5;
    start    = 1;
    @(negedge clk);
    start    = 0;
    wait(done);
    $display("Test 2: %d / %d = quotient: %d, remainder: %d", dividend, divisor, quotient, remainder);
    #20;

    // Test Case 3: 65535 / 12345
    @(negedge clk);
    dividend = 16'd65535;
    divisor  = 16'd12345;
    start    = 1;
    @(negedge clk);
    start    = 0;
    wait(done);
    $display("Test 3: %d / %d = quotient: %d, remainder: %d", dividend, divisor, quotient, remainder);
    #20;

    // Test Case 4: 12345 / 1  (should return dividend)
    @(negedge clk);
    dividend = 16'd12345;
    divisor  = 16'd1;
    start    = 1;
    @(negedge clk);
    start    = 0;
    wait(done);
    $display("Test 4: %d / %d = quotient: %d, remainder: %d", dividend, divisor, quotient, remainder);
    #20;

    // Test Case 5: 0 / 7  (edge-case: dividend zero)
    @(negedge clk);
    dividend = 16'd0;
    divisor  = 16'd7;
    start    = 1;
    @(negedge clk);
    start    = 0;
    wait(done);
    $display("Test 5: %d / %d = quotient: %d, remainder: %d", dividend, divisor, quotient, remainder);
    #20;

    $stop;
  end

endmodule


// `timescale 1ns/1ps
// module Div_tb;

//   // Parameters for the divider.
//   localparam DATA_WIDTH = 16;
//   // You can set STEP to any value; here we try 3 to illustrate a case where
//   // DATA_WIDTH (16) is not an exact multiple of STEP.
//   localparam STEP       = 5;

//   reg clk;
//   reg reset;   // active-low reset
//   reg start;
//   reg [DATA_WIDTH-1:0] dividend;
//   reg [DATA_WIDTH-1:0] divisor;
//   wire [DATA_WIDTH-1:0] quotient;
//   wire [DATA_WIDTH-1:0] remainder;
//   wire done;

//   // Instantiate the divider.
//   Div #(DATA_WIDTH, STEP) dut (
//     .clk(clk),
//     .reset(reset),
//     .start(start),
//     .dividend(dividend),
//     .divisor(divisor),
//     .quotient(quotient),
//     .remainder(remainder),
//     .done(done)
//   );

//   // Clock generation: 10 ns period.
//   always #5 clk = ~clk;

//   initial begin
//     // Dump waveforms for simulation viewing.
    
//     // Initialize signals.
//     clk = 0;
//     start = 0;
//     reset = 0; // Apply reset (active low)

//     #20;
//     reset = 1;

//     // Test Case 1: 100 / 3
//     @(negedge clk);
//     dividend = 16'd100;
//     divisor  = 16'd4;
//     start    = 1;
//     @(negedge clk);
//     start    = 0;
//     wait(done);
//     $display("Test 1: %d / %d = quotient: %d, remainder: %d", dividend, divisor, quotient, remainder);
//     #20;

//     // Test Case 2: 37 / 7
//     @(negedge clk);
//     dividend = 16'd50;
//     divisor  = 16'd10;
//     start    = 1;
//     @(negedge clk);
//     start    = 0;
//     wait(done);
//     $display("Test 2: %d / %d = quotient: %d, remainder: %d", dividend, divisor, quotient, remainder);
//     #20;

//     // Test Case 3: 65535 / 12345
//     @(negedge clk);
//     dividend = 16'd65535;
//     divisor  = 16'd12345;
//     start    = 1;
//     @(negedge clk);
//     start    = 0;
//     wait(done);
//     $display("Test 3: %d / %d = quotient: %d, remainder: %d", dividend, divisor, quotient, remainder);
//     #20;

//     // Test Case 4: 12345 / 1  (should return dividend)
//     @(negedge clk);
//     dividend = 16'd12345;
//     divisor  = 16'd1;
//     start    = 1;
//     @(negedge clk);
//     start    = 0;
//     wait(done);
//     $display("Test 4: %d / %d = quotient: %d, remainder: %d", dividend, divisor, quotient, remainder);
//     #20;

//     // Test Case 5: 0 / 7  (edge-case: dividend zero)
//     @(negedge clk);
//     dividend = 16'd0;
//     divisor  = 16'd7;
//     start    = 1;
//     @(negedge clk);
//     start    = 0;
//     wait(done);
//     $display("Test 5: %d / %d = quotient: %d, remainder: %d", dividend, divisor, quotient, remainder);
//     #20;

//     $finish;
//   end

// endmodule

