module PE_ControlUnit #(
    parameter ADDR_WIDTH = 16,   // Adjust to cover your BRAM depth
    parameter IN_CHANNELS =4,
    parameter PE_NUM = 1
)(
    input  logic                   clk,
    input  logic                   rst,
    // Feedback signals from the line buffer
    input  logic                   buffer_full, pad_top, pad_bottom, bnfifo_empty, bnfifo_full, fill_window_ready_to_mac, update_window_ready_to_mac,  // Asserted when initial fill is complete
    input  logic                   last_row_done, done_mac, bn_ready_to_read, ENABLE_PE,
    input logic [$clog2(IN_CHANNELS)-1:0] output_channel, // Asserted when update phase is complete
    input  logic initial_fill_done,
    input logic bn_done, relu_done, valid_window_maxfifo,
    input logic shift_flag, out_when_ready_pe_other, out_when_ready_pe6,
    input logic weights_rd_valid,
    // Control outputs
    output logic                   line_buffer_en, line_buffer_en_reg1, line_buffer_en_reg2, bn_en, relu_en, // Enable for the line buffer to accept a pixel
    output logic                   bram_en, start, buffer_slide, wr_en_bnfifo, max_fifo_en, maxpool_en, rd_en_bnfifo  // Enable for the BRAM read
    // output logic [ADDR_WIDTH-1:0]  bram_addr       // Address sent to the BRAM
);
 
  // Simple address counter
  // logic [ADDR_WIDTH-1:0] addr_counter;
  logic first_mac_output =0;
  logic start_initial, start_forward; // enables for mac unit
  logic done_mac_sync;


  // // Update the address counter on each clock cycle when pixel feed is enabled.
  // always_ff @(posedge clk or posedge rst) begin
  //     if (rst) begin
  //         addr_counter <= 0;
  //     end else begin
  //         // Continue reading pixels if:
  //         // - We are in the fill phase (buffer is not yet full)
  //         // - Or we are in the update phase (buffer_full is true but last_row_done is still false)
  //         if (!buffer_full || (buffer_full && !last_row_done))
  //             addr_counter <= addr_counter + 1;
  //     end
  // end

  always_ff @(posedge clk ) begin
    if(rst) begin
      line_buffer_en_reg1 <= 0;
      line_buffer_en_reg2 <= 0;
    end else begin
      line_buffer_en_reg1 <= line_buffer_en;
      line_buffer_en_reg2 <= line_buffer_en_reg1;
    end 
    // if(PE_NUM == 1 && !initial_fill_done) begin
    //   line_buffer_en_reg1 <= line_buffer_en;
    //   line_buffer_en_reg2 <= line_buffer_en_reg1;
    // end else if(PE_NUM != 1 && !initial_fill_done) begin
    //   line_buffer_en_reg1 <= line_buffer_en;
    // end 
    //else begin
    //   line_buffer_en_reg1 <= 0;
    //   line_buffer_en_reg2 <= 0;
    // end
  end


  // Control enable signals using if conditions.
  always_comb begin
    line_buffer_en=0;
    bram_en =0;
    start_initial =0;
    start_forward =0;
    buffer_slide =0;
    bn_en =0;
    //first_mac_output=0;
    relu_en =0;
    max_fifo_en=0;
    maxpool_en=0;
          // In the fill phase, always enable pixel reads.
          if (!buffer_full && ENABLE_PE ) begin
              line_buffer_en = 1;
              //bram_en means that the line buffer is ready to accept a pixel as an input not an actual bram enable(ready signal)
              if (!pad_top && !pad_bottom )
                bram_en        = 1;
              else 
                bram_en        = 0;
          end
          // In the update phase, continue to enable until the new row is complete.
          else if (buffer_full && !last_row_done && initial_fill_done &&shift_flag && ENABLE_PE) begin
              line_buffer_en = 1;
              if (!pad_top && !pad_bottom )
                bram_en        = 1;
              else 
                bram_en        = 0;
          end
          // Otherwise, disable both outputs.
          else begin
              line_buffer_en = 0;
              bram_en        = 0;
          end

          //for mac 
          if((((PE_NUM==1 &&fill_window_ready_to_mac || PE_NUM!=1&&PE_NUM!=6 && out_when_ready_pe_other || PE_NUM == 6&&out_when_ready_pe6)&& output_channel==0) ||
                ((PE_NUM==1 &&update_window_ready_to_mac || PE_NUM!=1&&PE_NUM!=6 && out_when_ready_pe_other || PE_NUM == 6&&out_when_ready_pe6 )&& output_channel==0 )) && !bnfifo_full && (PE_NUM==1&&weights_rd_valid || PE_NUM!= 1)) begin

            start_initial =1;
          end
            else begin
            start_initial=0;
          end

          // if(first_mac_output && bn_done && ((fill_window_ready_to_mac && output_channel==0) ||(update_window_ready_to_mac && output_channel==0 ))) 
          //   start_forward = 1;
          // else
          //   start_forward = 0;

          if(done_mac_sync && !bnfifo_full && weights_rd_valid) begin 
            buffer_slide=1;
           // wr_en_bnfifo =1;
            // bn_en=1;
            // first_mac_output =1;
          end else begin
            // first_mac_output = 1;
            buffer_slide=0;
            // bn_en=0;
            //wr_en_bnfifo =0;
          end

          if(done_mac && !bnfifo_full) begin
            wr_en_bnfifo =1;
          end else begin
            wr_en_bnfifo =0;
          end


          if (!bnfifo_empty) begin
            bn_en =1;
          end else begin
            bn_en=0;
          end

          if (bn_ready_to_read) begin //&& !bn_done || bn_done
            rd_en_bnfifo =1;
          end else begin
            rd_en_bnfifo =0;
          end

          if(bn_done)
          begin
            relu_en=1;

            // buffer_slide=1;////////////////////
          end
          else begin
            relu_en=0;
            // buffer_slide=0;/////////////////////////////
          end
          if (relu_done) begin
            max_fifo_en = 1;
          end else begin
            max_fifo_en = 0;
          end

          if (valid_window_maxfifo) begin
            maxpool_en = 1;
          end else begin
            maxpool_en = 0;
          end
      end
    always_ff @(posedge clk ) begin 
      if(rst) begin
         done_mac_sync<= 0;
      end else begin
        if (done_mac && !bnfifo_full) begin
          done_mac_sync <=1;
        end
         else if(weights_rd_valid)
          done_mac_sync <=0;
      end
    end
  // Provide the current BRAM address.
  // assign bram_addr = addr_counter;
  assign start = start_initial || start_forward;
endmodule


