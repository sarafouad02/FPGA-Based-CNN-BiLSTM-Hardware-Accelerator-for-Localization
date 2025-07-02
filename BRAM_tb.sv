`timescale 1ns/1ps

module tb_bram_images;

  //-------------------------------------------------------------------------
  // Parameters
  //-------------------------------------------------------------------------
  parameter NUM_IMAGES   = 4;
  parameter IMAGE_WIDTH  = 188;
  parameter IMAGE_HEIGHT = 120;
  parameter DATA_WIDTH   = 16;
  localparam IMAGE_SIZE   = IMAGE_WIDTH * IMAGE_HEIGHT;
  localparam MEM_DEPTH    = NUM_IMAGES * IMAGE_SIZE;
  localparam ADDR_WIDTH   = $clog2(IMAGE_SIZE);

  //-------------------------------------------------------------------------
  // Signal Declarations
  //-------------------------------------------------------------------------
  logic clk;
  logic rst;
  logic read_en;
  // img_sel selects one of the 4 images (0 to NUM_IMAGES-1)
  logic [$clog2(NUM_IMAGES)-1:0] img_sel;
  // addr is the relative address within one image (0 to IMAGE_SIZE-1)
  logic [ADDR_WIDTH-1:0] addr;
  logic [DATA_WIDTH-1:0] data_out;

  //-------------------------------------------------------------------------
  // Instantiate the BRAM Module
  //-------------------------------------------------------------------------
  bram_images #(
    .NUM_IMAGES(NUM_IMAGES),
    .IMAGE_WIDTH(IMAGE_WIDTH),
    .IMAGE_HEIGHT(IMAGE_HEIGHT),
    .DATA_WIDTH(DATA_WIDTH)
  ) uut (
    .clk(clk),
    .read_en(read_en),
    .img_sel(img_sel),
    .addr(addr),
    .data_out(data_out)
  );

  //-------------------------------------------------------------------------
  // Clock Generation
  //-------------------------------------------------------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10 ns clock period
  end

  //-------------------------------------------------------------------------
  // Memory Initialization
  //-------------------------------------------------------------------------
  // Load the internal memory of the DUT from a hex file.
  // The file "images.hex" should contain MEM_DEPTH words (one per pixel) in hex format.
  initial begin
    $readmemh("output.hex", uut.mem);
  end

  //-------------------------------------------------------------------------
  // Test Sequence
  //-------------------------------------------------------------------------
  initial begin
    // Initialize signals
    rst      = 1;
    read_en  = 0;
    img_sel  = 0;
    addr     = 0;
    #20;
    rst      = 0;
    #10;

    // Enable BRAM reading
    read_en = 1;

    // Test reading from image 0: read the first 5 addresses.
    img_sel = 0;
    $display("=== Reading first 5 addresses from Image 0 ===");
    repeat (5) begin
      @(posedge clk);
      addr = addr + 1;
      @(posedge clk);  // Wait for synchronous read
      $display("Time %0t: Image %0d, Addr: %0d, Data: %0h", $time, img_sel, addr, data_out);
    end

    // Reset the address counter for next image.
    addr = 0;

    // Test reading from image 1: read the first 5 addresses.
    img_sel = 1;
    $display("=== Reading first 5 addresses from Image 1 ===");
    repeat (5) begin
      @(posedge clk);
      addr = addr + 1;
      @(posedge clk);
      $display("Time %0t: Image %0d, Addr: %0d, Data: %0h", $time, img_sel, addr, data_out);
    end

    // Test a read from a middle address of image 2.
    img_sel = 2;
    addr    = IMAGE_SIZE / 2;
    @(posedge clk);
    @(posedge clk);
    $display("Time %0t: Image %0d, Addr: %0d, Data: %0h", $time, img_sel, addr, data_out);

    // Test a read from the last address of image 3.
    img_sel = 3;
    addr    = IMAGE_SIZE - 1;
    @(posedge clk);
    @(posedge clk);
    $display("Time %0t: Image %0d, Addr: %0d, Data: %0h", $time, img_sel, addr, data_out);

    #50;
    $finish;
  end

endmodule

