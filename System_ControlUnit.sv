module System_ControlUnit #(
    parameter NUM_IMAGES      = 4,
    parameter IMAGE_WIDTH     = 188,
    parameter IMAGE_HEIGHT    = 120,
    parameter DATA_WIDTH      = 16,
    parameter OUTPUT_SIZE     =12,
    parameter KERNEL_SIZE     = 3,
    parameter IMAGE_HEIGHT_2  = 188,
    parameter IMAGE_HEIGHT_3  = 188,
    parameter IMAGE_HEIGHT_4  = 188,
    parameter IMAGE_HEIGHT_5  = 188,
    parameter IMAGE_HEIGHT_6  = 188,
    
    parameter IN_CHANNELS    = 4,
    parameter IN_CHANNELS_2  = 4,
    parameter  IN_CHANNELS_3 = 4,
    parameter  IN_CHANNELS_4 = 4,
    parameter  IN_CHANNELS_5 = 4,
    parameter  IN_CHANNELS_6 = 4

   /////////to be done for the rest of pes////////////////////////////////////
)(
    input  logic                          clk,
    input  logic                          rst_n,           // active–low reset
    // input  logic                          start,           // pulse high to begin streaming

    // “maxpool_doneN” comes from each conv2d_top’s max_pool block
    input  logic                          maxpool_done1,
    input  logic                          maxpool_done2,
    input  logic                          maxpool_done3,
    input  logic                          maxpool_done4,
    input  logic                          maxpool_done5,
    input  logic                          maxpool_done6,
    input  logic                          fifo_pe1_2_empty,
    input  logic                          fifo_pe2_3_empty,
    input  logic                          fifo_pe3_4_empty,
    input  logic                          fifo_pe4_5_empty,
    input  logic                          fifo_pe5_6_empty,
    input  logic     [$clog2(IMAGE_HEIGHT_2)-1:0] num_shifts_counter_pe2,
    input  logic     [$clog2(IMAGE_HEIGHT_3)-1:0] num_shifts_counter_pe3,
    input  logic     [$clog2(IMAGE_HEIGHT_4)-1:0] num_shifts_counter_pe4,
    input  logic     [$clog2(IMAGE_HEIGHT_5)-1:0] num_shifts_counter_pe5,
    input  logic     [KERNEL_SIZE-1:0] row_fill_index_out_pe6,
    input  logic                       pad_bottom_pe6, 

    // Interface between the mac unit and the brams and fifos of the weights
    input  logic start_mac_1, start_mac_2, start_mac_3, start_mac_4, start_mac_5, start_mac_6,
    input  logic done_mac_1, done_mac_2, done_mac_3, done_mac_4, done_mac_5, done_mac_6,

    input  logic fill_window_ready_to_mac_pe1, update_window_ready_to_mac_pe1,
    input  logic fill_window_ready_to_mac_pe2, update_window_ready_to_mac_pe2,
    input  logic fill_window_ready_to_mac_pe3, update_window_ready_to_mac_pe3,
    input  logic fill_window_ready_to_mac_pe4, update_window_ready_to_mac_pe4,
    input  logic fill_window_ready_to_mac_pe5, update_window_ready_to_mac_pe5,
    input  logic fill_window_ready_to_mac_pe6, update_window_ready_to_mac_pe6,

    input  logic [$clog2(IN_CHANNELS)-1:0]  read_channel_idx_fifo1,
    input  logic [$clog2(IN_CHANNELS_2)-1:0] read_channel_idx_fifo2,
    input  logic [$clog2(IN_CHANNELS_3)-1:0]  read_channel_idx_fifo3, 
    input  logic [$clog2(IN_CHANNELS_4)-1:0]  read_channel_idx_fifo4,
    input  logic [$clog2(IN_CHANNELS_5)-1:0]   read_channel_idx_fifo5, 
    input  logic [$clog2(IN_CHANNELS_6)-1:0]   read_channel_idx_fifo6,
    //output logic rd_valid_1, rd_valid_2, rd_valid_3, rd_valid_4, rd_valid_5, rd_valid_6,
    output logic rd_ready_1, rd_ready_2, rd_ready_3, rd_ready_4, rd_ready_5, rd_ready_6,

    //////////////////////////////////////////////////////////////////////////////////////////////////////
    //– BRAM interface (to bram_images)
    // Control signals
    input  logic                          start_read,    // start convolution read phase
    input  logic                          write_pixel_ready,   // start loading next image batch

    // BRAM interface
    output logic                          bram_read_en,
    output logic                          bram_write_en,
    output logic [$clog2(NUM_IMAGES*IMAGE_WIDTH * IMAGE_HEIGHT)-1:0] bram_abs_read_addr,
    output logic [$clog2(NUM_IMAGES*IMAGE_WIDTH * IMAGE_HEIGHT)-1:0] bram_abs_write_addr,

    // conv PE interface (unchanged)
    output logic                          pe_valid_in,
    output logic                          pe_next_channel,
    
    output logic                          bank_select,
    ///////////////////////////////////////////////////////////////////////////////////////////////////////

    //– Enable signals for each PE
    output logic                          pe_enable,
    output logic                          pe2_enable,      // “enable” for PE₂ (driven by maxpool_done1)
    output logic                          pe3_enable,      // “enable” for PE₃ (driven by maxpool_done2)
    output logic                          pe4_enable,      // “enable” for PE₄ (driven by maxpool_done3)
    output logic                          pe5_enable,      // “enable” for PE₅ (driven by maxpool_done4)
    output logic                          pe6_enable       // “enable” for PE₆ (driven by maxpool_done5)
);

    //--------------------------------------------------------------------------------
    // Local parameters
    //--------------------------------------------------------------------------------
    localparam IMAGE_SIZE    = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam ADDR_WIDTH    = $clog2(IMAGE_SIZE);
    localparam CHANNEL_WIDTH = $clog2(NUM_IMAGES);

    // Ping-pong bank selector: toggles each time all pixels are done
    logic                          done_all;
    logic done_all_reg;
    always_ff @(posedge clk ) begin
        if(rst_n) begin
            done_all_reg <= 0;
        end else begin
            done_all_reg <= done_all;
        end
    end
    
    always_ff @(posedge clk) begin
        if (rst_n)
            bank_select <= 1'b0;
        else if (done_all && !done_all_reg)
            bank_select <= ~bank_select;
    end

    //------------------------------------------------------------------
    // Read State Machine
    //------------------------------------------------------------------
    typedef enum logic [1:0] {READ_IDLE, READ_ACTIVE} read_state_t;
    read_state_t read_state, read_next_state;
    logic [ADDR_WIDTH-1:0] read_pixel_counter;
    logic [CHANNEL_WIDTH-1:0] read_channel_counter;

    // //--------------------------------------------------------------------------------
    // // Internal counters
    // //--------------------------------------------------------------------------------
    // logic [ADDR_WIDTH-1:0]    pixel_counter;   // 0 .. IMAGE_SIZE−1
    // logic [CHANNEL_WIDTH-1:0] channel_counter; // 0 .. NUM_IMAGES−1

    logic [$clog2(NUM_IMAGES)-1:0] bram_read_img_sel;    // connect to bram_images.img_sel
    logic [ADDR_WIDTH-1:0] bram_read_addr;       // connect to bram_images.addr
    


    logic [$clog2(NUM_IMAGES)-1:0] bram_write_img_sel;    // connect to bram_images.img_sel
    logic [$clog2(NUM_IMAGES*IMAGE_SIZE)-1:0] bram_write_addr;       // connect to bram_images.addr
    

    //--------------------------------------------------------------------------------
    // “Startup” flag for PE₁ enable
    //--------------------------------------------------------------------------------
    logic first_pixel_seen;

    //--------------------------------------------------------------------------------
    // 1) READ FSM
    //--------------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst_n) begin
            read_state           <= READ_IDLE;
            read_pixel_counter   <= '0;
            read_channel_counter <= '0;
            done_all        <= 1'b0;
        end else begin
            read_state <= read_next_state;

            if (read_state == READ_IDLE && start_read) begin
                // When start pulses in IDLE, reset both counters and clear done_all
                read_pixel_counter   <= '0;
                read_channel_counter <= '0;
                done_all        <= 1'b0;
            end
            else if (read_state == READ_ACTIVE) begin
                // Each cycle in STREAM, if we are reading from BRAM, bump channel_counter
                if (bram_read_en) begin
                    if (read_channel_counter == NUM_IMAGES - 1) begin
                        // We just read ch = 3 for this pixel; move to next spatial pixel
                        read_channel_counter <= '0;

                        if (read_pixel_counter == IMAGE_SIZE - 1) begin
                            // Last pixel of last image → signal done_all and hold counters
                            read_pixel_counter <= read_pixel_counter;
                            done_all      <= 1'b1;
                        end else begin
                            // Move to next row/col in the image
                            read_pixel_counter <= read_pixel_counter + 1;
                        end
                    end else begin
                        // Still within the same spatial pixel → just next channel
                        read_channel_counter <= read_channel_counter + 1;
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------------------
    // 2) READ Next‐state logic
    //--------------------------------------------------------------------------------
    always_comb begin
        read_next_state = read_state;
        case (read_state)
            READ_IDLE: begin
                if (start_read) read_next_state = READ_ACTIVE;
            end
            READ_ACTIVE: begin
                if (done_all) read_next_state = READ_IDLE;
            end
        endcase
    end


    //------------------------------------------------------------------
    // Write FSM
    //------------------------------------------------------------------
    typedef enum logic {WRITE_IDLE, WRITE_ACTIVE} write_state_t;
    write_state_t write_state, write_next;
    logic [$clog2(IMAGE_SIZE*NUM_IMAGES)-1:0] write_pixel_counter;

    // State register and counters
    always_ff @(posedge clk) begin
        if (rst_n) begin
            write_state           <= WRITE_IDLE;
            write_pixel_counter   <= '0;
        end else begin
            write_state <= write_next;

            if (write_state == WRITE_ACTIVE) begin
                if (write_pixel_counter != NUM_IMAGES*IMAGE_SIZE-1) begin
                    write_pixel_counter <= write_pixel_counter + 1;
                end
            end else if (write_state == WRITE_IDLE && write_pixel_ready) begin
                write_pixel_counter   <= 0;
            end
        end
    end

    // Next-state logic
    always_comb begin
        write_next = write_state;
        case (write_state)
            WRITE_IDLE:     if (write_pixel_ready) write_next = WRITE_ACTIVE;
            WRITE_ACTIVE:   if (write_pixel_counter == NUM_IMAGES*IMAGE_SIZE-1)
                               write_next = WRITE_IDLE;
        endcase
    end

    //--------------------------------------------------------------------------------
    // 3) Output assignments
    //--------------------------------------------------------------------------------

    // 3.1 ) BRAM read‐enable is high throughout STREAM and BRAM outputs: address = pixel_counter, image select = channel_counter
    assign bram_read_en = (read_state == READ_ACTIVE) && start_read;
    assign bram_read_addr    = read_pixel_counter;
    assign bram_read_img_sel = read_channel_counter;
    assign bram_abs_read_addr  = bram_read_img_sel * IMAGE_SIZE + bram_read_addr;

    assign bram_write_en      = (write_state == WRITE_ACTIVE);
    assign bram_abs_write_addr  = write_pixel_counter;
    

    // 3.3 ) PE₁: valid_in pulses exactly when bram_read_en = 1
    //       next_channel pulses when channel_counter wraps 3→0
    assign pe_valid_in     = bram_read_en;
    assign pe_next_channel = (read_state == READ_ACTIVE && read_channel_counter == NUM_IMAGES - 1);

    // 3.4 ) “Startup‐enable” for PE₁: goes high once the very first BRAM read occurs
    always_ff @(posedge clk or posedge rst_n) begin
        if (rst_n) begin
            first_pixel_seen <= 1'b0;
            pe_enable        <= 1'b0;
        end else begin
            if (bram_read_en && !first_pixel_seen) begin
                first_pixel_seen <= 1'b1;
                pe_enable        <= 1'b1;
            end
        end
    end


//////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //--------------------------------------------------------------------------------
    // 3.6) PE enables
    //--------------------------------------------------------------------------------
    assign pe2_enable = maxpool_done1
                     || (!fifo_pe1_2_empty && num_shifts_counter_pe2 >= IMAGE_HEIGHT_2 - KERNEL_SIZE)
                     || (num_shifts_counter_pe2 == IMAGE_HEIGHT_2 - KERNEL_SIZE + 1);

    assign pe3_enable = maxpool_done2
                     || (!fifo_pe2_3_empty && num_shifts_counter_pe3 >= IMAGE_HEIGHT_3 - KERNEL_SIZE)
                     || (num_shifts_counter_pe3 == IMAGE_HEIGHT_3 - KERNEL_SIZE + 1);

    assign pe4_enable = maxpool_done3
                     || (!fifo_pe3_4_empty && num_shifts_counter_pe4 >= IMAGE_HEIGHT_4 - KERNEL_SIZE)
                     || (num_shifts_counter_pe4 == IMAGE_HEIGHT_4 - KERNEL_SIZE + 1);

    assign pe5_enable = maxpool_done4
                     || (!fifo_pe4_5_empty && num_shifts_counter_pe5 >= IMAGE_HEIGHT_5 - KERNEL_SIZE)
                     || (num_shifts_counter_pe5 == IMAGE_HEIGHT_5 - KERNEL_SIZE + 1);

    assign pe6_enable = maxpool_done5
                     || (!fifo_pe5_6_empty && row_fill_index_out_pe6 == KERNEL_SIZE-1)
                     || (fifo_pe5_6_empty && pad_bottom_pe6);

    //--------------------------------------------------------------------------------
    // 4) MAC / weights-FIFO handshakes: rd_ready_i
    //    Latch high on a start_mac_i rising-edge, clear on done_mac_i rising-edge
    //--------------------------------------------------------------------------------
    always_ff @(posedge clk) begin
      if (rst_n) begin
        rd_ready_1 <= 1'b0;
        rd_ready_2 <= 1'b0;
        rd_ready_3 <= 1'b0;
        rd_ready_4 <= 1'b0;
        rd_ready_5 <= 1'b0;
        rd_ready_6 <= 1'b0;
      end else begin
        // PE1 handshake
        if (start_mac_1 && (fill_window_ready_to_mac_pe1 || update_window_ready_to_mac_pe1))     
          rd_ready_1 <= 1'b1;
        else if (read_channel_idx_fifo1 == IN_CHANNELS-1)   
            rd_ready_1 <= 1'b0;
        // PE2 handshake
        if (start_mac_2 && (fill_window_ready_to_mac_pe2 || update_window_ready_to_mac_pe2))       
            rd_ready_2 <= 1'b1;
        else if (read_channel_idx_fifo2 == IN_CHANNELS_2 -1)   
            rd_ready_2 <= 1'b0;
        // PE3 handshake
        if (start_mac_3 && (fill_window_ready_to_mac_pe3 || update_window_ready_to_mac_pe3))       
            rd_ready_3 <= 1'b1;
        else if (read_channel_idx_fifo3 == IN_CHANNELS_3 -1)   
            rd_ready_3 <= 1'b0;
        // PE4 handshake
        if (start_mac_4 && (fill_window_ready_to_mac_pe4 || update_window_ready_to_mac_pe4))       
            rd_ready_4 <= 1'b1;
        else if (read_channel_idx_fifo4 == IN_CHANNELS_4 -1)   
            rd_ready_4 <= 1'b0;
        // PE5 handshake
        if (start_mac_5 && (fill_window_ready_to_mac_pe5 || update_window_ready_to_mac_pe5))       
            rd_ready_5 <= 1'b1;
        else if (read_channel_idx_fifo5 == IN_CHANNELS_5 -1)   
            rd_ready_5 <= 1'b0;
        // PE6 handshake
        if (start_mac_6)       
            rd_ready_6 <= 1'b1;
        else if (read_channel_idx_fifo6 == IN_CHANNELS_6 -1)   
            rd_ready_6 <= 1'b0;
      end
    end
    
endmodule






// module System_ControlUnit #(
//     parameter NUM_IMAGES      = 4,
//     parameter IMAGE_WIDTH     = 188,
//     parameter IMAGE_HEIGHT    = 120,
//     parameter DATA_WIDTH      = 16,
//     parameter OUTPUT_SIZE     =12,
//     parameter TOP_BOTTOM_PADDING         =1
// )(
//     input  logic                          clk,
//     input  logic                          rst_n,           // active–low reset
//     input  logic                          start,           // pulse high to begin streaming

//     // “maxpool_doneN” comes from each conv2d_top’s max_pool block
//     input  logic                          maxpool_done1,
//     input  logic                          maxpool_done2,
//     input  logic                          maxpool_done3,
//     input  logic                          maxpool_done4,
//     input  logic                          maxpool_done5,
//     input  logic                          maxpool_done6,

//     //– BRAM interface (to bram_images)
//     output logic                          bram_read_en,    // connect to bram_images.read_en
//     output logic [$clog2(NUM_IMAGES)-1:0] bram_img_sel,    // connect to bram_images.img_sel
//     output logic [$clog2(IMAGE_WIDTH*IMAGE_HEIGHT)-1:0]
//                                           bram_addr,       // connect to bram_images.addr

//     //– PE₁ (conv2d_top) interface
//     output logic                          pe_valid_in,     // conv2d_top.valid_in for PE₁
//     output logic                          pe_next_channel, // conv2d_top.next_channel for PE₁

//     //– Indicates “all four images fully read out of BRAM”
//     output logic                          done_all,

//     //– Enable signals for each PE
//     output logic                          pe_enable, top_pad, bottom_pad,      // “start‐enable” for PE₁
//     output logic                          pe2_enable,      // “enable” for PE₂ (driven by maxpool_done1)
//     output logic                          pe3_enable,      // “enable” for PE₃ (driven by maxpool_done2)
//     output logic                          pe4_enable,      // “enable” for PE₄ (driven by maxpool_done3)
//     output logic                          pe5_enable,      // “enable” for PE₅ (driven by maxpool_done4)
//     output logic                          pe6_enable,       // “enable” for PE₆ (driven by maxpool_done5)
//     output logic                          finished_4_images
// );

//     //--------------------------------------------------------------------------------
//     // Local parameters
//     //--------------------------------------------------------------------------------
//     localparam IMAGE_SIZE    = IMAGE_WIDTH * (IMAGE_HEIGHT);
//     localparam ADDR_WIDTH    = $clog2(IMAGE_SIZE);
//     localparam CHANNEL_WIDTH = $clog2(NUM_IMAGES);

//     //--------------------------------------------------------------------------------
//     // State machine for IDLE vs STREAM
//     //--------------------------------------------------------------------------------
//     typedef enum logic [1:0] {
//         IDLE,
//         STREAM
//     } cu_state_t;

//     cu_state_t state, next_state;

//     //--------------------------------------------------------------------------------
//     // Internal counters
//     //--------------------------------------------------------------------------------
//     logic [ADDR_WIDTH-1:0]    pixel_counter;   // 0 .. IMAGE_SIZE−1
//     logic [CHANNEL_WIDTH-1:0] channel_counter; // 0 .. NUM_IMAGES−1
//     // Row counter counts from 0 up to IMAGE_HEIGHT+PADDING
//     logic [$clog2(IMAGE_HEIGHT+TOP_BOTTOM_PADDING+1)-1:0] row_counter;
//     logic [$clog2(IMAGE_WIDTH+TOP_BOTTOM_PADDING+1)-1:0]  width_counter;
 
//     //--------------------------------------------------------------------------------
//     // “Startup” flag for PE₁ enable
//     //--------------------------------------------------------------------------------
//     logic first_pixel_seen;

//     //--------------------------------------------------------------------------------
//     // 1) State register + counters
//     //--------------------------------------------------------------------------------
//     always_ff @(posedge clk or posedge rst_n) begin
//         if (rst_n) begin
//             state            <= IDLE;
//             pixel_counter    <= '0;
//             channel_counter  <= '0;
//             row_counter      <= '0;
//             done_all         <= 1'b0;
//             first_pixel_seen <= 1'b0;
//             width_counter    <= 0;
//         end else begin
//             state <= next_state;

//             if (state == IDLE && start) begin
//                 // Reset everything at the start of streaming
//                 pixel_counter    <= '0;
//                 channel_counter  <= '0;
//                 row_counter      <= '0;
//                 done_all         <= 1'b0;
//                 first_pixel_seen <= 1'b0;
//                 width_counter    <= 0;
//             end
//             else if (state == STREAM) begin
//                 if (bram_read_en || top_pad || bottom_pad) begin


//                     // Advance channel
//                     if (channel_counter == NUM_IMAGES-1) begin
//                         channel_counter <= '0;

//                         // Advance pixel within the image
//                         if (pixel_counter == IMAGE_SIZE-1) begin
//                             // End of image
//                             pixel_counter <= 0;
//                             // done_all <= 1'b1;
//                             // pixel_counter <= pixel_counter;
//                         end else begin
//                         	if (!top_pad) begin//!bottom_pad && 
//                         		pixel_counter <= pixel_counter + 1;
//                         	end
                      
//                             width_counter <= width_counter + 1;

//                             // On moving from last channel of (row,col), possibly update row
//                             // Check if we crossed a row boundary:
//                             if (width_counter == IMAGE_WIDTH -1) begin

//                             	if (row_counter == IMAGE_HEIGHT + 2) begin
//                             		row_counter <= 0;
//                             		done_all <= 1'b1;
//                             	end else begin
//                             		row_counter <= row_counter + 1;
//                             	end
//                                 // we just finished a full row → increment row_counter
                                
//                                 width_counter <= 0;
//                             end
//                         end
//                     end else begin
//                         channel_counter <= channel_counter + 1;
//                     end
//                 end
//             end
//         end
//     end

//     //--------------------------------------------------------------------------------
//     // 2) Next‐state logic
//     //--------------------------------------------------------------------------------
//     always_comb begin
//         next_state = state;
//         case (state)
//             IDLE: begin
//                 if (start) next_state = STREAM;
//             end
//             STREAM: begin
//                 if (done_all) next_state = IDLE;
//             end
//         endcase
//     end

//     //--------------------------------------------------------------------------------
//     // 3) Output assignments
//     //--------------------------------------------------------------------------------
//     always_comb begin
//         top_pad    = (row_counter <  TOP_BOTTOM_PADDING);
//         bottom_pad = (row_counter == IMAGE_HEIGHT + 1);// && pixel_counter == IMAGE_SIZE-1;
//     end

//     // 3.1 ) BRAM read‐enable is high throughout STREAM
//     assign bram_read_en = (state == STREAM) && start && !top_pad && !bottom_pad;

//     // 3.2 ) BRAM outputs: address = pixel_counter, image select = channel_counter
//     assign bram_addr    = pixel_counter;
//     assign bram_img_sel = channel_counter;

//     // 3.3 ) PE₁: valid_in pulses exactly when bram_read_en = 1
//     //       next_channel pulses when channel_counter wraps 3→0
//     assign pe_valid_in     = bram_read_en;
//     assign pe_next_channel = (state == STREAM && channel_counter == NUM_IMAGES - 1);

//     // 3.4 ) “Startup‐enable” for PE₁: goes high once the very first BRAM read occurs
//     always_ff @(posedge clk or posedge rst_n) begin
//         if (rst_n) begin
//             first_pixel_seen <= 1'b0;
//             pe_enable        <= 1'b0;
//         end else begin
//             if (bram_read_en && !first_pixel_seen) begin
//                 first_pixel_seen <= 1'b1;
//                 pe_enable        <= 1'b1;
//             end
//         end
//     end

//     // 3.5 ) Raises done_all whenever all 4×IMAGE_SIZE pixels have been read
//     //       (this is set inside the state‐machine above)

//     // 3.6 ) Generate “enable” for each downstream PE based on its predecessor’s maxpool_done
//     //       Note: maxpool_done1 enables PE₂, maxpool_done2 enables PE₃, …, maxpool_done5 enables PE₆.

//     assign pe2_enable = maxpool_done1;
//     assign pe3_enable = maxpool_done2;
//     assign pe4_enable = maxpool_done3;
//     assign pe5_enable = maxpool_done4;
//     assign pe6_enable = maxpool_done5;

    

//     logic [DATA_WIDTH-1:0] counter_last_pixel_out;

//     always_ff @(posedge clk or posedge rst_n) begin 
//     	if(rst_n) begin
//     		counter_last_pixel_out <= 0;
//     		finished_4_images <=0;
//     	end else if (counter_last_pixel_out == OUTPUT_SIZE) begin
//     		counter_last_pixel_out <= 0;
//     		finished_4_images <= 1;
//     	end else if (maxpool_done6) begin
//     		counter_last_pixel_out <= counter_last_pixel_out + 1;
//     		finished_4_images <= 0;
//     	end
//     end

//     // (Optionally, you can ignore maxpool_done6, since there is no PE₇ to enable.)

// endmodule
