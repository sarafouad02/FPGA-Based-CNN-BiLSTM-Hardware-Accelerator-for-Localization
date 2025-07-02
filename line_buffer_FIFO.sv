//output each of the in_channel in a clock cycle
module line_buffer #(
    parameter IN_CHANNELS  = 4,
    parameter IMAGE_WIDTH  = 128,  
    parameter KERNEL_SIZE  = 3,    
    parameter DATA_WIDTH   = 16,
    parameter IMAGE_HEIGHT  = 10,
    parameter PADDING      = 1,
    parameter STRIDE       = 1,
    parameter MAX_POOL     = 0,
    parameter OUT_CHANNELS = 8,
    parameter PE_NUM       =1
)(
    input  logic clk,
    input  logic rst,
    input line_buffer_en, buffer_slide,
    input logic bram_en,
    // Now a single pixel is input per clock (channel-by-channel)
    input  logic signed [DATA_WIDTH-1:0] pixel_in, 
    // Output: one channel window at a time.
    input logic bnfifo_full,
    input logic weights_rd_valid,
    output logic buffer_full, fill_window_ready_to_mac,update_window_ready_to_mac,
    output logic last_row_done, initial_fill_done,
    output logic signed [DATA_WIDTH-1:0] window_out [KERNEL_SIZE][(KERNEL_SIZE)],
    

    output  logic pad_top, // When asserted, force top row to zero
    output  logic pad_bottom, // When asserted, force bottom row to zero
     // Output channel pointer
     output logic shift_flag, num_shifts_flag, out_when_ready_pe_other, out_when_ready_pe6,
    // This counter cycles through channels so that each cycle the window for one channel is output.
    output logic [$clog2(IN_CHANNELS)-1:0] output_channel,
    output logic [KERNEL_SIZE-1:0] row_fill_index_out,
    output logic [$clog2(IMAGE_HEIGHT)-1:0] num_shifts_counter
       
);

    //-------------------------------------------------------------------------
    // Derived parameters and internal memory
    //-------------------------------------------------------------------------
    localparam EFFECTIVE_WIDTH = IMAGE_WIDTH + 2*PADDING;
    localparam WINDOW_WIDTH    = KERNEL_SIZE ;
 
    // line_mem stores KERNEL_SIZE rows and EFFECTIVE_WIDTH columns for each channel.
    logic [DATA_WIDTH-1:0] line_mem [IN_CHANNELS][KERNEL_SIZE][EFFECTIVE_WIDTH];

    // For sliding window extraction over the padded frame.
    logic [DATA_WIDTH-1:0] col_index_window;

    //-------------------------------------------------------------------------
    // Fill pointers and counters
    //-------------------------------------------------------------------------
    // These pointers determine where to write new incoming pixels.
    int col_index      = PADDING;   // current column (in valid region)
    int row_fill_index = 0;         // current row being filled (0 to KERNEL_SIZE-1)
    assign row_fill_index_out = row_fill_index;
    // The fill_channel counter indicates which channel is currently being written.
    logic [$clog2(IN_CHANNELS)-1:0] fill_channel = 0;
    logic [$clog2(OUT_CHANNELS):0] out_feat_map_count =0;

    // A flag to indicate that the buffer is full (i.e. the entire window span for all channels is filled).
    logic update_fill_done, update_out_ready_flag, fill_out_ready_flag,update_phase_flag, last_fill_pixel;

    logic pad_top_reg,   pad_top_reg_reg;
    // logic pad_top_reg_reg, pad_bottom_reg_reg;
    logic shift_flag_reg;

    //-------------------------------------------------------------------------
    // Sliding window pointer (column index into line_mem)
    // This pointer indicates the left‐most column of the current window.
    int col_index_window_reg = 0;

    //-------------------------------------------------------------------------
    // Update phase pointers (for shifting when buffer is full)
    int col_index_update = PADDING; // When shifting, the column to update in the new (bottom) row.
    //int shift_flag       = 0;       // Indicates that we are in the middle of shifting rows.
    // A separate update_channel counter for channel‐by‐channel update of row3.
    logic [$clog2(IN_CHANNELS)-1:0] update_channel = 0;

    //-------------------------------------------------------------------------
   
    // A helper signal: window_ready is high when we have enough valid data in the buffer.
    // (We use row_fill_index and col_index from the fill phase.)
    wire window_ready;
    assign window_ready = ((row_fill_index >= KERNEL_SIZE-1 && col_index > (WINDOW_WIDTH - 1)) || buffer_full);


    assign fill_window_ready_to_mac= (window_ready || fill_out_ready_flag )&& !update_phase_flag;
    assign update_window_ready_to_mac =  (col_index_update > WINDOW_WIDTH - 1 || update_out_ready_flag);
    //-------------------------------------------------------------------------
    // Buffer Full Flag Logic
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            buffer_full <=0 ;
        end else if(num_shifts_flag) begin
            buffer_full <=0 ;
        end else begin
            // For example, we consider the buffer full when we have finished filling at least KERNEL_SIZE rows
            // and the valid region has been completely filled.
            if ((row_fill_index >= KERNEL_SIZE-1) && (col_index == (IMAGE_WIDTH)) && fill_channel == IN_CHANNELS - 1)
                buffer_full <= 1;
        end
    end

    always_comb begin
        if (row_fill_index ==0 && num_shifts_counter == 0) begin
            if(col_index == IMAGE_WIDTH) begin
                if (fill_channel >= IN_CHANNELS -2)
                    pad_top = 0;
                else 
                    pad_top = 1;
            end else begin
                pad_top = 1;
            end
        end else begin
            pad_top = 0;
        end
    end

    assign pad_bottom = PE_NUM!= 6 && (num_shifts_counter == IMAGE_HEIGHT - KERNEL_SIZE + 2*PADDING -1) || PE_NUM==6 && shift_flag==1;

    always_ff @(posedge clk ) begin 
        if(rst) begin
            pad_top_reg <= 0;
            pad_top_reg_reg <=0;
          
        end else begin
            pad_top_reg <= pad_top;
            pad_top_reg_reg <= pad_top_reg;
           
        end
    end

    //-------------------------------------------------------------------------
    // Fill / Update Logic (writes pixels into line_mem channel-by-channel)
    //-------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin //must add top and bottom padding
            // Reset: clear all line memory.
            for (int c = 0; c < IN_CHANNELS; c++) begin
                for (int j = 0; j < KERNEL_SIZE; j++) begin
                    for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
                        line_mem[c][j][k] <= 0;
                    end
                end
            end
            col_index            <= PADDING;
            row_fill_index       <= 0;
            fill_channel         <= 0;
            //col_index_window_reg <= 0;
            col_index_update     <= PADDING;
            shift_flag           <= 0;
            update_channel       <= 0;
            initial_fill_done    <= 0;
            update_phase_flag<=0;
            // update_fill_done     <= 0;
            last_row_done        <= 0;
            update_out_ready_flag <= 0;
            fill_out_ready_flag   <= 0;
            last_fill_pixel  <= 0;
        end else if (num_shifts_flag)begin
            // Reset: clear all line memory.
            for (int c = 0; c < IN_CHANNELS; c++) begin
                for (int j = 0; j < KERNEL_SIZE; j++) begin
                    for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
                        line_mem[c][j][k] <= 0;
                    end
                end
            end
            col_index            <= PADDING;
            row_fill_index       <= 0;
            fill_channel         <= 0;
            //col_index_window_reg <= 0;
            col_index_update     <= PADDING;
            shift_flag           <= 0;
            update_channel       <= 0;
            initial_fill_done    <= 0;
            update_phase_flag<=0;
            // update_fill_done     <= 0;
            last_row_done        <= 0;
            update_out_ready_flag <= 0;
            fill_out_ready_flag   <= 0;
            last_fill_pixel  <= 0;
        end else begin
            if (!buffer_full || MAX_POOL) begin
                // ----- Filling Phase -----
                update_phase_flag<=0;
                // Write the incoming pixel into the line_mem for the current fill_channel.
                if (PADDING && ((row_fill_index == 0 && (PE_NUM!=6&&pad_top_reg_reg || PE_NUM==6&&pad_top_reg) ) ||
                                (row_fill_index == KERNEL_SIZE-1 && pad_bottom)))
                    line_mem[fill_channel][row_fill_index][col_index] <= 0;
                else if (line_buffer_en)
                    line_mem[fill_channel][row_fill_index][col_index] <= pixel_in;

                if (fill_channel > 0 && col_index >= WINDOW_WIDTH - 1 && row_fill_index >= KERNEL_SIZE-1 && !initial_fill_done) begin
                    fill_out_ready_flag <= 1;
                end else begin
                    fill_out_ready_flag <= 0;
                end

                if (col_index == IMAGE_WIDTH && fill_channel == IN_CHANNELS -1 && row_fill_index == KERNEL_SIZE -1 && !initial_fill_done) begin
                    last_fill_pixel <= 1; 
                end else if (initial_fill_done) begin
                    last_fill_pixel <= 0;
                end

                // Advance the fill_channel counter.
                if(line_buffer_en) begin
                if (fill_channel < IN_CHANNELS - 1)
                    fill_channel <= fill_channel + 1;
                else begin
                    fill_channel <= 0;
                    // Once all channels have been written for this pixel position, advance the column pointer.
                    if ( (col_index < (PADDING + IMAGE_WIDTH - 1)))
                        col_index <= col_index + 1;
                    else if (row_fill_index < KERNEL_SIZE - 1) begin
                        col_index <= PADDING;
                        row_fill_index <= row_fill_index + 1;
                    end else begin
                        // If already in the last row, keep row_fill_index (or you can decide to stall further writes)
                        row_fill_index <= row_fill_index; 
                    end
                end
            end

                // (output the initial filling phase first before entering the shift and update phase)
            end else if (buffer_full && col_index_window_reg < IMAGE_WIDTH && !initial_fill_done) begin
                if (col_index_window_reg == IMAGE_WIDTH -1 && output_channel == IN_CHANNELS-2 && out_feat_map_count >= OUT_CHANNELS -1) begin
                    initial_fill_done <= 1;
                    // col_index_window_reg <= 0;
                end
            end else begin 
                if (col_index_window_reg == IMAGE_WIDTH -1 && output_channel == IN_CHANNELS-2 && last_row_done ) begin
                    shift_flag <= 0; // end shift; ready for next update phase
                end
                    
                // ----- Update Phase (Buffer Full) -----
                // In update phase the buffer is full.
                // Do not update col_index_window_reg here (it will be updated in the output phase).
                // Instead, perform the row shift to bring in new pixels.
                if ((!shift_flag && col_index_window_reg == IMAGE_WIDTH -1 && output_channel == IN_CHANNELS-1 || (!shift_flag && update_fill_done)) && out_feat_map_count >= OUT_CHANNELS -1) begin
                    // Shift every channel’s rows upward.
                    update_phase_flag<=1;
                    for (int c = 0; c < IN_CHANNELS; c++) begin
                        // Shift row 1 into row 0.
                        for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
                            if (PADDING && (PE_NUM!=6&&pad_top_reg_reg || PE_NUM==6&&pad_top_reg))
                                line_mem[c][0][k] <= 0;
                            else
                                line_mem[c][0][k] <= line_mem[c][1][k];
                        end
                        // Shift row 2 into row 1.
                        for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
                            line_mem[c][1][k] <= line_mem[c][2][k];
                        end
                    end
                    // Prepare to update row 2 (the new row) channel-by-channel.
                    col_index_update <= PADDING;
                    shift_flag <= 1;
                    update_channel <= 0;
                end

                // Now, update row 2 for the current update_channel.
                if (PADDING && pad_bottom)
                    line_mem[update_channel][2][col_index_update] <= 0;
                else if ((line_buffer_en && ((col_index_update >= PADDING) && (col_index_update < (PADDING + IMAGE_WIDTH)) && !last_row_done)) && shift_flag)
                    line_mem[update_channel][2][col_index_update] <= pixel_in;
                // else
                //     line_mem[update_channel][2][col_index_update] <= 0;

                if (col_index_update == IMAGE_WIDTH && update_channel == IN_CHANNELS -1 && !update_fill_done) begin
                    last_row_done <= 1; 
                    //col_index_update = col_index_update + 1;
                end else if (shift_flag) begin
                    last_row_done <= 0;
                    // Advance update_channel.
                if(line_buffer_en) begin
                    if (update_channel < IN_CHANNELS - 1)
                        update_channel <= update_channel + 1;
                    else begin
                        update_channel <= 0;
                        // Once all channels have been updated for this column, advance col_index_update.
                        if (col_index_update < (PADDING + IMAGE_WIDTH - 1) )
                            col_index_update <= col_index_update + 1;
                        else begin
                            col_index_update <= PADDING;
                        end
                    end 
                end
            end
                   
                if (update_channel > 0 && col_index_update > WINDOW_WIDTH - 1 && !update_fill_done) begin
                    update_out_ready_flag <= 1;
                end else begin
                    update_out_ready_flag <= 0;
                end
                 
                
            end 
        end
    end

    always_ff @(posedge clk) begin : proc_
        if(rst) begin
             shift_flag_reg<= 0;
        end else begin
            shift_flag_reg <= shift_flag;
        end
    end

    always_ff @(posedge clk) begin 
        if(rst) begin
            num_shifts_counter <= 0;
            num_shifts_flag <= 0;
        end else if (update_fill_done == 1) begin
            num_shifts_counter <= num_shifts_counter + 1;
            num_shifts_flag <=0;
        end else if (num_shifts_counter == IMAGE_HEIGHT - KERNEL_SIZE + 2*PADDING) begin
            num_shifts_flag <=1;
            num_shifts_counter <= 0;
        end else begin
            num_shifts_flag <= 0;
        end
    end


    always_comb begin
        if (col_index_window_reg == IMAGE_WIDTH -1 && output_channel == IN_CHANNELS-1 && last_row_done && out_feat_map_count >= OUT_CHANNELS -1) begin
                    update_fill_done = 1;
                end else begin
                    update_fill_done = 0;
                end
                    
    end

    //-------------------------------------------------------------------------
    // Output Window Generation (channel-by-channel)
    //-------------------------------------------------------------------------
    // Instead of outputting all channels at once, we output the window for the channel given by output_channel.
    // logic out_when_ready_pe6;
    assign out_when_ready_pe6 = PE_NUM==6 &&(window_ready || fill_out_ready_flag) &&  (!shift_flag || shift_flag&& col_index_update >= IMAGE_WIDTH&& update_channel>=IN_CHANNELS-1);
    logic out_when_ready_pe1;
    assign out_when_ready_pe1 = (window_ready || fill_out_ready_flag) && ((!update_fill_done && !shift_flag ) || (col_index_update > WINDOW_WIDTH - 1 || update_out_ready_flag));
    assign out_when_ready_pe_other = out_when_ready_pe1 && 
                                        ( (( col_index_window_reg <= col_index - KERNEL_SIZE || last_fill_pixel ) && !update_phase_flag) 
                                            || ( (col_index_window_reg <= col_index_update - KERNEL_SIZE || last_row_done) && update_phase_flag));
    always_comb begin
        if ((PE_NUM == 1 && out_when_ready_pe1 || PE_NUM != 1 && PE_NUM!=6 && out_when_ready_pe_other || out_when_ready_pe6)&& weights_rd_valid ) begin //PE_NUM == 1 && out_when_ready_pe1 || PE_NUM != 1 && out_when_ready_pe_other
            for (int j = 0; j < KERNEL_SIZE; j++) begin
                for (int k = 0; k < WINDOW_WIDTH; k++) begin
                    if(!bnfifo_full )
                    window_out[j][k] = line_mem[output_channel][j][col_index_window_reg + k];
                else
                    window_out[j][k] =0;
                end
            end
        end else begin
            // If not ready, output zeros.
            for (int j = 0; j < KERNEL_SIZE; j++) begin
                for (int k = 0; k < WINDOW_WIDTH; k++) begin
                    window_out[j][k] = 0;
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // Output Channel and Sliding Pointer Update
    //-------------------------------------------------------------------------
    // This block cycles through output channels; when all channels have been output for the current window,
    logic flag_test;
    assign  flag_test = PE_NUM == 1 && out_when_ready_pe1 || PE_NUM != 1 && PE_NUM!=6 && out_when_ready_pe_other || out_when_ready_pe6;
    // it advances the sliding window pointer to the next window.
    always_ff @(posedge clk ) begin
        if (rst) begin
            output_channel <= 0;
            col_index_window_reg <= 0;
        end else if (num_shifts_flag) begin
            output_channel <= 0;
            col_index_window_reg <= 0;
        end else if ((PE_NUM == 1 && out_when_ready_pe1 || PE_NUM != 1 && PE_NUM!=6 && out_when_ready_pe_other || out_when_ready_pe6)&& weights_rd_valid ) begin
            if (output_channel < IN_CHANNELS - 1) begin
                if(!bnfifo_full)
                output_channel <= output_channel + 1;
                else
                    output_channel<= output_channel;
            end else begin//
                // Advance the sliding pointer for the next window.
                if ((col_index_window_reg <= EFFECTIVE_WIDTH - WINDOW_WIDTH) && out_feat_map_count <= OUT_CHANNELS-1 ) begin
                    if (((col_index_window_reg == EFFECTIVE_WIDTH - WINDOW_WIDTH) && out_feat_map_count == OUT_CHANNELS-1 )) begin // we wanted to put col_index_window_reg to 0 at the beginning of the update phase 
                        out_feat_map_count <= 0; 
                        col_index_window_reg <= 0;
                    end
                    if(buffer_slide || PE_NUM==6 && last_row_done&& output_channel >= IN_CHANNELS-1 && buffer_slide ) begin
                        output_channel<=0;
                        out_feat_map_count <= out_feat_map_count + 1;
                        if (out_feat_map_count >= OUT_CHANNELS -1) begin
                            col_index_window_reg <= col_index_window_reg + STRIDE;
                            out_feat_map_count <= 0; 
                        end

                    end
                     
                end else begin
                        col_index_window_reg <= 0; ///////////////////////////////////////////
                end
             
            end//
        end else if(buffer_slide ||(shift_flag && !shift_flag_reg && output_channel == IN_CHANNELS - 1) ) begin
                output_channel<=0;
                // out_feat_map_count <= out_feat_map_count + 1;
            end
    end
    //-------------------------------------------------------------------------
    // Pass the sliding window pointer to the output port.
    // (This pointer indicates the left-most column of the current window.)
    assign col_index_window = col_index_window_reg;

endmodule



// //the module that needs to be genralized for any IMAGE_WIDTH other than 8
// //the module that output 3x3 window_out
// module line_buffer #(
//     parameter IN_CHANNELS  = 4,
//     parameter IMAGE_WIDTH  = 128,  
//     parameter KERNEL_SIZE  = 3,    
//     parameter DATA_WIDTH   = 16,
//     parameter NUM_PIXELS   = 3,
//     parameter PADDING      = 1,
//     parameter STRIDE       = 1,
//     parameter MAX_POOL     = 0
// )(
//     input  logic clk,
//     input  logic rst,
//     input  logic signed [DATA_WIDTH-1:0] pixel_in [IN_CHANNELS], 
//     input  logic pad_top,    // When asserted, force top row to zero
//     input  logic pad_bottom, // When asserted, force bottom row to zero
//     output logic signed [DATA_WIDTH-1:0] window_out [IN_CHANNELS][KERNEL_SIZE][KERNEL_SIZE+NUM_PIXELS-1],
//     //output logic frame_end_flag, // Raised when window reaches end of padded frame
//     // For sliding window extraction over the padded frame.
//     output logic [DATA_WIDTH-1:0] col_index_window       // Pointer into the padded memory for window extraction
// );

//     // Effective width includes left and right padding.
//     localparam EFFECTIVE_WIDTH = IMAGE_WIDTH + 2*PADDING;
//     // Window width (the number of columns needed to form a complete window)
//     localparam WINDOW_WIDTH = KERNEL_SIZE + NUM_PIXELS - 1;

//     // line_mem now stores KERNEL_SIZE rows of EFFECTIVE_WIDTH columns.
//     logic [DATA_WIDTH-1:0] line_mem [IN_CHANNELS][KERNEL_SIZE][EFFECTIVE_WIDTH];

//     // Indices for filling and sliding.
//     // For initial fill we only write into the valid region [PADDING, PADDING+IMAGE_WIDTH-1].
//     int col_index         = PADDING;  
//     int row_fill_index    = 0;         // Which row is being filled (0 to KERNEL_SIZE-1)
//     logic buffer_full     = 0;         // We consider the buffer “ready” once row 2 has at least WINDOW_WIDTH valid pixels

//     // For sliding window extraction.
//     // This pointer is updated (in steps of NUM_PIXELS) as soon as there is enough data.
//     int col_index_window_reg  = 0;

//     // For updating a new row after a frame is processed.
//     int col_index_update  = PADDING;     // Only update valid region columns.
//     int shift_flag        = 0;           // Indicates that we are in the middle of shifting rows

//     // A helper signal that tells us when a complete window is available.
//     // In the initial fill phase, if we are filling the third row (row_fill_index == KERNEL_SIZE-1)
//     // and col_index has advanced far enough, then window_ready is true.
//     // In the update phase, buffer_full is already true.
//     wire window_ready;
//     assign window_ready = ( (row_fill_index >= KERNEL_SIZE-1 && col_index > (WINDOW_WIDTH - 1)) || buffer_full );

//     always_ff @(posedge clk) begin
//         if (rst) begin
//             // Reset: clear all line memory.
//             for (int c = 0; c < IN_CHANNELS; c++) begin
//                 for (int j = 0; j < KERNEL_SIZE; j++) begin
//                     for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
//                         line_mem[c][j][k] <= 0;
//                     end
//                 end
//             end
//             col_index         <= PADDING;
//             row_fill_index    <= 0;
//             // buffer_full       <= 0;
//             col_index_window_reg  <= 0;
//             col_index_update  <= PADDING;
//             shift_flag        <= 0;
//             //frame_end_flag    <= 0;
//         end else begin
//             // ----- Filling Phase Or MAX POOL mode -----
//             if (!buffer_full || (MAX_POOL)) begin
//                 // Write pixel_in into the valid region of the current row.
//                 // For the top row (row 0) and bottom row (row 2), force zeros if pad_top or pad_bottom is high.
//                 for (int c = 0; c < IN_CHANNELS; c++) begin
//                     if (PADDING &&((row_fill_index == 0 && pad_top) ||
//                         (row_fill_index == KERNEL_SIZE-1 && pad_bottom)))
//                         line_mem[c][row_fill_index][col_index] <= 0;
//                     else
//                         line_mem[c][row_fill_index][col_index] <= pixel_in[c];
//                 end

//                 // Advance the fill pointer in the valid region.
//                 if (col_index < (PADDING + IMAGE_WIDTH - 1)) begin
//                     col_index <= col_index + 1;
//                 end else if(row_fill_index < KERNEL_SIZE-1) begin
//                     col_index <= PADDING;
//                     row_fill_index <= row_fill_index + 1;
//                 end else 
//                     row_fill_index <= row_fill_index + 1;

//                 ///////////////////////////////////////////////////////////////////////////////

//                 // // In the initial fill, update the sliding window pointer as new valid pixels become available.
//                 // if ( (MAX_POOL && (row_fill_index > KERNEL_SIZE -1) && col_index_window_reg >= IMAGE_WIDTH - STRIDE +1) || 
//                 //        ( !MAX_POOL && ((row_fill_index >= KERNEL_SIZE -1 && col_index > WINDOW_WIDTH - 1)) ) ) //&&
//                 //     //(col_index_window_reg <= (col_index - WINDOW_WIDTH))) 
//                 //     begin  //this also works col_index_window_reg < (col_index - KERNAL_SIZE)
//                 //     col_index_window_reg <= col_index_window_reg + STRIDE ; 
//                 // end


//                 // In the initial fill, update the sliding window pointer as new valid pixels become available.
//                 if (MAX_POOL && (row_fill_index > KERNEL_SIZE -1) )begin
//                     if (col_index_window_reg < IMAGE_WIDTH - STRIDE ) begin  //this also works col_index_window_reg < (col_index - KERNAL_SIZE)
//                         col_index_window_reg <= col_index_window_reg + STRIDE ; 
//                     end else begin
//                         col_index_window_reg <= 0;
//                     end
//                 end else if ( !MAX_POOL && (row_fill_index >= KERNEL_SIZE -1 && col_index > WINDOW_WIDTH - 1) ) //&&
//                     //(col_index_window_reg <= (col_index - WINDOW_WIDTH))) 
//                     begin  //this also works col_index_window_reg < (col_index - KERNAL_SIZE)
//                     col_index_window_reg <= col_index_window_reg + STRIDE ; 
//                     end

//                 //MAX POOL mode: to update the sliding window pointer
//                 // if (MAX_POOL && col_index_window_reg >= IMAGE_WIDTH - STRIDE +1) begin
//                 //     col_index_window_reg <= 0;
//                 // end

//                 //MAX POOL mode: to overwrite the line_mem
//                 if (MAX_POOL && row_fill_index > KERNEL_SIZE-1 && col_index_window_reg >= IMAGE_WIDTH - STRIDE) begin
//                     row_fill_index <= 0;
//                     col_index <= PADDING;
//                 end


//                 // // Once we are filling the third row and have enough valid pixels, mark the buffer as ready.
//                 // if ((row_fill_index > KERNEL_SIZE -1) && (col_index == (IMAGE_WIDTH)) && 
//                 //     (col_index_window_reg == IMAGE_WIDTH -1)) begin
//                 //     buffer_full <= 1;
//                 // end

//             end else begin
//                 // ----- Update Phase -----
//                 // In update phase, the buffer is full.
//                 // Slide the window over the padded frame with stride = NUM_PIXELS.
//                 // if (col_index_window_reg < EFFECTIVE_WIDTH - WINDOW_WIDTH) begin
//                 //     col_index_window_reg <= col_index_window_reg + NUM_PIXELS;
//                 // end else begin



//                     if (col_index_window_reg < EFFECTIVE_WIDTH - WINDOW_WIDTH) begin
//                        col_index_window_reg <= col_index_window_reg + STRIDE;
//                     end

//                     //frame_end_flag <= 1; // End of padded frame reached

//                     // Shift rows upward.
//                     if (!shift_flag) begin
//                         for (int c = 0; c < IN_CHANNELS; c++) begin
//                             // For the top row: if pad_top is asserted, force zeros; otherwise shift row 1.
//                             for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
//                                 if (PADDING && pad_top)
//                                     line_mem[c][0][k] <= 0;
//                                 else
//                                     line_mem[c][0][k] <= line_mem[c][1][k];
//                             end
//                             // Shift row 2 into row 1.
//                             for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
//                                 line_mem[c][1][k] <= line_mem[c][2][k];
//                             end
//                         end
//                         col_index_update <= PADDING;  // Restart filling of the valid region for new row 3.
//                     end

//                     // Overwrite row 3 with new incoming pixels.
//                     for (int c = 0; c < IN_CHANNELS; c++) begin
//                         if (PADDING && pad_bottom)
//                             line_mem[c][2][col_index_update] <= 0;
//                         else if ((col_index_update >= PADDING) && (col_index_update < (PADDING + IMAGE_WIDTH )))
//                             line_mem[c][2][col_index_update] <= pixel_in[c];
//                         else
//                             line_mem[c][2][col_index_update] <= 0;
//                     end

                    

//                     if (col_index_update == WINDOW_WIDTH - 1)begin
//                         col_index_window_reg <= 0;
//                     end
                    
//                     shift_flag <= 1;

//                     // Advance the update pointer.
//                     if (col_index_update < (PADDING + IMAGE_WIDTH )) begin
//                         col_index_update <= col_index_update + 1;
//                     end else begin
//                         // After the row is updated (even if not fully complete, we have output windows as soon as possible),
//                         // reset pointers and clear the shift flag.
//                         col_index_update <= PADDING;
//                         //col_index_window_reg <= 0;
//                         shift_flag <= 0;
//                     end
//                 //end
//             end
//         end
//     end

//     // Assign the sliding window pointer to the output.
//     assign col_index_window = col_index_window_reg;

//     always_comb begin
//         // Once we are filling the third row and have enough valid pixels, mark the buffer as ready.
//                 if  ( (MAX_POOL && (row_fill_index > KERNEL_SIZE -1)) || ((row_fill_index > KERNEL_SIZE -1) && (col_index == (IMAGE_WIDTH)) && 
//                     (col_index_window_reg == IMAGE_WIDTH -1)) )begin
//                     buffer_full = 1;
//                 end
//     end

//     // ----- Output Window Assignment -----
//     // Extract the window from the padded line memory.
//     // The window size is WINDOW_WIDTH columns and KERNEL_SIZE rows.
    // always_comb begin
    //     if( (!MAX_POOL && (window_ready && (!shift_flag || col_index_update > WINDOW_WIDTH - 1))) || 
    //         (MAX_POOL && row_fill_index > KERNEL_SIZE-1 && col_index >= IMAGE_WIDTH -1) )begin 
    //         for (int c = 0; c < IN_CHANNELS; c++) begin
    //             for (int j = 0; j < KERNEL_SIZE; j++) begin
    //                 for (int k = 0; k < WINDOW_WIDTH; k++) begin
    //                     window_out[c][j][k] = line_mem[c][j][col_index_window_reg + k];
    //                 end
    //             end
    //         end
//         end else begin
//             // Output zeros if the window is not yet ready or during shifting.
//             for (int c = 0; c < IN_CHANNELS; c++) begin
//                 for (int j = 0; j < KERNEL_SIZE; j++) begin
//                     for (int k = 0; k < WINDOW_WIDTH; k++) begin
//                         window_out[c][j][k] = 0;
//                     end
//                 end
//             end
//         end
//     end

// endmodule


// //output each of the in_channel in a clock cycle
// module line_buffer #(
//     parameter IN_CHANNELS  = 4,
//     parameter IMAGE_WIDTH  = 128,  
//     parameter KERNEL_SIZE  = 3,    
//     parameter DATA_WIDTH   = 16,
//     parameter NUM_PIXELS   = 3, // (Used in original window width calc)
//     parameter PADDING      = 1,
//     parameter STRIDE       = 1,
//     parameter MAX_POOL     = 0
// )(
//     input  logic clk,
//     input  logic rst,
//     // Now a single pixel is input per clock (channel-by-channel)
//     input  logic signed [DATA_WIDTH-1:0] pixel_in, 
//     input  logic pad_top,    // When asserted, force top row to zero
//     input  logic pad_bottom, // When asserted, force bottom row to zero
//     // Output: one channel window at a time.
//     output logic signed [DATA_WIDTH-1:0] window_out [KERNEL_SIZE][(KERNEL_SIZE+NUM_PIXELS-1)],
//     // For sliding window extraction over the padded frame.
//     output logic [DATA_WIDTH-1:0] col_index_window       
// );

//     //-------------------------------------------------------------------------
//     // Derived parameters and internal memory
//     //-------------------------------------------------------------------------
//     localparam EFFECTIVE_WIDTH = IMAGE_WIDTH + 2*PADDING;
//     localparam WINDOW_WIDTH    = KERNEL_SIZE + NUM_PIXELS - 1;

//     // line_mem stores KERNEL_SIZE rows and EFFECTIVE_WIDTH columns for each channel.
//     logic [DATA_WIDTH-1:0] line_mem [IN_CHANNELS][KERNEL_SIZE][EFFECTIVE_WIDTH];

//     //-------------------------------------------------------------------------
//     // Fill pointers and counters
//     //-------------------------------------------------------------------------
//     // These pointers determine where to write new incoming pixels.
//     int col_index      = PADDING;   // current column (in valid region)
//     int row_fill_index = 0;         // current row being filled (0 to KERNEL_SIZE-1)
//     // The fill_channel counter indicates which channel is currently being written.
//     logic [$clog2(IN_CHANNELS)-1:0] fill_channel = 0;

//     // A flag to indicate that the buffer is full (i.e. the entire window span for all channels is filled).
//     logic buffer_full, initial_fill_done, update_fill_done;

//     //-------------------------------------------------------------------------
//     // Sliding window pointer (column index into line_mem)
//     // This pointer indicates the left‐most column of the current window.
//     int col_index_window_reg = 0;

//     //-------------------------------------------------------------------------
//     // Update phase pointers (for shifting when buffer is full)
//     int col_index_update = PADDING; // When shifting, the column to update in the new (bottom) row.
//     int shift_flag       = 0;       // Indicates that we are in the middle of shifting rows.
//     // A separate update_channel counter for channel‐by‐channel update of row3.
//     logic [$clog2(IN_CHANNELS)-1:0] update_channel = 0;

//     //-------------------------------------------------------------------------
//     // Output Channel
//     // This counter cycles through channels so that each cycle the window for one channel is output.
//     logic [$clog2(IN_CHANNELS)-1:0] output_channel = 0;

//     // A helper signal: window_ready is high when we have enough valid data in the buffer.
//     // (We use row_fill_index and col_index from the fill phase.)
//     wire window_ready;
//     assign window_ready = ((row_fill_index >= KERNEL_SIZE-1 && col_index > (WINDOW_WIDTH - 1)) || buffer_full);

//     //-------------------------------------------------------------------------
//     // Buffer Full Flag Logic
//     //-------------------------------------------------------------------------
//     always_ff @(posedge clk) begin
//         if (rst) begin
//             buffer_full <= 0;
//         end else begin
//             // Consider the buffer full when we've filled at least KERNEL_SIZE rows
//             // and the valid region has been completely filled for all channels.
//             if ((row_fill_index >= KERNEL_SIZE-1) && (col_index == IMAGE_WIDTH) && (fill_channel == IN_CHANNELS - 1))
//                 buffer_full <= 1;
//         end
//     end

//     //-------------------------------------------------------------------------
//     // Fill / Update Logic (writes pixels into line_mem channel-by-channel)
//     //-------------------------------------------------------------------------
//     always_ff @(posedge clk or posedge rst) begin
//         if (rst) begin
//             // Reset: clear all line memory.
//             for (int c = 0; c < IN_CHANNELS; c++) begin
//                 for (int j = 0; j < KERNEL_SIZE; j++) begin
//                     for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
//                         line_mem[c][j][k] <= 0;
//                     end
//                 end
//             end
//             col_index            <= PADDING;
//             row_fill_index       <= 0;
//             fill_channel         <= 0;
//             col_index_window_reg <= 0;
//             col_index_update     <= PADDING;
//             shift_flag           <= 0;
//             update_channel       <= 0;
//             initial_fill_done    <= 0;
//             update_fill_done     <= 0;
//         end else begin
//             if (!buffer_full || MAX_POOL) begin
//                 // ----- Filling Phase -----
//                 // Write the incoming pixel into the line_mem for the current fill_channel.
//                 if (PADDING && ((row_fill_index == 0 && pad_top) ||
//                                 (row_fill_index == KERNEL_SIZE-1 && pad_bottom)))
//                     line_mem[fill_channel][row_fill_index][col_index] <= 0;
//                 else
//                     line_mem[fill_channel][row_fill_index][col_index] <= pixel_in;

//                 // Advance the fill_channel counter.
//                 if (fill_channel < IN_CHANNELS - 1)
//                     fill_channel <= fill_channel + 1;
//                 else begin
//                     fill_channel <= 0;
//                     // Once all channels have been written for this pixel position, advance the column pointer.
//                     if (col_index < (PADDING + IMAGE_WIDTH - 1))
//                         col_index <= col_index + 1;
//                     else if (row_fill_index < KERNEL_SIZE - 1) begin
//                         col_index <= PADDING;
//                         row_fill_index <= row_fill_index + 1;
//                     end else begin
//                         // If already in the last row, stall further writes.
//                         row_fill_index <= row_fill_index;
//                     end
//                 end

//                 // In the filling phase, update the sliding window pointer as new valid pixels come in.
//                 if (!MAX_POOL && (row_fill_index >= KERNEL_SIZE - 1 && col_index > WINDOW_WIDTH - 1 && fill_channel == IN_CHANNELS-1)) begin
//                     col_index_window_reg <= col_index_window_reg + STRIDE;
//                     if (col_index_window_reg >= (IMAGE_WIDTH - STRIDE))
//                         col_index_window_reg <= 0;
//                 end

//             end else if (buffer_full && col_index_window_reg < IMAGE_WIDTH && !initial_fill_done) begin
//                 // Initial fill complete phase for output.
//                 if (col_index_window_reg == IMAGE_WIDTH - 1 && output_channel == IN_CHANNELS - 2) begin
//                     initial_fill_done <= 1;
//                 end
//                 if (!MAX_POOL && (row_fill_index >= KERNEL_SIZE - 1 && col_index > WINDOW_WIDTH - 1 && output_channel >= IN_CHANNELS-1)) begin
//                     col_index_window_reg <= col_index_window_reg + STRIDE;
//                 end
//             end else begin
//                 // ----- Shift and Update Phase -----
//                 if (col_index_window_reg >= (IMAGE_WIDTH - STRIDE) && output_channel == IN_CHANNELS - 1)
//                     col_index_window_reg <= 0;

//                 if (col_index_window_reg == IMAGE_WIDTH - 1 && output_channel == IN_CHANNELS - 1)
//                     update_fill_done <= 1;

//                 // ----- Row Shift -----
//                 // When the current window has reached the end and all channels have been output,
//                 // shift every channel's rows upward.
//                 if (!shift_flag && col_index_window_reg == IMAGE_WIDTH - 1 && output_channel == IN_CHANNELS - 1) begin
//                     for (int c = 0; c < IN_CHANNELS; c++) begin
//                         // Shift row 1 into row 0.
//                         for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
//                             if (PADDING && pad_top)
//                                 line_mem[c][0][k] <= 0;
//                             else
//                                 line_mem[c][0][k] <= line_mem[c][1][k];
//                         end
//                         // Shift row 2 into row 1.
//                         for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
//                             line_mem[c][1][k] <= line_mem[c][2][k];
//                         end
//                     end
//                     // Prepare to update row 2 (the new row) channel-by-channel.
//                     col_index_update <= PADDING;
//                     shift_flag       <= 1;
//                     update_channel   <= 0;
//                 end

//                 // ----- Updated Row 2 Write: Stall until window output is complete -----
//                 // Only update row 2 when output_channel is 0, meaning the window has been fully output.
//                 if (col_index_update < (PADDING + IMAGE_WIDTH)) begin
//                     if (PADDING && pad_bottom)
//                         line_mem[update_channel][2][col_index_update] <= 0;
//                     else if ((col_index_update >= PADDING) && (col_index_update < (PADDING + IMAGE_WIDTH)))
//                         line_mem[update_channel][2][col_index_update] <= pixel_in;
                    
//                     // Advance update_channel.
//                     if (update_channel < IN_CHANNELS - 1)
//                         update_channel <= update_channel + 1;
//                     else begin
//                         update_channel <= 0;
//                         // Once all channels have been updated for this column, advance col_index_update.
//                         if (col_index_update < (PADDING + IMAGE_WIDTH - 1))
//                             col_index_update <= col_index_update + 1;
//                         else if (update_fill_done) begin
//                             col_index_update <= PADDING;
//                             shift_flag       <= 0; // End shift; ready for next update phase.
//                             update_fill_done <= 0;
//                         end
//                     end
//                 end
//                 // If output_channel is not 0, do nothing so as not to overwrite row 2.
//             end 
//         end
//     end

//     //-------------------------------------------------------------------------
//     // Output Window Generation (channel-by-channel)
//     //-------------------------------------------------------------------------
//     always_comb begin
//         if (window_ready && (!shift_flag || col_index_update > WINDOW_WIDTH - 1)) begin
//             for (int j = 0; j < KERNEL_SIZE; j++) begin
//                 for (int k = 0; k < WINDOW_WIDTH; k++) begin
//                     window_out[j][k] = line_mem[output_channel][j][col_index_window_reg + k];
//                 end
//             end
//         end else begin
//             // If not ready, output zeros.
//             for (int j = 0; j < KERNEL_SIZE; j++) begin
//                 for (int k = 0; k < WINDOW_WIDTH; k++) begin
//                     window_out[j][k] = 0;
//                 end
//             end
//         end
//     end

//     //-------------------------------------------------------------------------
//     // Output Channel and Sliding Pointer Update
//     //-------------------------------------------------------------------------
//     always_ff @(posedge clk or posedge rst) begin
//         if (rst) begin
//             output_channel <= 0;
//         end else if (window_ready && (!shift_flag || col_index_update > WINDOW_WIDTH - 1)) begin
//             if (output_channel < IN_CHANNELS - 1)
//                 output_channel <= output_channel + 1;
//             else begin
//                 output_channel <= 0;
//                 // Advance the sliding pointer for the next window.
//                 if (col_index_window_reg < EFFECTIVE_WIDTH - WINDOW_WIDTH)
//                     col_index_window_reg <= col_index_window_reg + STRIDE;
//             end
//         end
//     end

//     //-------------------------------------------------------------------------
//     // Pass the sliding window pointer to the output port.
//     //-------------------------------------------------------------------------
//     assign col_index_window = col_index_window_reg;

// endmodule


// // ////////////////////old code waits for whole row///////////////////////
// module line_buffer #(
//     parameter IN_CHANNELS  = 4,
//     parameter IMAGE_WIDTH  = 128,  
//     parameter KERNEL_SIZE  = 3,    
//     parameter DATA_WIDTH   = 16,
//     parameter NUM_PIXELS   = 3,
//     parameter PADDING      = 1
// )(
//     input  logic clk,
//     input  logic rst,
//     input  logic [DATA_WIDTH-1:0] pixel_in [IN_CHANNELS], 
//     input  logic pad_top,    // When asserted, force top row to zero
//     input  logic pad_bottom, // When asserted, force bottom row to zero
//     output logic signed [DATA_WIDTH-1:0] window_out [IN_CHANNELS][KERNEL_SIZE][KERNEL_SIZE+NUM_PIXELS-1],
//     output logic frame_end_flag, // Raised when window reaches end of padded frame
//     // For sliding window extraction over the padded frame.
//     output logic [DATA_WIDTH-1:0] col_index_window       // Pointer into the padded memory for window extraction
// );

//     // Effective width includes left and right padding.
//     localparam EFFECTIVE_WIDTH = IMAGE_WIDTH + 2*PADDING;

//     // line_mem now stores KERNEL_SIZE rows of EFFECTIVE_WIDTH columns.
//     logic [DATA_WIDTH-1:0] line_mem [IN_CHANNELS][KERNEL_SIZE][EFFECTIVE_WIDTH];

//     // Indices for filling and sliding.
//     // For initial fill, we only write into the valid region [PADDING, PADDING+IMAGE_WIDTH-1].
//     int col_index         = PADDING;  
//     int row_fill_index    = 0;         // Which row is being filled (0 to KERNEL_SIZE-1)
//     logic buffer_full     = 0;         // Set when all KERNEL_SIZE rows are filled


//     // For updating a new row after a frame is processed.
//     int col_index_update  = PADDING;     // Only update valid region columns.
//     int shift_flag        = 0;           // Indicates that we are in the middle of shifting rows

//     always_ff @(posedge clk) begin
//         if (rst) begin
//             // Reset: clear all line memory.
//             for (int c = 0; c < IN_CHANNELS; c++) begin
//                 for (int j = 0; j < KERNEL_SIZE; j++) begin
//                     for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
//                         line_mem[c][j][k] <= 0;
//                     end
//                 end
//             end
//             col_index         <= PADDING;
//             row_fill_index    <= 0;
//             buffer_full       <= 0;
//             col_index_window  <= 0;
//             col_index_update  <= PADDING;
//             shift_flag        <= 0;
//             frame_end_flag    <= 0;
//         end else begin
//             if (!buffer_full) begin
//                 // ----- Filling Phase -----
//                 // Insert incoming pixel data into the valid region of the current row.
//                 // If we're filling the top row and pad_top is asserted, or the bottom row and pad_bottom is asserted,
//                 // force zeros instead.
//                 for (int c = 0; c < IN_CHANNELS; c++) begin
//                     if ((row_fill_index == 0 && pad_top) ||
//                         (row_fill_index == KERNEL_SIZE-1 && pad_bottom))
//                         line_mem[c][row_fill_index][col_index] <= 0;
//                     else
//                         line_mem[c][row_fill_index][col_index] <= pixel_in[c];
//                 end

//                 // Advance the column pointer in the valid region.
//                 if (col_index < (PADDING + IMAGE_WIDTH - 1)) begin
//                     col_index <= col_index + 1;
//                 end else begin
//                     col_index <= PADDING;
//                     row_fill_index <= row_fill_index + 1;
//                 end

//                 // When all KERNEL_SIZE rows are filled, mark the buffer as full.
//                 if (row_fill_index == KERNEL_SIZE) begin
//                     buffer_full <= 1;
//                 end

//             end else begin
//                 // ----- Sliding Window & Update Phase -----
//                 // Slide the window over the padded frame with a stride equal to NUM_PIXELS.
//                 if (col_index_window < EFFECTIVE_WIDTH - (KERNEL_SIZE+NUM_PIXELS-1)) begin
//                     col_index_window <= col_index_window + NUM_PIXELS;
//                 end else begin
//                     frame_end_flag <= 1; // Indicate window reached the end of the padded frame

//                     // Shift rows upward.
//                     if (!shift_flag) begin
//                         for (int c = 0; c < IN_CHANNELS; c++) begin
//                             // For the top row: if pad_top is asserted, force zeros; otherwise shift row 1.
//                             for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
//                                 if (pad_top)
//                                     line_mem[c][0][k] <= 0;
//                                 else
//                                     line_mem[c][0][k] <= line_mem[c][1][k];
//                             end
//                             // Shift row 2 into row 1.
//                             for (int k = 0; k < EFFECTIVE_WIDTH; k++) begin
//                                 line_mem[c][1][k] <= line_mem[c][2][k];
//                             end
//                         end
//                         col_index_update <= PADDING;  // Restart filling of the valid region
//                     end

//                     // Overwrite row 3 (index 2) with new incoming pixels.
//                     // If pad_bottom is asserted, force zeros.
//                     for (int c = 0; c < IN_CHANNELS; c++) begin
//                         if (pad_bottom)
//                             line_mem[c][2][col_index_update] <= 0;
//                         else if ((col_index_update >= PADDING) && (col_index_update < (PADDING + IMAGE_WIDTH)))
//                             line_mem[c][2][col_index_update] <= pixel_in[c];
//                         else
//                             line_mem[c][2][col_index_update] <= 0;
//                     end

//                     shift_flag <= 1;

//                     // Move update pointer within the valid region.
//                     if (col_index_update < (PADDING + IMAGE_WIDTH - 1)) begin
//                         col_index_update <= col_index_update + 1;
//                     end else begin
//                         // Reset update pointer and sliding window pointer after finishing update.
//                         col_index_update <= PADDING;
//                         col_index_window <= 0;
//                         shift_flag <= 0;
//                     end
//                 end
//             end
//         end
//     end

//     // ----- Output Window Assignment -----
//     // Extract the window from the padded line memory.
//     // The window size is (KERNEL_SIZE+NUM_PIXELS-1) columns and KERNEL_SIZE rows.
//     always_comb begin
//         if (buffer_full && !shift_flag) begin
//             for (int c = 0; c < IN_CHANNELS; c++) begin
//                 for (int j = 0; j < KERNEL_SIZE; j++) begin
//                     for (int k = 0; k < KERNEL_SIZE+NUM_PIXELS-1; k++) begin
//                         window_out[c][j][k] = line_mem[c][j][col_index_window + k];
//                     end
//                 end
//             end
//         end else begin
//             // If the buffer is not yet ready or is shifting, output zeros.
//             for (int c = 0; c < IN_CHANNELS; c++) begin
//                 for (int j = 0; j < KERNEL_SIZE; j++) begin
//                     for (int k = 0; k < KERNEL_SIZE+NUM_PIXELS-1; k++) begin
//                         window_out[c][j][k] = 0;
//                     end
//                 end
//             end
//         end
//     end

// endmodule


