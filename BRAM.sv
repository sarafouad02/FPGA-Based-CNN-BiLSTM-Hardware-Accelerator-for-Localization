//-----------------------------------------------------------------------------
// PingPongBRAM.sv
//  Dual-bank BRAM (Bank 0 / Bank 1) with independent write ports.
//  Reads come from the “active” bank, writes always go to the “inactive”
//
//  Parameters:
//    ADDR_WIDTH, DATA_WIDTH
//  Ports:
//    clk             – system clock
//    rst_n           – active-low reset
//    bank_sel        – 0 → use Bank0 for read, write Bank1; 1 → vice versa
//    we_in           – write-enable for loading host image data
//    addr_in, wdata  – address & data for host writes (4-image block)
//    addr_out        – read address for convolution engine
//    rdata_out       – read data from active bank
module PingPongBRAM #(
  parameter DATA_WIDTH = 16,
  parameter NUM_IMAGES   = 4,
  parameter IMAGE_WIDTH  = 64,
  parameter IMAGE_HEIGHT = 64
) (
  input                          clk,
  input                          bank_sel,
  // Host-side load interface
  input                          write_en,
  input                          read_en,
  input      [$clog2(IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)-1:0]    addr_in_0,
  input      [$clog2(IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)-1:0]    addr_in_1,
  input      [DATA_WIDTH-1:0]    wdata_0,
  input      [DATA_WIDTH-1:0]    wdata_1,
  // Convolution-side read interface
  input      [$clog2(IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)-1:0]    addr_out_0,
  input      [$clog2(IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES)-1:0]    addr_out_1,
  output logic [DATA_WIDTH-1:0]    rdata_out_0,
  output logic [DATA_WIDTH-1:0]    rdata_out_1
  
);

  localparam DEPTH = IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES;

  // Two physical BRAM arrays
  (* ram_style = "block" *) reg [DATA_WIDTH-1:0] bank0_mem [0:DEPTH-1];
  (* ram_style = "block" *) reg [DATA_WIDTH-1:0] bank1_mem [0:DEPTH-1];

  always @(posedge clk) begin
      // Write into the inactive bank
      if (write_en) begin
        if (bank_sel == 1'b0)
          bank1_mem[addr_in_1] <= wdata_0;
        else
          bank0_mem[addr_in_0] <= wdata_1;
      end
  end
  
  always_ff @(posedge clk) begin 
    // Read from the active bank
    if (read_en) begin
        if (bank_sel == 1'b0)
          rdata_out_0 <= bank0_mem[addr_out_0];
        else
          rdata_out_1 <= bank1_mem[addr_out_1];
      end
  end

  // preload memory of bank 0 
  initial begin
    $readmemh("combined_combined_frames_0001_0002.mem", bank0_mem);
  end

 //  // preload memory of bank 1 to avoid optimization
 //  initial begin
 //    $readmemh("combined_combined_frames_0003_0004.mem", bank1_mem);
 // end

endmodule