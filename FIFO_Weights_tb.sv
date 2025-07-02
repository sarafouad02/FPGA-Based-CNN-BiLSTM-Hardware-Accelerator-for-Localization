`timescale 1ns/1ps

module weights_fifo_tb;
  // ------------------------------------------------------------------------
  // Testbench parameters (small for clarity)
  // ------------------------------------------------------------------------
  localparam DATA_WIDTH        = 16;
  localparam IN_CHANNELS       = 4;
  localparam KERNEL_SIZE       = 3;
  localparam FILTER_BUFFER_CNT = 6;
  localparam WEIGHTS_PER_FILTER = IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;

  // ------------------------------------------------------------------------
  // Clock & Reset
  // ------------------------------------------------------------------------
  logic clk, rst_n;
  initial clk = 0;
  always #5 clk = ~clk;  // 10ns period

  // ------------------------------------------------------------------------
  // DUT interfaces
  // ------------------------------------------------------------------------
  logic                         wr_valid, wr_ready;
  logic signed [DATA_WIDTH-1:0] wr_data;
  logic                         rd_valid, rd_ready;
  logic signed [DATA_WIDTH-1:0] window_out [KERNEL_SIZE][KERNEL_SIZE];

  // ------------------------------------------------------------------------
  // Instantiate the FIFO
  // ------------------------------------------------------------------------
  weights_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .IN_CHANNELS(IN_CHANNELS),
    .KERNEL_SIZE(KERNEL_SIZE),
    .FILTER_BUFFER_CNT(FILTER_BUFFER_CNT)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_data(wr_data),
    .rd_valid(rd_valid), .rd_ready(rd_ready),
    .window_out(window_out)
  );
 integer  f, c, e;
  // ------------------------------------------------------------------------
  // Stimulus: write then read
  // ------------------------------------------------------------------------
  initial begin
    // Reset
    rst_n     = 0;
    wr_valid  = 0;
    rd_ready  = 0;
    wr_data   = '0;
    #20 rst_n = 1;

    // Write pattern: for filter f, channel c, element e
    // data = f*100 + c*10 + e
   rd_ready = 1;
    for (f = 0; f < 2*FILTER_BUFFER_CNT; f++) begin
      for (c = 0; c < IN_CHANNELS; c++) begin
        for (e = 0; e < KERNEL_SIZE*KERNEL_SIZE; e++) begin
          @(posedge clk);
          if (!wr_ready) $error("Expected wr_ready=1 at f=%0d c=%0d e=%0d", f,c,e);
          wr_valid <= 1;
          wr_data  <= e;
        end
      end
    end
    // finish writes
    @(posedge clk) wr_valid <= 0;

    // give it a few cycles
    repeat (8) @(posedge clk);

    // Start reading all windows
    
    // total windows = FILTER_BUFFER_CNT * IN_CHANNELS * KERNEL_SIZE*KERNEL_SIZE
    repeat (FILTER_BUFFER_CNT*IN_CHANNELS*KERNEL_SIZE*KERNEL_SIZE + 2) @(posedge clk);
    rd_ready = 0;

    #20 $stop;
  end

  // ------------------------------------------------------------------------
  // Monitor: print each 2×2 window when valid
  // ------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rd_valid && rd_ready) begin
      $display("--- Window (filter/channel implicitly in data) at time %0t ---", $time);
      for (int r = 0; r < KERNEL_SIZE; r++) begin
        for (int k = 0; k < KERNEL_SIZE; k++) begin
          $write("%3d ", window_out[r][k]);
        end
        $write("\n");
      end
      $write("\n");
    end
  end

endmodule
