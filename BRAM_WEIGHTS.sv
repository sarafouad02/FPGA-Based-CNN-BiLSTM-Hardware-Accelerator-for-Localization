// BRAM for CNN weights with readable signal names
module bram_weights #(
  parameter integer DATA_WIDTH      = 16,
  parameter integer IN_CHANNELS     = 4,
  parameter integer OUT_CHANNELS    = 4,
  parameter integer KERNEL_SIZE     = 3,
  parameter PE_NUM                  =1 
  // number of values per kernel
  
)(
  input  logic                   clk,
  input  logic                   rst_n,       // active-low reset
  input  logic                   start_stream, // pulse to start streaming weights
  input  logic                   fifo_full,
  output logic                   weight_valid, // high while weight_data is valid
  output logic signed [DATA_WIDTH-1:0] weight_data
);

  localparam integer KERNEL_ELEM_NUM = KERNEL_SIZE * KERNEL_SIZE;
  // total number of weight entries
  localparam integer MEM_DEPTH       = OUT_CHANNELS * IN_CHANNELS * KERNEL_ELEM_NUM;
  // address width to index entire memory
  localparam integer ADDR_WIDTH      = $clog2(MEM_DEPTH);
  // internal BRAM storage
 (* rom_style = "block" *) reg signed [DATA_WIDTH-1:0] weight_mem [0:MEM_DEPTH-1];

  // streaming state
  logic                         stream_active;
  logic [ADDR_WIDTH-1:0]       bram_address;

  // indices to generate address
  logic [$clog2(OUT_CHANNELS)-1:0] out_channel_index;
  logic [$clog2(IN_CHANNELS )-1:0] in_channel_index;
  logic [$clog2(KERNEL_ELEM_NUM)-1:0] kernel_flat_index;

  // calculate BRAM address from indices
  wire [ADDR_WIDTH-1:0] calculated_address =
       out_channel_index * (IN_CHANNELS * KERNEL_ELEM_NUM)+ in_channel_index  *  KERNEL_ELEM_NUM + kernel_flat_index;

  // read data (registered for one-cycle output)
  logic signed [DATA_WIDTH-1:0] data_out_reg;
  always_ff @(posedge clk) begin
    data_out_reg <= weight_mem[bram_address];
  end
  
  assign weight_data  = data_out_reg;
  assign weight_valid = stream_active;

  // FSM: iterate out_channel -> kernel_elem -> in_channel
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      stream_active      <= 1'b0;
      out_channel_index  <= '0;
      kernel_flat_index  <= '0;
      in_channel_index   <= '0;
     // bram_address       <= '0;
    end else begin
      if (start_stream && !stream_active) begin
        // begin streaming
        stream_active     <= 1'b1;
        out_channel_index <= 0;
        kernel_flat_index <= 0;
        in_channel_index  <= 0;
       // bram_address      <= 0;
      end else if (stream_active && !fifo_full) begin
        // advance input-channel index
        if (in_channel_index < IN_CHANNELS-1) begin
          in_channel_index <= in_channel_index + 1;
        end else begin
          in_channel_index <= 0;
          // advance kernel element index
          if (kernel_flat_index < KERNEL_ELEM_NUM-1) begin
            kernel_flat_index <= kernel_flat_index + 1;
          end else begin
            kernel_flat_index <= 0;
            // advance output-channel index
            if (out_channel_index < OUT_CHANNELS-1) begin
              out_channel_index <= out_channel_index + 1;
            end else begin
              // finished all weights
              stream_active <= 1'b0;
              
            end
          end
        end
       // bram_address <= calculated_address;
      end
    end
  end
  assign bram_address = stream_active? calculated_address: 0;
  // Optional: preload weights from file
  // initial $readmemh("weights_init.hex", weight_mem);
  initial begin
     case (PE_NUM)
        1: $readmemh("conv1_weight.mem", weight_mem);
        2: $readmemh("conv2_weight.mem", weight_mem);
        3: $readmemh("conv3_weight.mem", weight_mem);
        4: $readmemh("conv4_weight.mem", weight_mem);
        5: $readmemh("conv5_weight.mem", weight_mem);
        6: $readmemh("conv6_weight.mem", weight_mem);
  endcase

  end

endmodule

