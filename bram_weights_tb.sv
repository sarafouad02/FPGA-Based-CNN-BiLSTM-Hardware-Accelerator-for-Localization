`timescale 1ns/1ps

module bram_weights_tb;
  // ---------------------------------------------------------
  // Testbench parameters (small for example)
  // ---------------------------------------------------------
  localparam int DATA_WIDTH      = 16;
  localparam int IN_CHANNELS     = 4;
  localparam int OUT_CHANNELS    = 64;
  localparam int KERNEL_SIZE     = 3;
  localparam int KERNEL_ELEM_NUM = KERNEL_SIZE * KERNEL_SIZE;
  localparam int MEM_DEPTH       = OUT_CHANNELS * IN_CHANNELS * KERNEL_ELEM_NUM;
  localparam int ADDR_WIDTH      = $clog2(MEM_DEPTH);

  // ---------------------------------------------------------
  // Clock & Reset
  // ---------------------------------------------------------
  logic clk;
  logic rst_n;
  initial clk = 0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------
  // DUT IO
  // ---------------------------------------------------------
  logic                  start_stream;
  logic                  weight_valid;
  logic signed [DATA_WIDTH-1:0] weight_data;

  // ---------------------------------------------------------
  // Instantiate DUT
  // ---------------------------------------------------------
  bram_weights #(
    .DATA_WIDTH   (DATA_WIDTH),
    .IN_CHANNELS  (IN_CHANNELS),
    .OUT_CHANNELS (OUT_CHANNELS),
    .KERNEL_SIZE  (KERNEL_SIZE)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start_stream(start_stream),
    .weight_valid(weight_valid),
    .weight_data(weight_data)
  );

  // ---------------------------------------------------------
  // Initialize memory file and preload BRAM
  // ---------------------------------------------------------

  // ---------------------------------------------------------
  // Stimulus: reset, start_stream pulse, monitor outputs
  // ---------------------------------------------------------
  initial begin
    // Reset
    rst_n = 0;
    start_stream = 0;
    #20;
    rst_n = 1;
    #10;

  	// preload DUT memory
    $readmemh("conv1_weight.mem", dut.weight_mem);
    #10;
    // Pulse start_stream
    @(posedge clk);
    start_stream = 1;

    @(posedge clk);
    start_stream = 0;

    // Collect outputs for MEM_DEPTH+2 cycles
    repeat (MEM_DEPTH + 2) begin
      @(posedge clk);
      if (weight_valid) begin
        $display("%0t: weight_valid=1, data=%0d", $time, weight_data);
      end
    end

    $finish;
  end
endmodule
