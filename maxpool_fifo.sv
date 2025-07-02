module maxpool_buffer #(
    parameter DATA_WIDTH    = 16,
    parameter IMAGE_WIDTH   = 188,   // number of spatial columns
    parameter KERNEL_HEIGHT = 2,     // always 2
    parameter STRIDE        = 2,
    parameter IMAGE_HEIGHT  = 120,
    parameter OUT_CHANNELS  = 16,     // depth
    parameter PE_NUM        =1
)(
    input  logic                    clk,
    input  logic                    rst,           // active‐high reset
    input  logic                    en,            // new‐pixel enable
    input  logic [DATA_WIDTH-1:0]   pixel_in,      // one pixel for one channel at a time
    output logic                    valid_chan,    // goes high once 2×2 window is ready for all channels
    output logic [DATA_WIDTH-1:0]   window [KERNEL_HEIGHT][KERNEL_HEIGHT]
);

  //–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  // 1) internal parameters for pointer widths
  //–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
    // after your existing localparams
  // compute the last read‐pointer value that still yields a full 2×2 window
  localparam integer LAST_READ = 
      (IMAGE_WIDTH % STRIDE == 0) ? IMAGE_WIDTH : IMAGE_WIDTH + (STRIDE - (IMAGE_WIDTH % STRIDE));

  localparam COL_W = $clog2(LAST_READ);       // to index 0..IMAGE_WIDTH-1
  localparam CH_W  = $clog2(OUT_CHANNELS);      // to index 0..OUT_CHANNELS-1
  localparam CNT_W = $clog2(LAST_READ + 1);   // for counting columns

  //–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  // 2) write pointers & flags
  //–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  logic [COL_W-1:0] write_col_ptr;  // 0..IMAGE_WIDTH-1
  logic [CH_W -1:0] write_ch;       // 0..OUT_CHANNELS-1
  logic [CH_W -1:0] write_ch_reg;     
  logic             row0_done, row1_done;      // went high once row0 fully written
  logic [CNT_W-1:0] row1_col_wr;    // how many columns of row1 have been completely written
  logic [COL_W-1:0]       read_col_ptr;
  logic [CH_W -1:0]       chan_idx;
  logic [$clog2(IMAGE_HEIGHT)-1:0]  num_update_counter, num_rows_counter;
  logic                             num_update_flag, num_rows_flag;

  // two line-buffers: row0_mem and row1_mem, each [column][channel]
  logic [DATA_WIDTH-1:0] row0_mem [0:IMAGE_WIDTH-1][0:OUT_CHANNELS-1];
  logic [DATA_WIDTH-1:0] row1_mem [0:IMAGE_WIDTH-1][0:OUT_CHANNELS-1];




  //–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  // 3) filling logic: write into row0 first, then row1
  //–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  always_ff @(posedge clk) begin
    if (rst ) begin
      write_col_ptr <= '0;
      write_ch      <= '0;
      row0_done     <=  1'b0;
      row1_col_wr   <= '0;
      row1_done     <= '1;
      write_ch_reg  <= '0;
      //row0_mem initialize by 0
      //row1_mem
      for (int i = 0; i < IMAGE_WIDTH; i = i + 1) begin
        for (int j = 0; j < OUT_CHANNELS; j = j + 1) begin
          row0_mem[i][j] <= '0;
          row1_mem[i][j] <= '0;
        end
      end
    end
    else if (num_update_flag || num_rows_flag) begin
      write_col_ptr <= '0;
      write_ch      <= '0;
      row0_done     <=  1'b0;
      row1_col_wr   <= '0;
      row1_done     <= '1;
      write_ch_reg  <= '0;
      //row0_mem initialize by 0
      //row1_mem
      for (int i = 0; i < IMAGE_WIDTH; i = i + 1) begin
        for (int j = 0; j < OUT_CHANNELS; j = j + 1) begin
          row0_mem[i][j] <= '0;
          row1_mem[i][j] <= '0;
        end
      end
    end else if (en ) begin
      write_ch_reg <= write_ch;
      if (!row0_done ) begin
        // ─── writing into row0_mem ───
        if (num_rows_counter == IMAGE_HEIGHT -2 && IMAGE_HEIGHT[0] == 1) begin //only in case  of odd height
          row0_mem[write_col_ptr][write_ch] <= 0;
        end else begin
          row0_mem[write_col_ptr][write_ch] <= pixel_in;
        end
       

        // once we finish all OUT_CHANNELS in column write_col_ptr:
        if (write_ch == OUT_CHANNELS-1) begin
          write_ch <= '0;

          if (IMAGE_WIDTH[0] == 0) begin //even
            if (write_col_ptr == LAST_READ-1) begin
              // finished entire row0
              row0_done     <= 1'b1;
              write_col_ptr <= '0;
              row1_done <=0;
            end else begin
              write_col_ptr <= write_col_ptr + 1; 
            end
          end else begin //odd
            if (write_col_ptr == LAST_READ-2) begin
              // finished entire row0
              row0_done     <= 1'b1;
              write_col_ptr <= '0;
              row1_done <=0;
            end else begin
              write_col_ptr <= write_col_ptr + 1; 
            end
          end
            
          
        end else begin
          write_ch <= write_ch + 1;
        end

      end else begin

        // ─── writing into row1_mem ───
        row1_mem[write_col_ptr][write_ch] <= pixel_in;
         
        if (write_ch == OUT_CHANNELS-1) begin
          write_ch <= '0;
          // completed column "write_col_ptr" for row1:
          if (row1_col_wr < LAST_READ)
            row1_col_wr <= row1_col_wr + 1;


          if (IMAGE_WIDTH[0] == 0) begin //even
              // advance column pointer (wrap around)
            if (write_col_ptr == LAST_READ-1) begin
              write_col_ptr <= '0;
              row1_done     <= 1;
             
            end
            else
              write_col_ptr <= write_col_ptr + 1;
          end else begin // odd
            if (write_col_ptr == LAST_READ-2) begin
              write_col_ptr <= '0;
              row1_done     <= 1;
             
            end
            else
              write_col_ptr <= write_col_ptr + 1;
          end
        
          
        end else begin
          write_ch <= write_ch + 1;
        end
      end
    end

     else begin
       if(read_col_ptr + STRIDE == LAST_READ && chan_idx == OUT_CHANNELS-1) begin
        row0_done     <= 1'b0;
        // write_col_ptr <= 0;
      end
     end 
    
    
  end

  //This section is responsible for reseting the fifo when reaching the last row of the image
    //------------------------------------------------------------------------------
  // 1) Compute HALF_HEIGHT at elaboration time
  //------------------------------------------------------------------------------
  localparam integer HALF_HEIGHT = (IMAGE_HEIGHT) / 2;

  //------------------------------------------------------------------------------
  // 2) Delay register for row1_done
  //------------------------------------------------------------------------------
  logic row0_done_d, row1_done_d;

  always_ff @(posedge clk ) begin
    if (rst) begin
      row1_done_d <= 1'b0;
      row0_done_d <=0;
    end else if ( num_update_flag || num_rows_flag) begin
      row1_done_d <= 1'b0;
      row0_done_d <=0;
    end else begin
      row1_done_d <= row1_done;
      row0_done_d <= row0_done;
    end
  end

  //------------------------------------------------------------------------------
  // 3) Counter that increments only on the rising edge of row1_done
  //------------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      num_update_counter <= '0;
      num_rows_counter <= '0;
      num_update_flag <= 0;
      num_rows_flag <= 0;
    end else begin
        if (num_update_counter == HALF_HEIGHT + 1 && chan_idx == OUT_CHANNELS-1) begin
          if(IMAGE_HEIGHT[0] == 1) begin
            num_update_counter <= 0;
          end else begin
            num_update_counter <= 1;
          end
          
          num_update_flag <= 1;
        end else if (row1_done && !row1_done_d) begin
          num_update_counter <= num_update_counter + 1;
          num_update_flag <= 0;
        end else begin
        // otherwise hold its value
        num_update_counter <= num_update_counter;
        num_update_flag <= 0;
      end

      // for rows counter
      if (num_rows_counter == IMAGE_HEIGHT + 1) begin
        if(IMAGE_HEIGHT[0] == 1) begin
            num_rows_counter <= 0;
          end else begin
            num_rows_counter <= 1;
          end
        num_rows_flag <= 1;
      end else if (row0_done && !row0_done_d || row1_done && !row1_done_d) begin
        num_rows_counter <= num_rows_counter + 1;
        num_rows_flag <= 0;
      end else begin
        num_rows_counter <= num_rows_counter;
        num_rows_flag <= 0;
      end
    end
  end


  //–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  // 4) read pointers: chan_idx (0..OUT_CHANNELS-1) and read_col_ptr (0..IMAGE_WIDTH-1)
  //–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  

  // Compute “we definitely have two full rows up to read_col_ptr+STRIDE-1”
  wire have_two_rows, odd_valid_chan;
  assign have_two_rows =
       row0_done
    && ((write_col_ptr >= (read_col_ptr + STRIDE)) 
    ||( read_col_ptr + STRIDE == LAST_READ && row1_done) )   // ensure row1's columns [read_col_ptr .. read_col_ptr+1] are done
    && (read_col_ptr + STRIDE - 1 < LAST_READ) ; // in bounds
//||( read_col_ptr + STRIDE == IMAGE_WIDTH && (write_col_ptr >= (read_col_ptr + STRIDE-1)) && write_ch == OUT_CHANNELS-1)) 

// assign update_have_two_rows = (row1_col_wr == IMAGE_WIDTH-1) && (write_col_ptr > STRIDE-1) 
//     && (write_ch  == OUT_CHANNELS-1) && !(chan_idx == OUT_CHANNELS-1) ;

  always_ff @(posedge clk) begin
    if (rst) begin
      read_col_ptr <= '0;
      chan_idx     <= '0;
    end else if (num_update_flag || num_rows_flag) begin
      read_col_ptr <= '0;
      chan_idx     <= '0;
    end
    //
    else if (valid_chan ) begin
      if (chan_idx == OUT_CHANNELS-1) begin
        // we just finished outputting channel (OUT_CHANNELS-1) for this 2×2 window:
        chan_idx <= '0;

        // now slide the spatial window by STRIDE to the next 2 columns:
         if (read_col_ptr + STRIDE < LAST_READ)
          read_col_ptr <= read_col_ptr + STRIDE;
        else
          read_col_ptr <= '0;  // wrap around if you want continuous tiling 
        
        
      end else begin
        // still outputting channels 0..OUT_CHANNELS-1 for the same 2×2 window:
        chan_idx <= chan_idx + 1;
      end
    end 
    else begin
      // not ready yet → hold pointers at zero:
      chan_idx     <= '0;
      read_col_ptr <= read_col_ptr;
      // if(read_col_ptr + STRIDE == IMAGE_WIDTH && chan_idx == OUT_CHANNELS-1) begin
      //   read_col_ptr <=0;
      // end
      end
  end

  //In case the image width is odd, so that the last index is not valid for a 2x2 output 
  assign odd_valid_chan = (IMAGE_WIDTH[0] == 1) && (read_col_ptr == IMAGE_WIDTH -1);

  // “valid_chan” simply reflects whether 2×2 is ready for all channels:
  assign valid_chan = have_two_rows;// || PE_NUM ==6 && row0_done

  //–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  // 5) deliver the 2×2 mini-window (row0,row1) for the current channel
  //–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  // We guard with valid_chan so that until both rows exist, window[*] = 0
  assign window[0][0] = (valid_chan && !odd_valid_chan) ? row0_mem[read_col_ptr    ][chan_idx] : '0;
  assign window[0][1] = (valid_chan && !odd_valid_chan) ? row0_mem[read_col_ptr + 1][chan_idx] : '0;
  assign window[1][0] = (valid_chan && !odd_valid_chan) ? row1_mem[read_col_ptr    ][chan_idx] : '0;
  assign window[1][1] = (valid_chan && !odd_valid_chan) ? row1_mem[read_col_ptr + 1][chan_idx] : '0;

endmodule




// module maxpool_buffer #(
//     parameter DATA_WIDTH   = 16,
//     parameter IMAGE_WIDTH  = 128,  // adjust as needed
//     parameter KERNEL_SIZE  = 3,
//     parameter STRIDE       = 2 
// )(
//     input  logic                      clk,
//     input  logic                      rst,
//     input  logic                      en,         // enable for incoming pixel (from MAC)
//     // input  logic                      win_update, // update window pointer (stride control)
//     input  logic [DATA_WIDTH-1:0]     pixel_in,
//     output logic                      valid_window, 
//     // 2x2 window output: first index = row (0 or 1), second index = column (0 or 1)
//     output logic [DATA_WIDTH-1:0]     window [KERNEL_SIZE][KERNEL_SIZE]
// );

//   // Internal memories for the two rows.
//   // row0 is written first; once full, row1 begins.
//   logic [$clog2(IMAGE_WIDTH):0] row0_wr_ptr, row1_wr_ptr;
//   logic                         row0_done;

//   // Declare two memory arrays for the two rows.
//   logic [DATA_WIDTH-1:0] row0 [0:IMAGE_WIDTH-1];
//   logic [DATA_WIDTH-1:0] row1 [0:IMAGE_WIDTH-1];

//   // Write logic:
//   // - While row0 is not done, fill row0.
//   // - After row0 is full, fill row1.
//   always_ff @(posedge clk or posedge rst) begin
//     if(rst) begin
//       row0_wr_ptr <= 0;
//       row1_wr_ptr <= 0;
//       row0_done   <= 1'b0;
//     end else if(en) begin
//       if(!row0_done) begin
//         row0[row0_wr_ptr] <= pixel_in;
//         if(row0_wr_ptr == IMAGE_WIDTH-1) begin
//           row0_done   <= 1'b1;
//           row0_wr_ptr <= 0; // optional: you can hold or reset pointer if needed
//         end else begin
//           row0_wr_ptr <= row0_wr_ptr + 1;
//         end
//       end else begin
//         row1[row1_wr_ptr] <= pixel_in;
//         // When row1 is being filled, you can use row1_wr_ptr as the number of valid pixels
//         if(row1_wr_ptr < IMAGE_WIDTH-1)
//           row1_wr_ptr <= row1_wr_ptr + 1;
//       end
//     end
//   end

//   // Window extraction:
//   // A 2x2 window is read starting at column index win_ptr.
//   // Valid window only if:
//   //   - row0 is complete (i.e. row0_done==1)
//   //   - there are at least two pixels in row1 (i.e. row1_wr_ptr > win_ptr+1)
//   //   - and we do not exceed IMAGE_WIDTH (assumed even)
//   logic [$clog2(IMAGE_WIDTH):0] win_ptr;

//   always_ff @(posedge clk or posedge rst) begin
//     if(rst) begin
//       win_ptr <= 0;
//     end else if(valid_window) begin
//       if(win_ptr + STRIDE < IMAGE_WIDTH)
//         win_ptr <= win_ptr + STRIDE;  // shift window by stride=2
//       else
//         win_ptr <= 0; // wrap-around or hold (depending on your application)
//     end
//   end

//   // Generate window outputs (combinational read)
//   // We assume that row0 is completely valid once row0_done is high.
//   assign window[0][0] = valid_window? row0[win_ptr] : 0;
//   assign window[0][1] = valid_window? row0[win_ptr+1] : 0;
//   assign window[1][0] = valid_window? row1[win_ptr] : 0;
//   assign window[1][1] = valid_window? row1[win_ptr+1] : 0;

//   // Valid window flag: true if row0 is done and row1 has at least win_ptr+2 pixels.
//   assign valid_window = row0_done && ((win_ptr + STRIDE -1) < row1_wr_ptr) && ((win_ptr + STRIDE -1) < IMAGE_WIDTH);

// endmodule