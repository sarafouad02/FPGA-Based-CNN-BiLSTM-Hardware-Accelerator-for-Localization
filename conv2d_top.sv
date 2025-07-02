module conv2d_top #(
    parameter IN_CHANNELS     = 4,
    parameter OUT_CHANNELS    = 8,
    parameter KERNEL_SIZE     = 3,
    parameter STRIDE          = 1,
    parameter PADDING         = 1,
    parameter IMAGE_WIDTH     = 128, // Needed for buffer and FIFO
    parameter IMAGE_HEIGHT    = 120,
    parameter DATA_WIDTH      = 16,
    parameter MAX_POOL_KERNEL = 2,
    parameter FRAC_SZ         = 12,
    parameter PE_NUM          =1
)(
    input  logic clk,
    input  logic rst,
    input  logic  ENABLE_PE, //pad_top, pad_bottom,
    input  logic signed [DATA_WIDTH-1:0] pixel_in, // Now row-wise input
    input  logic signed [DATA_WIDTH-1:0] kernel_weights [KERNEL_SIZE][KERNEL_SIZE], 
    input  logic weights_rd_valid,
    output logic signed [DATA_WIDTH-1:0] output_feature_map,
    output logic bram_en, maxpool_done, num_shifts_flag,  line_buffer_en_top, pad_bottom, pad_top,
    output logic [KERNEL_SIZE-1:0] row_fill_index_out, 
    output logic bn_fifo_full_to_cu,
    output logic start_mac, done_mac,fill_window_ready_to_mac, update_window_ready_to_mac,
    output logic [$clog2(IMAGE_HEIGHT)-1:0] num_shifts_counter
    
    //output logic [DATA_WIDTH-1:0]  bram_addr   
);
    // Control unit signals
    logic line_buffer_en, line_buffer_en_reg1, line_buffer_en_reg2, buffer_full, last_row_done, initial_fill_done, buffer_slide, wr_en_bnfifo_in, rd_en_bnfifo_in, ready_to_read; 
    logic   relu_done, max_fifo_en, maxpool_en, bnfifo_rd_to_bn;
    // Buffered output for MAC array
    logic [$clog2(IN_CHANNELS)-1:0] output_channel;

    // Instantiate a simple FIFO (buffering one row, width = IMAGE_WIDTH)
    // Note: Our FIFO reset is active low, so we connect ~rst.
    logic bn_fifo_empty, bn_fifo_full, bn_fifo_empty_to_cu, out_when_ready_pe_other_mac_flag, out_when_ready_pe6_mac_flag;
    logic signed [DATA_WIDTH-1:0] bn_fifo_dout;
    logic shift_flag;
    logic [$clog2(IN_CHANNELS)-1:0] output_channel_to_mac;
    // logic pad_top, pad_bottom;

    logic signed [DATA_WIDTH-1:0] window_out [KERNEL_SIZE][KERNEL_SIZE];
    logic signed [DATA_WIDTH-1:0] mac_result;

    // Batch normalization output
    logic signed [DATA_WIDTH-1:0] bn_result;
    logic bn_done;

    // RELU output
    logic signed [DATA_WIDTH-1:0] relu_out;

    // maxpool fifo out
    logic [DATA_WIDTH-1:0] maxpool_fifo_out_reg [MAX_POOL_KERNEL][MAX_POOL_KERNEL];

    // maxpool out 
    logic signed [DATA_WIDTH-1:0] maxpool_out;

    // pipelining registers /////////////////////////////////////////////
    // buffer_mac_reg
    logic signed [DATA_WIDTH-1:0] window_out_mac [KERNEL_SIZE][KERNEL_SIZE];
    logic bn_en, start_mac_reg;


    // mac_bn_reg
    logic signed [DATA_WIDTH-1:0] mac_output_bnfifo;
    logic bn_en_bn, bnfifo_wr_en;

    // bn_relu_reg
    logic signed [DATA_WIDTH-1:0] bn_output_relu;
    logic relu_en_relu;

    // relu_maxfifo_Reg
    logic [DATA_WIDTH-1:0] output_data_max_fifo;

    // maxfifo_maxpool_reg
    logic [DATA_WIDTH-1:0] window_out_maxpool [MAX_POOL_KERNEL][MAX_POOL_KERNEL];
    // logic frame_end_flag_maxpool_reg; // Raised when window reaches end of padded frame
    logic valid_window_maxfifo, en_maxfifo_reg, maxpool_en_maxpool;

    logic signed [DATA_WIDTH-1:0] bn_mean, bn_std, bn_gamma ,bn_beta;
    logic signed [DATA_WIDTH-1:0] bn_mean_reg, bn_std_reg, bn_gamma_reg ,bn_beta_reg;

    assign line_buffer_en_top = (PE_NUM == 1 && !initial_fill_done)?
                                 line_buffer_en_reg2 : (PE_NUM != 1 && !initial_fill_done && row_fill_index_out == 0)?
                                    line_buffer_en_reg1 : line_buffer_en;

    //in case of pe = 2 or more  want to differentiate between 
    // the line_bufffer_en going to the line buffer and the one going to the wrapper
    logic line_buffer_en_for_buff;
    always_ff @(posedge clk) begin : proc_for_buff
        if(rst) begin
            line_buffer_en_for_buff <= 0;
        end else begin
            if (PE_NUM == 1 && !initial_fill_done) begin
                line_buffer_en_for_buff <= line_buffer_en_reg1;
            end else if (PE_NUM != 1 && !initial_fill_done && row_fill_index_out == 0) begin
                line_buffer_en_for_buff <= line_buffer_en;
            end else if (PE_NUM != 1) begin
                line_buffer_en_for_buff <= line_buffer_en_top;
            end else begin
                line_buffer_en_for_buff <= 0;
            end
            
        end
    end

/////////////////////////////////////////////////////DUAL PORT BRAMS FOR BATCH NORMALIZATION ///////////////////////////////////
logic bn_en_d;
always_ff @(posedge clk) begin 
    if(rst) begin
       bn_en_d  <= 0;
    end else begin
      bn_en_d   <=bn_en ;
    end
end

 dual_port_bn_bram #(.DATA_WIDTH(DATA_WIDTH), .OUT_CHANNELS(OUT_CHANNELS) , .PE_NUM      (PE_NUM) , .IS_MEAN_VAR (1)
 ) BRAM_MEAN_VAR(.clk(clk), .rst_n(!rst), .enable_a  (ready_to_read), .data_out_a(bn_mean), .enable_b(ready_to_read), .data_out_b(bn_std)
 );

 dual_port_bn_bram #(.DATA_WIDTH(DATA_WIDTH), .OUT_CHANNELS(OUT_CHANNELS) , .PE_NUM      (PE_NUM), .IS_MEAN_VAR (0)
 ) BRAM_GAMMA_BETA( .clk(clk), .rst_n(!rst), .enable_a  (ready_to_read), .data_out_a(bn_gamma), .enable_b(ready_to_read), .data_out_b(bn_beta)
 );
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Instantiate the control unit.
    PE_ControlUnit #(
        .ADDR_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(IN_CHANNELS), 
        .PE_NUM     (PE_NUM)
    ) PE_ControlUnit ( 
        .rst(rst), 
        .clk(clk), 
        .line_buffer_en_reg1(line_buffer_en_reg1), 
        .line_buffer_en_reg2(line_buffer_en_reg2),
        .buffer_full(buffer_full), 
        .last_row_done(last_row_done), 
        .bram_en(bram_en),
        .start(start_mac), 
        .done_mac(done_mac),
        .buffer_slide(buffer_slide),
        .fill_window_ready_to_mac(fill_window_ready_to_mac),
        //.bram_addr(bram_addr),
        .bn_en(bn_en),
        .update_window_ready_to_mac(update_window_ready_to_mac),
        .output_channel(output_channel),
        .bn_done(bn_done),
        .relu_en(relu_en),
        .relu_done(relu_done),
        .max_fifo_en(max_fifo_en),
        .shift_flag(shift_flag),
        .valid_window_maxfifo(valid_window_maxfifo),
        .maxpool_en(maxpool_en),
        .initial_fill_done(initial_fill_done),
        .wr_en_bnfifo(wr_en_bnfifo_in),
        .bnfifo_empty              (bn_fifo_empty_to_cu), 
        .bnfifo_full               (bn_fifo_full_to_cu),
        .rd_en_bnfifo(rd_en_bnfifo_in),
        .ENABLE_PE                 (ENABLE_PE),
        .line_buffer_en            (line_buffer_en),
        .bn_ready_to_read(ready_to_read),
        .out_when_ready_pe_other   (out_when_ready_pe_other_mac_flag),
        .out_when_ready_pe6        (out_when_ready_pe6_mac_flag),
        .pad_top(pad_top),    // When asserted, force top row to zero
        .pad_bottom(pad_bottom), // When asserted, force bottom row to zero
        .weights_rd_valid(weights_rd_valid) //coming from the fifo of weights
    );

    // Line buffer instantiation (row-wise input)
    line_buffer #(
        .IN_CHANNELS(IN_CHANNELS),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .PADDING(1), 
        .STRIDE(1), 
        .MAX_POOL(0), 
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .OUT_CHANNELS(OUT_CHANNELS),
        .PE_NUM(PE_NUM)
    ) buffer_unit (
        .clk(clk),
        .rst(rst),
        .line_buffer_en(line_buffer_en_for_buff || (PE_NUM ==1 && line_buffer_en_top && initial_fill_done)), //line_buffer_en_for_buff || (PE_NUM ==1 && line_buffer_en_top && initial_fill_done)
        .pixel_in(pixel_in),       // Row-wise input
        .window_out(window_out),   // 3×3 window
        .pad_top(pad_top),
        .buffer_full(buffer_full),
        .buffer_slide(buffer_slide),
        .fill_window_ready_to_mac(fill_window_ready_to_mac),
        .update_window_ready_to_mac(update_window_ready_to_mac),
        .last_row_done(last_row_done),
        .pad_bottom(pad_bottom), 
        .bram_en(bram_en),
        .shift_flag(shift_flag), 
        .bnfifo_full(bn_fifo_full_to_cu),
        .output_channel(output_channel),
        .initial_fill_done(initial_fill_done), 
        .out_when_ready_pe_other   (out_when_ready_pe_other_mac_flag),
        .num_shifts_flag(num_shifts_flag), 
        .weights_rd_valid(weights_rd_valid),
        .out_when_ready_pe6        (out_when_ready_pe6_mac_flag),
        .row_fill_index_out(row_fill_index_out), 
        .num_shifts_counter(num_shifts_counter)
    );
    /////////////////////////////////////////////////////////////////////////////////////////
    reg_buffer_mac #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(IN_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .STRIDE(STRIDE),
        .PADDING(PADDING),
        .MAX_POOL(0)
    ) reg_buffer_mac (
        .rst(rst),
        .clk(clk),
        .window_out_lb(window_out), 
        .window_out_mac(window_out_mac), 
        .output_channel_in(output_channel),
        .output_channel_out(output_channel_to_mac), 
        .start_lb(start_mac), 
        .start_mac(start_mac_reg)
    );
    ////////////////////////////////////////////////////////////////////////////////////////
    // MAC array for convolution (processing 3 pixels per cycle)
    mac_array #(
        .IN_CHANNELS(IN_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .PADDING(PADDING),
        .FRAC_SZ(FRAC_SZ)
    ) mac_unit (
        .clk(clk),
        .rst(rst),
        .input_feature_map(window_out_mac), // 3×3 sliding window
        .kernel_weights(kernel_weights),
        .output_channel(output_channel_to_mac),
        .mac_output(mac_result),
        .start(start_mac_reg), 
        .done(done_mac)
    );
    ///////////////////////////////////////////////////////////////////////////////////////////
    reg_mac_bnfifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(IN_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .STRIDE(STRIDE),
        .PADDING(PADDING),
        .MAX_POOL(0)    
    )
    reg_mac_bnfifo_inst (
        .clk(clk), 
        .rst(rst), 
        .mac_output_mac   (mac_result), 
        .mac_output_bnfifo(mac_output_bnfifo),
        .bnfifo_wr(wr_en_bnfifo_in),
        .bnfifo_wr_out(bnfifo_wr_en),
        .bnfifo_rd(rd_en_bnfifo_in),
        .bnfifo_rd_out(bnfifo_rd_en)
    );

    ////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////
    // add bn_buffer....
    
    // The write enable is taken from bn_en_bn and the read enable is driven by valid_in (adjust as needed)
    buffer #(
       .IMAGE_WIDTH(256),
       .DATA_WIDTH(DATA_WIDTH)
    ) bn_fifo_inst (
       .clk(clk),
       .rst_n(~rst),
       .wr_en(bnfifo_wr_en),
       .din(mac_output_bnfifo),
       .rd_en(bnfifo_rd_en),
       .dout(bn_fifo_dout),
       .full(bn_fifo_full),
       .empty(bn_fifo_empty)
    );

    ////////////////////////////////////////////////////////////////////////////////////////
    // add another reg(reg_bnfifo_bn)
    // This register will latch the FIFO's output before passing it into the batch normalization unit.
    logic signed [DATA_WIDTH-1:0] bn_buffered_out;
    reg_bnfifo_bn #(
       .DATA_WIDTH(DATA_WIDTH)
    ) reg_bnfifo_bn_inst (
       .clk(clk),
       .rst(rst),
       .data_in(bn_fifo_dout),
       .data_out(bn_buffered_out),
       .bn_en_in(bn_en),
       .bn_en_out(bn_en_bn),
       .rd_en_in(bnfifo_rd_en),
       .rd_en_out(bnfifo_rd_to_bn),
       .bn_fifo_full_in(bn_fifo_full),
       .bn_mean_reg_in   (bn_mean),
       .bn_std_reg_in    (bn_std), 
       .bn_gamma_reg_in  (bn_gamma), 
       .bn_beta_reg_in   (bn_beta), 
       .bn_mean_reg_out  (bn_mean_reg), 
       .bn_std_reg_out   (bn_std_reg), 
       .bn_gamma_reg_out (bn_gamma_reg), 
       .bn_beta_reg_out  (bn_beta_reg),
       .bn_fifo_full_out(bn_fifo_full_to_cu),
       .bn_fifo_empty_in(bn_fifo_empty),
       .bn_fifo_empty_out(bn_fifo_empty_to_cu)
    );

    ////////////////////////////////////////////////////////////////////////////
    // Batch normalization
    // localparam signed [DATA_WIDTH-1:0] BN_MEAN  = 16'd1000;
    // localparam signed [DATA_WIDTH-1:0] BN_VAR   = 16'd1024;
    // localparam signed [DATA_WIDTH-1:0] BN_GAMMA = 16'd1;
    // localparam signed [DATA_WIDTH-1:0] BN_BETA  = 16'd5;


    // Note: The batch norm now takes the output of the register (bn_buffered_out) instead of mac_output_bn.
    batch_norm #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_SZ(FRAC_SZ)
    ) bn_unit (
        .clk(clk),
        .rst(rst),
        .enable(bn_en_bn),
        .bn_input(bn_buffered_out),
        .mean_mov(bn_mean_reg),
        // .var_mov(bn_var),
        .gamma(bn_gamma_reg),
        .beta(bn_beta_reg),
        .std_mov         (bn_std_reg),
        .bn_done(bn_done), 
        .ready    (ready_to_read), 
        .bnfifo_read_flag(bnfifo_rd_to_bn),
        .bn_output(bn_result)
    );

    ////////////////////////////////////////////////////////////////////
    reg_bn_relu #(
         .DATA_WIDTH(DATA_WIDTH),
         .IN_CHANNELS(IN_CHANNELS),
         .KERNEL_SIZE(KERNEL_SIZE),
         .IMAGE_WIDTH(IMAGE_WIDTH),
         .STRIDE(STRIDE),
         .PADDING(PADDING),
         .MAX_POOL(0)
    ) reg_bn_relu (
        .clk(clk),
        .rst(rst), 
        .bn_output_relu(bn_output_relu), 
        .bn_output_bn(bn_result),
        .relu_en_bn(relu_en),
        .relu_en_relu(relu_en_relu)
    );
    ////////////////////////////////////////////////////////////////////
    // ReLU
    relu #(
        .DATA_WIDTH(DATA_WIDTH)
    ) ReLU (
        .input_data(bn_output_relu),
        .enable(relu_en_relu),
        .done(relu_done),
        .output_data(relu_out)
    );
    //////////////////////////////////////////////////////////////////////
    reg_relu_max_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(IN_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .STRIDE(STRIDE),
        .PADDING(PADDING),
        .MAX_POOL(0)
    ) reg_relu_max_fifo_inst ( 
        .rst(rst),
        .clk(clk),
        .output_data_relu(relu_out),
        .max_fifo_en_relu(max_fifo_en),
        .max_fifo_en_max_fifo(en_maxfifo_reg),
        .output_data_max_fifo(output_data_max_fifo)
    );
    //////////////////////////////////////////////////////////////////////
    // Line buffer instantiation max pool fifo
    maxpool_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .KERNEL_HEIGHT(MAX_POOL_KERNEL),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .STRIDE(2), .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .OUT_CHANNELS (OUT_CHANNELS),
        .PE_NUM(PE_NUM)
    ) max_pool_fifo (
        .rst(rst), 
        .clk(clk), 
        .pixel_in(output_data_max_fifo), 
        .en(en_maxfifo_reg), 
        .valid_chan(valid_window_maxfifo), 
        .window(maxpool_fifo_out_reg)
    );
    ///////////////////////////////////////////////////////////////////////////
    reg_maxfifo_maxpool #(
        .DATA_WIDTH(DATA_WIDTH),
        .KERNEL_SIZE(MAX_POOL_KERNEL)
    ) reg_maxfifo_maxpool_inst (
        .clk(clk),
        .rst(rst), 
        .maxpool_en_maxfifo(maxpool_en), 
        .window_maxpool(window_out_maxpool), 
        .maxpool_en_maxpool(maxpool_en_maxpool),
        .window_maxfifo(maxpool_fifo_out_reg)
    );
    ///////////////////////////////////////////////////////////////////////////////
    // Max Pool
    max_pool_2x2 #(
        .DATA_WIDTH(DATA_WIDTH),
        .MAX_POOL_KERNEL(MAX_POOL_KERNEL)
    ) max_pool (
        .clk(clk), 
        .rst(rst), 
        .enable(maxpool_en_maxpool),
        .maxpool_fifo_out(window_out_maxpool), 
        .pooled_pixel(maxpool_out),
        .maxpool_done    (maxpool_done)
    );

    // Output assignment.
    assign output_feature_map = maxpool_out;

    // Output valid signal is asserted when buffer has enough data
    // assign valid_out = valid_in && !frame_end_flag;
    
endmodule