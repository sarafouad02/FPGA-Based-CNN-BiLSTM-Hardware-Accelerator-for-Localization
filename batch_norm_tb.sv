module tb_batch_norm_fsm;;
  // Parameters
  parameter DATA_WIDTH = 16;
  parameter FRAC_SZ    = 12;

  // Inputs
  reg clk;
  reg rst;
  reg enable;
  reg bnfifo_read_flag;
  reg signed [DATA_WIDTH-1:0] bn_input;
  reg signed [DATA_WIDTH-1:0] mean_mov;
  reg signed [DATA_WIDTH-1:0] std_mov;
  reg signed [DATA_WIDTH-1:0] gamma;
  reg signed [DATA_WIDTH-1:0] beta;

  // Outputs
  wire bn_done;
  wire ready;
  wire signed [DATA_WIDTH-1:0] bn_output;

  // Instantiate DUT
  batch_norm #(
    .DATA_WIDTH(DATA_WIDTH),
    .FRAC_SZ   (FRAC_SZ)
  ) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .bnfifo_read_flag(bnfifo_read_flag),
    .bn_input(bn_input),
    .mean_mov(mean_mov),
    .std_mov(std_mov),
    .gamma(gamma),
    .beta(beta),
    .bn_done(bn_done),
    .ready(ready),
    .bn_output(bn_output)
  );

  // Clock generation (10ns period)
  initial clk = 0;
  always #5 clk = ~clk;

  // Task to perform a single batch-norm operation
  task do_batch_norm;
    input signed [DATA_WIDTH-1:0] x;
    input signed [DATA_WIDTH-1:0] m;
    input signed [DATA_WIDTH-1:0] s;
    input signed [DATA_WIDTH-1:0] g;
    input signed [DATA_WIDTH-1:0] b;
    begin
      // Apply parameters
      mean_mov = m;
      std_mov  = s;
      gamma    = g;
      beta     = b;

      // Start normalization
      @(negedge clk);
      enable = 1;
      @(negedge clk);
      enable = 0;

      // Provide input sample when DUT is ready
      wait (ready);
      @(negedge clk);
      bn_input          = x;
      bnfifo_read_flag  = 1;
      @(negedge clk);
      bnfifo_read_flag  = 0;

      // Wait for completion
      wait (bn_done);
      @(negedge clk);
      // Display result in decimal
      $display("BN: input=%0f, mean=%0f, std=%0f, gamma=%0f, beta=%0f -> output=%0f", 
               $itor(x)/2.0**FRAC_SZ, $itor(m)/2.0**FRAC_SZ,
               $itor(s)/2.0**FRAC_SZ, $itor(g)/2.0**FRAC_SZ,
               $itor(b)/2.0**FRAC_SZ, $itor(bn_output)/2.0**FRAC_SZ);
    end
  endtask

  // Test sequence
  initial begin
    // Initialize inputs
    rst               = 1;
    enable            = 0;
    bnfifo_read_flag  = 0;
    bn_input          = 0;
    mean_mov          = 0;
    std_mov           = (1 << FRAC_SZ); // default 1.0
    gamma             = (1 << FRAC_SZ);
    beta              = 0;

    // Release reset
    #20;
    rst = 0;

    // Test cases (Q4.12):
    //  input=2.0, mean=1.0, std=0.5, gamma=1.0, beta=0.0 -> (2-1)/0.5=2.0
    do_batch_norm(16'sd8192, 16'sd4096, 16'sd2048, 16'sd4096, 16'sd0);
    
    // input=1.5, mean=1.0, std=1.0, gamma=2.0, beta=0.5 -> 2*(0.5)+0.5=1.5
    do_batch_norm(16'sd6144, 16'sd4096, 16'sd4096, 16'sd8192, 16'sd2048);

    // input=-1.0, mean=0.0, std=1.0, gamma=1.0, beta=0.0 -> -1.0
    do_batch_norm(-16'sd4096, 16'sd0, 16'sd4096, 16'sd4096, 16'sd0);

    // // Random tests
    // repeat (5) begin
    //   reg signed [DATA_WIDTH-1:0] rx, rm, rs, rg, rb;
    //   rx = $random;
    //   rm = $random;
    //   rs = $random;
    //   if (rs == 0) rs = (1<<FRAC_SZ);
    //   rg = $random;
    //   rb = $random;
    //   wg: do_batch_norm(rx, rm, rs, rg, rb);
    // end

    $display("Batch-norm testbench completed.");
    $stop;
  end

endmodule


// `timescale 1ns/1ps
// module tb_batch_norm_fsm;

//   //-------------------------------------------------------------------------
//   // Parameter Declarations
//   //-------------------------------------------------------------------------
//   localparam DATA_WIDTH = 16;
//   localparam NUM_PIXELS = 3; // Not used in this single–output version

//   //-------------------------------------------------------------------------
//   // Signal Declarations
//   //-------------------------------------------------------------------------
//   logic clk, rst;
//   logic enable;
//   logic signed [DATA_WIDTH-1:0] mac_output;
//   logic signed [DATA_WIDTH-1:0] mean_mov;
//   logic signed [DATA_WIDTH-1:0] var_mov;
//   logic signed [DATA_WIDTH-1:0] gamma;
//   logic signed [DATA_WIDTH-1:0] beta;
//   logic signed [DATA_WIDTH-1:0] bn_output;

//   //-------------------------------------------------------------------------
//   // DUT Instantiation
//   //-------------------------------------------------------------------------
//   batch_norm_fsm #(
//       .DATA_WIDTH(DATA_WIDTH),
//       .NUM_PIXELS(NUM_PIXELS)
//   ) dut (
//       .clk(clk),
//       .rst(rst),
//       .enable(enable),
//       .mac_output(mac_output),
//       .mean_mov(mean_mov),
//       .var_mov(var_mov),
//       .gamma(gamma),
//       .beta(beta),
//       .bn_output(bn_output)
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
//   // Test Stimulus
//   //-------------------------------------------------------------------------
//   initial begin
//     // Initialize all inputs.
//     enable      = 0;
//     mac_output  = 0;
//     mean_mov    = 0;
//     var_mov     = 0;
//     gamma       = 0;
//     beta        = 0;
    
//     // Wait for reset deassertion.
//     @(negedge rst);
//     #10;
    
//     // Set test values.
//     mac_output = 1620;  // Example: convolution output
//     mean_mov   = 500;
//     var_mov    = 15;    // So var_mov+1 = 16, and sqrt(16)=4
//     gamma      = 2;
//     beta       = 10;
    
//     // Pulse 'enable' for one cycle to start the computation.
//     enable = 1;
//     @(posedge clk);
//     enable = 0;
    
//     // Wait long enough for the FSM to complete its work.
//     // For DATA_WIDTH=16, the SQRT_LOOP runs for ~8 cycles, plus one each for NORMALIZE and SCALE.
//     // Adding a few extra cycles to be safe.
//     repeat (15) @(posedge clk);
    
//     // Display the output.
//     $display("-----------------------------------------------------");
//     $display("Time = %0t ns", $time);
//     $display("mac_output = %0d, mean_mov = %0d, var_mov = %0d", mac_output, mean_mov, var_mov);
//     $display("gamma = %0d, beta = %0d", gamma, beta);
//     $display("bn_output = %0d (expected = 260)", bn_output);
//     if (bn_output == 260)
//       $display("TEST PASS: bn_output is as expected.");
//     else
//       $display("TEST FAIL: bn_output is not as expected.");
//     $display("-----------------------------------------------------");
    
//     #20;
//     $finish;
//   end

// endmodule
