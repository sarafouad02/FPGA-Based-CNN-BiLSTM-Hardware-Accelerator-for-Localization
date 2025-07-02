module weights_fifo #(
  // Width of each weight word
  parameter  DATA_WIDTH        = 16,
  // Number of input channels per filter
  parameter  IN_CHANNELS       = 4,
  parameter  OUT_CHANNELS       =4,
  // Spatial dimension of each filter kernel (assumed square)
  parameter  KERNEL_SIZE       = 3,
  // Number of filters to buffer in the FIFO
  parameter  FILTER_BUFFER_CNT = 2
)(
  input  logic                         clk,        // Main clock
  input  logic                         rst_n,      // Active-low reset
  // Write interface (from BRAM)
  input  logic                         wr_valid,   // New weight available
  input  logic signed [DATA_WIDTH-1:0] wr_data,    // Weight word
  input  logic                         rd_ready,   // Consumer can accept read
  input  logic                         bnfifo_full ,
  // Read interface (to consumer)
  output logic                         rd_valid,   // window_out is valid
  output logic                         wr_ready,   // FIFO can accept write
  output logic signed [DATA_WIDTH-1:0] window_out[KERNEL_SIZE][KERNEL_SIZE],
  output logic [$clog2(IN_CHANNELS)-1:0]      read_channel_idx,
  output logic                         fifo_full  // FIFO buffer full

 
);
  // Derived constant: number of weights per filter
  localparam int WEIGHTS_PER_FILTER = IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;

  // Internal storage array
  logic signed [DATA_WIDTH-1:0]
    line_buffer [0:IN_CHANNELS-1]
                [0:KERNEL_SIZE-1]
                [0:KERNEL_SIZE*FILTER_BUFFER_CNT-1];
   // FIFO status flags
 
  logic                         fifo_empty; // FIFO buffer empty
  logic last_filter_flag;
  // FIFO status counter: number of complete filters stored
  logic [$clog2(FILTER_BUFFER_CNT+1)-1:0] filter_count;


  // Write-side pointers
  logic [$clog2(FILTER_BUFFER_CNT)-1:0] write_filter_idx;
  logic [$clog2(IN_CHANNELS)-1:0]      write_channel_idx;
  logic [$clog2(KERNEL_SIZE*KERNEL_SIZE)-1:0] write_flat_idx;

  wire [$clog2(KERNEL_SIZE)-1:0] write_row = write_flat_idx / KERNEL_SIZE;
  wire [$clog2(KERNEL_SIZE)-1:0] write_col = write_flat_idx % KERNEL_SIZE;
  wire [$clog2(KERNEL_SIZE*FILTER_BUFFER_CNT)-1:0] write_col_offset = write_filter_idx * KERNEL_SIZE;



  

  // Read-side pointers
  logic [$clog2(FILTER_BUFFER_CNT)-1:0] read_filter_idx;
  


  // Read valid when at least one filter present
  assign rd_valid = (filter_count > 0) &&!fifo_empty;

  // Update filter_count on filter-completion events
  logic write_filter_done, read_filter_done;

  assign write_filter_done = wr_valid && wr_ready &&
                             (write_channel_idx == IN_CHANNELS-1) &&
                             (write_flat_idx == (WEIGHTS_PER_FILTER/IN_CHANNELS -1));
  assign read_filter_done  = rd_valid && rd_ready &&
                             (read_channel_idx == IN_CHANNELS-1);

  // fifo_full / fifo_empty flags
  assign fifo_full  =( (filter_count == FILTER_BUFFER_CNT) 
  || (write_channel_idx == IN_CHANNELS -1 && write_flat_idx == WEIGHTS_PER_FILTER/IN_CHANNELS -1 
    && filter_count == FILTER_BUFFER_CNT-1) )&& !(read_channel_idx == IN_CHANNELS -1 && read_filter_idx >= FILTER_BUFFER_CNT -2) ;

  assign fifo_empty = (filter_count == 0);

  //============================================================================
  // 1) filter_count logic
  //============================================================================
  always_ff @(posedge clk ) begin
    if (!rst_n) begin
      filter_count <= 0;
    end else begin
      case ({write_filter_done, read_filter_done})
        2'b10: filter_count <= filter_count + 1; // write done
        2'b01: 
        begin
          if(FILTER_BUFFER_CNT == OUT_CHANNELS)
            filter_count <= filter_count;
          else
            filter_count <= filter_count - 1; // read done
        end

        default: filter_count <= filter_count;    // no change or both
      endcase
    end
  end

  //============================================================================
  // 2) Write logic
  //============================================================================
  always_ff @(posedge clk ) begin
    if (!rst_n) begin
      write_filter_idx  <= 0;
      write_channel_idx <= 0;
      write_flat_idx    <= 0;
    end else if (wr_valid && wr_ready) begin
      // Store incoming weight
      line_buffer[write_channel_idx][write_row]
                  [write_col_offset + write_col] <= wr_data;
      // Advance pointers
      if (write_channel_idx == IN_CHANNELS-1) begin
        write_channel_idx <= 0;
        if (write_flat_idx == (WEIGHTS_PER_FILTER/IN_CHANNELS -1)) begin
          write_flat_idx   <= 0;
          if (write_filter_idx == FILTER_BUFFER_CNT-1)
            write_filter_idx <= 0;
          else
            write_filter_idx <= write_filter_idx + 1;
        end else begin
          write_flat_idx <= write_flat_idx + 1;
        end
      end else begin
        write_channel_idx <= write_channel_idx + 1;
      end
    end
  end

  //============================================================================
  // 3) Read logic
  //============================================================================
  always_ff @(posedge clk ) begin
    if (!rst_n) begin
      read_filter_idx  <= 0;
      read_channel_idx <= 0;
    end else if (rd_valid && rd_ready ) begin
      if (read_channel_idx == IN_CHANNELS-1) begin
        read_channel_idx <= 0;
        if (read_filter_idx == FILTER_BUFFER_CNT-1)
          read_filter_idx <= 0;
        else
          read_filter_idx <= read_filter_idx + 1;
      end else begin
        if(!bnfifo_full)
        read_channel_idx <= read_channel_idx + 1;
      end
    end
  end

  //============================================================================
  // 4) Output the KxK window for current channel/filter (simplified)
  //============================================================================
  always_comb begin
    for (int r = 0; r < KERNEL_SIZE; r++) begin
      for (int c = 0; c < KERNEL_SIZE; c++) begin
        window_out[r][c] = rd_valid && rd_ready?
          line_buffer[read_channel_idx][r][read_filter_idx*KERNEL_SIZE + c] :
          '0;
      end
    end
end


always_ff @(posedge clk ) begin // this tells us that the weights of the last filter are written
  if(!rst_n) begin
     last_filter_flag<= 0;
  end else begin
    if(filter_count == FILTER_BUFFER_CNT)
   last_filter_flag  <=1 ;
  end
end

  // FIFO can accept writes until filter_count==max
 assign wr_ready =
  (filter_count < FILTER_BUFFER_CNT) &&
  !(FILTER_BUFFER_CNT == OUT_CHANNELS && last_filter_flag);  // and here we use last_filter_flag to disable writing in the fifo again if it already took all weights from the bram
endmodule









// module weights_fifo #(
//   // Width of each weight word
//   parameter int DATA_WIDTH        = 16,
//   // Number of input channels per filter
//   parameter int IN_CHANNELS       = 4,
//   // Spatial dimension of each filter kernel (assumed square)
//   parameter int KERNEL_SIZE       = 3,
//   // Number of filters to buffer in the FIFO
//   parameter int FILTER_BUFFER_CNT = 2
  
// )(
//   input  logic                         clk,        // Main clock
//   input  logic                         rst_n,      // Active-low reset

//   // Write interface (from BRAM)
//   input  logic                         wr_valid,   // New weight available
//   output logic                         wr_ready,   // FIFO can accept write
//   input  logic signed [DATA_WIDTH-1:0] wr_data,    // Weight word

//   // Read interface (to consumer)
//   output logic                         rd_valid,   // window_out is valid
//   input  logic                         rd_ready,   // Consumer can accept read
//   output logic signed [DATA_WIDTH-1:0] window_out[KERNEL_SIZE][KERNEL_SIZE]
// );
  
//   // Derived constant: number of weights per filter
//   localparam int WEIGHTS_PER_FILTER = IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;
//   //==============================================================================
//   // 1) Internal storage array:
//   //    line_buffer[input_channel][row][filter_offset + column]
//   //==============================================================================
//   logic signed [DATA_WIDTH-1:0]
//     line_buffer [0: IN_CHANNELS-1]
//                 [0: KERNEL_SIZE-1]
//                 [0: KERNEL_SIZE*FILTER_BUFFER_CNT-1];

//   //==============================================================================
//   // 2) Write-side pointers
//   //    Writing order: filter -> channel -> (row, col flattened)
//   //==============================================================================
//   logic [$clog2(FILTER_BUFFER_CNT)-1:0] write_filter_idx;
//   logic [$clog2(IN_CHANNELS)     -1:0] write_channel_idx;
//   logic [$clog2(KERNEL_SIZE*KERNEL_SIZE)-1:0] write_flat_idx;

//   // Calculate row, col, and buffer offset from flat index
//  // calculate decoded positions for row, col and filter offset
//   wire [$clog2(KERNEL_SIZE)-1:0] write_row        = write_flat_idx / KERNEL_SIZE;
//   wire [$clog2(KERNEL_SIZE)-1:0] write_col        = write_flat_idx % KERNEL_SIZE;
//   wire [$clog2(KERNEL_SIZE*FILTER_BUFFER_CNT)-1:0] write_col_offset = write_filter_idx * KERNEL_SIZE;


//   // FIFO can accept writes until all filters are filled
//   assign wr_ready = (write_filter_idx < FILTER_BUFFER_CNT);

//   always_ff @(posedge clk or negedge rst_n) begin
//     if (!rst_n) begin
//       write_filter_idx  <= 0;
//       write_channel_idx <= 0;
//       write_flat_idx    <= 0;
//     end else if (wr_valid && wr_ready) begin
//       // Store the incoming weight
//       line_buffer[write_channel_idx][write_row]
//                   [write_col_offset + write_col] <= wr_data;


// 	// Advance channel -> flat index -> filter
// 	if (write_channel_idx == IN_CHANNELS-1) begin
//           write_channel_idx <= 0;
//       if (write_flat_idx == WEIGHTS_PER_FILTER/IN_CHANNELS - 1 && write_filter_idx < FILTER_BUFFER_CNT-1) begin
//         write_flat_idx <= 0;
//         write_filter_idx <= write_filter_idx + 1;    
//       end else begin
//         write_flat_idx <= write_flat_idx + 1;
//       end

//       if(write_filter_idx == FILTER_BUFFER_CNT-1 && write_flat_idx == WEIGHTS_PER_FILTER/IN_CHANNELS - 1) begin
//       	write_filter_idx <=0;
//       	write_flat_idx   <=0;
// 		end
//         end else
//           write_channel_idx <= write_channel_idx + 1;
//       end 
//   end

//   //==============================================================================
//   // 3) Read-side pointers
//   //    Reading order: same as write but gated by rd_ready
//   //==============================================================================
//   logic [$clog2(FILTER_BUFFER_CNT)-1:0] read_filter_idx;
//   logic [$clog2(IN_CHANNELS)     -1:0] read_channel_idx;
//   logic [$clog2(KERNEL_SIZE*KERNEL_SIZE)-1:0] read_flat_idx;

//   // rd_valid true after at least one filter is written
//   assign rd_valid = (read_filter_idx < write_filter_idx) ||
//                     (read_filter_idx == write_filter_idx &&
//                      (write_channel_idx  > read_channel_idx + IN_CHANNELS -1)) 
//                     	||(read_filter_idx == FILTER_BUFFER_CNT-1 && write_filter_idx == 0);
//                      	//||
//                       //(write_channel_idx == read_channel_idx && write_flat_idx == 0)));

//   always_ff @(posedge clk or negedge rst_n) begin
//     if (!rst_n) begin
//       read_filter_idx  <= 0;
//       read_channel_idx <= 0;
//       read_flat_idx    <= 0;
//     end else if (rd_valid && rd_ready) begin
//       // Advance flat index -> channel -> filter
//       // if (read_flat_idx == WEIGHTS_PER_FILTER/IN_CHANNELS - 1) begin
//       //   read_flat_idx <= 0;
//         if (read_channel_idx == IN_CHANNELS-1) begin
//           read_channel_idx <= 0;
//           if (read_filter_idx == FILTER_BUFFER_CNT-1)
//             read_filter_idx <= 0;
//           else
//             read_filter_idx <= read_filter_idx + 1;
//         end else
//           read_channel_idx <= read_channel_idx + 1;
//       // end else begin
//       //   read_flat_idx <= read_flat_idx + 1;
//       // end
//     end
//   end


//   //==============================================================================
//   // 4) Build the KxK output window
//   //==============================================================================
//   wire [$clog2(KERNEL_SIZE)-1:0] read_row = read_flat_idx / KERNEL_SIZE;
//   wire [$clog2(KERNEL_SIZE)-1:0] read_col = read_flat_idx % KERNEL_SIZE;

//   // genvar r, c;
//   // generate
//   always_comb begin : proc_
//   	 for (int r = 0; r < KERNEL_SIZE; r++) begin: rows
//       for (int c = 0; c < KERNEL_SIZE; c++) begin: cols
//         // Only output the element matching current read_row/read_col
//         window_out[r][c] = (rd_valid &&rd_ready)
//                                   ? line_buffer[read_channel_idx][r]
//                                                [read_filter_idx*KERNEL_SIZE + c]
//                                   : '0;
//       end
//     end
//   end
   
//   // endgenerate

// endmodule
