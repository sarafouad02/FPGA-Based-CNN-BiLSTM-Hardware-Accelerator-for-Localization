// CNN pipeline wrapper with 6 pipelined conv2d_top stages
module cnn_pipeline_wrapper #(
    parameter DATA_WIDTH   = 16,
    parameter KERNEL_SIZE  = 3,
    parameter STRIDE       = 1,
    parameter PADDING      = 1,
    parameter MAX_POOL_KERNEL = 2,
    parameter FRAC_SZ = 12,
    parameter IMAGE_WIDTH     = 64,
    parameter IMAGE_HEIGHT    = 64,
    parameter NUM_IMAGES      = 4,
    parameter TOP_BOTTOM_PADDING = 1,
    parameter IN_CHANNELS     =4,
    parameter OUT_CHANNELS    = 4
)(
    input  logic clk,
    input  logic rst,
    input  logic ENABLE_PE,
    input  logic [DATA_WIDTH-1:0] bram_image_in, //data to write it in the bram of images
    input  logic  write_pixel_ready, //signal input from the highlevel to write in the bram of images 

    output logic num_shifts_flag_pe1, maxpool_done6,
    output logic signed [DATA_WIDTH-1:0] output_feature_map
);


    localparam  IMAGE_WIDTH_2  = IMAGE_WIDTH/2;
    localparam  IMAGE_WIDTH_3  = IMAGE_WIDTH/4;
    localparam  IMAGE_WIDTH_4  = IMAGE_WIDTH/8;
    localparam  IMAGE_WIDTH_5  = IMAGE_WIDTH/16;
    localparam  IMAGE_WIDTH_6  = IMAGE_WIDTH/32;

    localparam  IMAGE_HEIGHT_2  = IMAGE_HEIGHT/2;
    localparam  IMAGE_HEIGHT_3  = IMAGE_HEIGHT/4;
    localparam  IMAGE_HEIGHT_4  = IMAGE_HEIGHT/8;
    localparam  IMAGE_HEIGHT_5  = IMAGE_HEIGHT/16;
    localparam  IMAGE_HEIGHT_6  = IMAGE_HEIGHT/32;

    localparam  IN_CHANNELS_2 = 4;
    localparam  IN_CHANNELS_3 = 8;
    localparam  IN_CHANNELS_4 = 8;
    localparam  IN_CHANNELS_5 = 16;
    localparam  IN_CHANNELS_6 = 8;

    localparam  OUT_CHANNELS_2 = 8;
    localparam  OUT_CHANNELS_3 = 8;
    localparam  OUT_CHANNELS_4 = 16;
    localparam  OUT_CHANNELS_5 = 8;
    localparam  OUT_CHANNELS_6 = 6;


    localparam DEPTH = IMAGE_WIDTH*IMAGE_HEIGHT*NUM_IMAGES;


    // Intermediate wires and valids for pipeline
    logic signed [DATA_WIDTH-1:0] stage_out [5:0];
    logic maxpool_done1, maxpool_done2, maxpool_done3, maxpool_done4, maxpool_done5;
    logic pe2_enable, pe3_enable, pe4_enable, pe5_enable, pe6_enable;
    logic ready_signal_to_sys_CU1;
    logic pad_top_pe1, pad_top_pe2, pad_top_pe3, pad_top_pe4, pad_top_pe5, pad_top_pe6, pad_top_reg_pe6;
    logic pad_bottom_pe1, pad_bottom_pe2, pad_bottom_pe3, pad_bottom_pe4, pad_bottom_pe5, pad_bottom_pe6;
    

    logic [DATA_WIDTH-1:0]            bram_image_out, bram_image_out_0, bram_image_out_1;
    logic                          bram_read_en, data_out_flag;   
    logic [$clog2(NUM_IMAGES)-1:0] bram_img_sel;    
    logic bram_write_en, bank_select;
    logic [$clog2(DEPTH)-1:0] bram_abs_read_addr;
    logic [$clog2(DEPTH)-1:0] bram_abs_write_addr;


    logic line_buffer_en_top1, line_buffer_en_top2, line_buffer_en_top3, line_buffer_en_top4, line_buffer_en_top5, line_buffer_en_top6;
    logic [KERNEL_SIZE-1:0] row_fill_index_out_pe1, row_fill_index_out_pe2, row_fill_index_out_pe3, row_fill_index_out_pe4, row_fill_index_out_pe5, row_fill_index_out_pe6;
    logic signed [DATA_WIDTH-1:0] reg_out_1, reg_out_2, reg_out_3, reg_out_4, reg_out_5;
    logic fifo_pe1_2_empty, fifo_pe2_3_empty, fifo_pe3_4_empty, fifo_pe4_5_empty, fifo_pe5_6_empty;
    logic [$clog2(IMAGE_HEIGHT_2)-1:0] num_shifts_counter_pe2;
    logic [$clog2(IMAGE_HEIGHT_3)-1:0] num_shifts_counter_pe3;
    logic [$clog2(IMAGE_HEIGHT_4)-1:0] num_shifts_counter_pe4;
    logic [$clog2(IMAGE_HEIGHT_5)-1:0] num_shifts_counter_pe5;


    logic start_stream_1, start_stream_2, start_stream_3, start_stream_4, start_stream_5 ,start_stream_6;
    logic weight_valid_1, weight_valid_2, weight_valid_3 ,weight_valid_4 ,weight_valid_5 ,weight_valid_6;

    logic signed [DATA_WIDTH-1:0] weight_data_1, weight_data_2 ,weight_data_3 ,weight_data_4 ,weight_data_5,weight_data_6;

    logic rd_valid_1, rd_valid_2, rd_valid_3, rd_valid_4, rd_valid_5, rd_valid_6;
    logic rd_ready_1, rd_ready_2, rd_ready_3, rd_ready_4, rd_ready_5, rd_ready_6;

    logic start_mac_1, start_mac_2 , start_mac_3, start_mac_4, start_mac_5, start_mac_6;
    logic done_mac_1, done_mac_2, done_mac_3, done_mac_4, done_mac_5, done_mac_6;
    logic fill_window_ready_to_mac_pe1 ,update_window_ready_to_mac_pe1; 
    logic fill_window_ready_to_mac_pe2, update_window_ready_to_mac_pe2;
    logic fill_window_ready_to_mac_pe3, update_window_ready_to_mac_pe3;
    logic fill_window_ready_to_mac_pe4, update_window_ready_to_mac_pe4;
    logic fill_window_ready_to_mac_pe5, update_window_ready_to_mac_pe5;
    logic fill_window_ready_to_mac_pe6, update_window_ready_to_mac_pe6; 

    logic [$clog2(IN_CHANNELS)-1:0]  read_channel_idx_fifo1; 
    logic [$clog2(IN_CHANNELS_2)-1:0] read_channel_idx_fifo2;
    logic [$clog2(IN_CHANNELS_3)-1:0] read_channel_idx_fifo3;
    logic [$clog2(IN_CHANNELS_4)-1:0] read_channel_idx_fifo4;
    logic [$clog2(IN_CHANNELS_5)-1:0] read_channel_idx_fifo5;
    logic [$clog2(IN_CHANNELS_6)-1:0] read_channel_idx_fifo6;

    logic bnfifo_full_1 ,bnfifo_full_2 ,bnfifo_full_3 ,bnfifo_full_4 ,bnfifo_full_5 ,bnfifo_full_6;

    logic fifo_full_fifo1, fifo_full_fifo2, fifo_full_fifo3, fifo_full_fifo4, fifo_full_fifo5, fifo_full_fifo6; 
    logic signed [DATA_WIDTH-1:0] weights_window_out_1[KERNEL_SIZE][KERNEL_SIZE];
    logic signed [DATA_WIDTH-1:0] weights_window_out_2[KERNEL_SIZE][KERNEL_SIZE];
    logic signed [DATA_WIDTH-1:0] weights_window_out_3[KERNEL_SIZE][KERNEL_SIZE];
    logic signed [DATA_WIDTH-1:0] weights_window_out_4[KERNEL_SIZE][KERNEL_SIZE];
    logic signed [DATA_WIDTH-1:0] weights_window_out_5[KERNEL_SIZE][KERNEL_SIZE];
    logic signed [DATA_WIDTH-1:0] weights_window_out_6[KERNEL_SIZE][KERNEL_SIZE];

    // interface of the bn BRAMS with the BN//////////////////////////////////
    //logic bn_en_pe1, bn_en_pe2, bn_en_pe3, bn_en_pe4, bn_en_pe5, bn_en_pe6;
    ///////////////////////////////BRAM for input images/////////////////////////////

    PingPongBRAM #(.DATA_WIDTH(DATA_WIDTH), .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .NUM_IMAGES(NUM_IMAGES)
        ) BRAM_IMG (
            .clk      (clk), 
            .read_en  (bram_read_en), 
            .bank_sel (bank_select), 
            .write_en (bram_write_en), 
            .addr_in_0 (bram_abs_write_addr),
            .addr_in_1 (bram_abs_write_addr),
            .addr_out_0(bram_abs_read_addr),
            .addr_out_1(bram_abs_read_addr), 
            .wdata_0    (bram_image_in),
            .wdata_1    (bram_image_in), 
            .rdata_out_0(bram_image_out_0), 
            .rdata_out_1(bram_image_out_1)
        );



    assign bram_image_out = bank_select? bram_image_out_1: bram_image_out_0;

        ///////////////////////////////////////////BRAMS for Weights/////////////////////////

      logic weight_valid_1_reg, weight_valid_2_reg, weight_valid_3_reg, weight_valid_4_reg, weight_valid_5_reg, weight_valid_6_reg;
    always_ff @(posedge clk) begin : proc_
        if(rst) begin
            weight_valid_1_reg <= 0;
            weight_valid_2_reg <= 0;
            weight_valid_3_reg <= 0;
            weight_valid_4_reg <= 0;
            weight_valid_5_reg <= 0;
            weight_valid_6_reg <= 0;
        end else begin
            weight_valid_1_reg <= weight_valid_1;
            weight_valid_2_reg <= weight_valid_2;
            weight_valid_3_reg <= weight_valid_3;
            weight_valid_4_reg <= weight_valid_4;
            weight_valid_5_reg <= weight_valid_5;
            weight_valid_6_reg <= weight_valid_6;
        end
    end

    bram_weights #(
        .DATA_WIDTH(DATA_WIDTH), .KERNEL_SIZE(KERNEL_SIZE), .OUT_CHANNELS(OUT_CHANNELS), .IN_CHANNELS(IN_CHANNELS) , .PE_NUM      (1)
    ) BRAM_W_1 ( .clk         (clk), .rst_n       (~rst), .start_stream(start_stream_1 && !fifo_full_fifo1), .fifo_full   (fifo_full_fifo1),
    .weight_valid(weight_valid_1), .weight_data (weight_data_1)
    
    );
    
    weights_fifo #( .KERNEL_SIZE(KERNEL_SIZE), .IN_CHANNELS(IN_CHANNELS), .OUT_CHANNELS     (OUT_CHANNELS), .DATA_WIDTH(DATA_WIDTH), 
    .FILTER_BUFFER_CNT (4)
    ) FIFO_W1 ( .clk(clk), .rst_n(~rst), .wr_valid(weight_valid_1_reg), .wr_ready(start_stream_1), .read_channel_idx(read_channel_idx_fifo1),
    .wr_data   (weight_data_1), .rd_valid  (rd_valid_1), .rd_ready  (rd_ready_1), .window_out(weights_window_out_1) , 
    .bnfifo_full     (bnfifo_full_1), .fifo_full(fifo_full_fifo1)
    );

//////////////////////////////////////////////////////////
    bram_weights #(
        .DATA_WIDTH(DATA_WIDTH), .KERNEL_SIZE(KERNEL_SIZE), .OUT_CHANNELS(OUT_CHANNELS_2), .IN_CHANNELS(IN_CHANNELS_2) , .PE_NUM      (2)
    ) BRAM_W_2 ( .clk         (clk), .rst_n       (~rst), .start_stream(start_stream_2 && !fifo_full_fifo2), .fifo_full   (fifo_full_fifo2),
     .weight_valid(weight_valid_2), .weight_data(weight_data_2)
    
    );

    weights_fifo #( .KERNEL_SIZE(KERNEL_SIZE), .IN_CHANNELS(IN_CHANNELS_2), .OUT_CHANNELS     (OUT_CHANNELS_2), .DATA_WIDTH(DATA_WIDTH),
    .FILTER_BUFFER_CNT (8)
    ) FIFO_W2 ( .clk(clk), .rst_n(~rst), .wr_valid(weight_valid_2_reg), .wr_ready(start_stream_2), .bnfifo_full     (bnfifo_full_2), 
    .fifo_full(fifo_full_fifo2), .read_channel_idx(read_channel_idx_fifo2),
    .wr_data   (weight_data_2), .rd_valid  (rd_valid_2), .rd_ready  (rd_ready_2), .window_out(weights_window_out_2)
    );

///////////////////////////////////////////////////////////////////////////////////////////////////
    bram_weights #(
        .DATA_WIDTH(DATA_WIDTH), .KERNEL_SIZE(KERNEL_SIZE), .OUT_CHANNELS(OUT_CHANNELS_3), .IN_CHANNELS(IN_CHANNELS_3) , .PE_NUM      (3)
    ) BRAM_W_3 ( .clk(clk), .rst_n(~rst), .start_stream(start_stream_3 && !fifo_full_fifo3), .fifo_full   (fifo_full_fifo3),
     .weight_valid(weight_valid_3), .weight_data (weight_data_3)
    
    );
    weights_fifo #( .KERNEL_SIZE(KERNEL_SIZE), .IN_CHANNELS(IN_CHANNELS_3), .OUT_CHANNELS     (OUT_CHANNELS_3), .DATA_WIDTH(DATA_WIDTH),
    .FILTER_BUFFER_CNT (8)
    ) FIFO_W3 ( .clk(clk), .rst_n(~rst), .wr_valid(weight_valid_3_reg), .wr_ready(start_stream_3), .bnfifo_full     (bnfifo_full_3), 
    .fifo_full       (fifo_full_fifo3), .read_channel_idx(read_channel_idx_fifo3),
    .wr_data(weight_data_3), .rd_valid(rd_valid_3), .rd_ready(rd_ready_3), .window_out(weights_window_out_3)
    );

/////////////////////////////////////////////////////////

    bram_weights #(
        .DATA_WIDTH(DATA_WIDTH), .KERNEL_SIZE(KERNEL_SIZE), .OUT_CHANNELS(OUT_CHANNELS_4), .IN_CHANNELS(IN_CHANNELS_4) , .PE_NUM      (4)
    ) BRAM_W_4 ( .clk         (clk), .rst_n       (~rst), .start_stream(start_stream_4 && !fifo_full_fifo4), .fifo_full   (fifo_full_fifo4),
     .weight_valid(weight_valid_4), .weight_data (weight_data_4)
    
    );

     weights_fifo #( .KERNEL_SIZE(KERNEL_SIZE), .IN_CHANNELS(IN_CHANNELS_4), .OUT_CHANNELS     (OUT_CHANNELS_4), .DATA_WIDTH(DATA_WIDTH),
    .FILTER_BUFFER_CNT (16)
    ) FIFO_W4 ( .clk       (clk), .rst_n     (~rst), .wr_valid  (weight_valid_4_reg), .wr_ready  (start_stream_4), 
    .bnfifo_full     (bnfifo_full_4), .fifo_full       (fifo_full_fifo4), .read_channel_idx(read_channel_idx_fifo4),
    .wr_data   (weight_data_4), .rd_valid  (rd_valid_4), .rd_ready  (rd_ready_4), .window_out(weights_window_out_4)
    );
//////////////////////////////////////////////////////////

    bram_weights #(
        .DATA_WIDTH     (DATA_WIDTH), .KERNEL_SIZE    (KERNEL_SIZE), .OUT_CHANNELS   (OUT_CHANNELS_5), .IN_CHANNELS    (IN_CHANNELS_5) , .PE_NUM(5)
    ) BRAM_W_5 ( .clk         (clk), .rst_n       (~rst), .start_stream(start_stream_5 && !fifo_full_fifo5), .fifo_full   (fifo_full_fifo5),
     .weight_valid(weight_valid_5), .weight_data (weight_data_5)
    
    );

     weights_fifo #( .KERNEL_SIZE(KERNEL_SIZE), .IN_CHANNELS(IN_CHANNELS_5), .OUT_CHANNELS     (OUT_CHANNELS_5), .DATA_WIDTH(DATA_WIDTH),
    .FILTER_BUFFER_CNT (8)
    ) FIFO_W5 ( .clk       (clk), .rst_n     (~rst), .wr_valid  (weight_valid_5_reg), .wr_ready  (start_stream_5), 
    .bnfifo_full     (bnfifo_full_5), .fifo_full       (fifo_full_fifo5), .read_channel_idx(read_channel_idx_fifo5),
    .wr_data   (weight_data_5), .rd_valid  (rd_valid_5), .rd_ready  (rd_ready_5), .window_out(weights_window_out_5)
    );
/////////////////////////////////////////////////////////

    bram_weights #(
        .DATA_WIDTH     (DATA_WIDTH), .KERNEL_SIZE    (KERNEL_SIZE), .OUT_CHANNELS   (OUT_CHANNELS_6), .IN_CHANNELS(IN_CHANNELS_6) , .PE_NUM(6)
    ) BRAM_W_6 ( .clk         (clk), .rst_n       (~rst), .start_stream(start_stream_6 && !fifo_full_fifo6), .fifo_full   (fifo_full_fifo6),
     .weight_valid(weight_valid_6), .weight_data (weight_data_6)
    
    );

     weights_fifo #( .KERNEL_SIZE(KERNEL_SIZE), .IN_CHANNELS(IN_CHANNELS_6), .OUT_CHANNELS     (OUT_CHANNELS_6), .DATA_WIDTH(DATA_WIDTH),
    .FILTER_BUFFER_CNT (6)
    ) FIFO_W6 ( .clk       (clk), .rst_n     (~rst), .wr_valid  (weight_valid_6_reg), .wr_ready  (start_stream_6),
     .bnfifo_full     (bnfifo_full_6), .fifo_full       (fifo_full_fifo6), .read_channel_idx(read_channel_idx_fifo6),
    .wr_data   (weight_data_6), .rd_valid  (rd_valid_6), .rd_ready  (rd_ready_6), .window_out(weights_window_out_6)
    );



    ////////////////////////////////////////////////////////////////////////////////////
    always_ff @(posedge clk ) begin : proc_pad_top_reg_pe6
        if(rst) begin
            pad_top_reg_pe6 <= 0;
        end else begin
            pad_top_reg_pe6 <= pad_top_pe6;
        end
    end


    //System_ControlUnit instantiation 
    System_ControlUnit #(.DATA_WIDTH(DATA_WIDTH), .IMAGE_WIDTH(IMAGE_WIDTH), .IMAGE_HEIGHT(IMAGE_HEIGHT), .NUM_IMAGES(NUM_IMAGES), .OUTPUT_SIZE (6),
     .KERNEL_SIZE (KERNEL_SIZE), .IN_CHANNELS(IN_CHANNELS), .IN_CHANNELS_2 (IN_CHANNELS_2), .IN_CHANNELS_3 (IN_CHANNELS_3), 
     .IN_CHANNELS_4 (IN_CHANNELS_4), .IN_CHANNELS_5 (IN_CHANNELS_5), .IN_CHANNELS_6 (IN_CHANNELS_6),
     .IMAGE_HEIGHT_2(IMAGE_HEIGHT_2), .IMAGE_HEIGHT_3(IMAGE_HEIGHT_3), .IMAGE_HEIGHT_4(IMAGE_HEIGHT_4), 
     .IMAGE_HEIGHT_5(IMAGE_HEIGHT_5), .IMAGE_HEIGHT_6(IMAGE_HEIGHT_6)
        ) Sys_CU (
                .maxpool_done1  (maxpool_done1), .maxpool_done2  (maxpool_done2), .maxpool_done3  (maxpool_done3), .maxpool_done4  (maxpool_done4), 
                .maxpool_done5  (maxpool_done5), .maxpool_done6  (maxpool_done6), .rst_n          (rst), .start_read(ready_signal_to_sys_CU1), 
                .bram_read_en   (bram_read_en), .pe2_enable     (pe2_enable), .clk(clk), 
                .pe3_enable     (pe3_enable), .pe4_enable     (pe4_enable), .pe5_enable     (pe5_enable), .pe6_enable     (pe6_enable), 
                .fifo_pe1_2_empty  (fifo_pe1_2_empty), .num_shifts_counter_pe2(num_shifts_counter_pe2), 
                .num_shifts_counter_pe3(num_shifts_counter_pe3), 
                .num_shifts_counter_pe4(num_shifts_counter_pe4), .num_shifts_counter_pe5(num_shifts_counter_pe5), 
                .fifo_pe2_3_empty      (fifo_pe2_3_empty), .fifo_pe3_4_empty      (fifo_pe3_4_empty), 
                .fifo_pe4_5_empty      (fifo_pe4_5_empty), .pad_bottom_pe6        (pad_bottom_pe6),
                .fifo_pe5_6_empty      (fifo_pe5_6_empty),
                .row_fill_index_out_pe6(row_fill_index_out_pe6), .done_mac_1(done_mac_1), .done_mac_2(done_mac_2), .done_mac_3(done_mac_3),
                .done_mac_4            (done_mac_4), .done_mac_5(done_mac_5), .done_mac_6(done_mac_6), 
                .start_mac_1(start_mac_1), .start_mac_2(start_mac_2), .start_mac_3(start_mac_3), 
                .fill_window_ready_to_mac_pe1(fill_window_ready_to_mac_pe1), .update_window_ready_to_mac_pe1(update_window_ready_to_mac_pe1), 
                .fill_window_ready_to_mac_pe2  (fill_window_ready_to_mac_pe2), 
                .fill_window_ready_to_mac_pe3  (fill_window_ready_to_mac_pe3), .fill_window_ready_to_mac_pe4  (fill_window_ready_to_mac_pe4), 
                .fill_window_ready_to_mac_pe5  (fill_window_ready_to_mac_pe5),
                .fill_window_ready_to_mac_pe6  (fill_window_ready_to_mac_pe6), .update_window_ready_to_mac_pe2(update_window_ready_to_mac_pe2), 
                .update_window_ready_to_mac_pe3(update_window_ready_to_mac_pe3), 
                .update_window_ready_to_mac_pe4(update_window_ready_to_mac_pe4), .update_window_ready_to_mac_pe5(update_window_ready_to_mac_pe5),
                .update_window_ready_to_mac_pe6(update_window_ready_to_mac_pe6), 
                .read_channel_idx_fifo2(read_channel_idx_fifo2), .read_channel_idx_fifo3(read_channel_idx_fifo3), 
                .read_channel_idx_fifo4(read_channel_idx_fifo4), .read_channel_idx_fifo5(read_channel_idx_fifo5), 
                .read_channel_idx_fifo6(read_channel_idx_fifo6), 
                .start_mac_4(start_mac_4), .start_mac_5(start_mac_5), .start_mac_6(start_mac_6), .rd_ready_1(rd_ready_1), .rd_ready_2(rd_ready_2), 
                .rd_ready_3(rd_ready_3), 
                .rd_ready_4(rd_ready_4), .rd_ready_5(rd_ready_5), .rd_ready_6(rd_ready_6) , .read_channel_idx_fifo1(read_channel_idx_fifo1), 
                .write_pixel_ready(write_pixel_ready), .bram_write_en(bram_write_en), 
                .bram_abs_read_addr(bram_abs_read_addr), .bram_abs_write_addr(bram_abs_write_addr), .bank_select(bank_select)
               

        ); 

    // Layer 1: in=4, out=64
    conv2d_top #(
        .IN_CHANNELS(IN_CHANNELS), .OUT_CHANNELS(OUT_CHANNELS), .KERNEL_SIZE(KERNEL_SIZE), .STRIDE(STRIDE), .PADDING(PADDING),
        .IMAGE_WIDTH(IMAGE_WIDTH), .DATA_WIDTH(DATA_WIDTH), .MAX_POOL_KERNEL(MAX_POOL_KERNEL), .FRAC_SZ(FRAC_SZ), 
        .PE_NUM(1), .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) pe1 (
        .clk(clk), .rst(rst), .pixel_in(bram_image_out), .kernel_weights(weights_window_out_1), .maxpool_done(maxpool_done1), 
        .num_shifts_counter(), 
        .ENABLE_PE(ENABLE_PE), .bram_en(ready_signal_to_sys_CU1), .num_shifts_flag   (num_shifts_flag_pe1), 
        .row_fill_index_out(row_fill_index_out_pe1),
        .output_feature_map(stage_out[0]), .line_buffer_en_top(line_buffer_en_top1), .weights_rd_valid(rd_valid_1), 
        .fill_window_ready_to_mac(fill_window_ready_to_mac_pe1), .update_window_ready_to_mac(update_window_ready_to_mac_pe1),
        .pad_top(pad_top_pe1), .pad_bottom(pad_bottom_pe1), .start_mac(start_mac_1), .bn_fifo_full_to_cu        (bnfifo_full_1), 
        .done_mac(done_mac_1) 
    );


    buffer #(
       .IMAGE_WIDTH(IMAGE_WIDTH_2*OUT_CHANNELS*2),
       .DATA_WIDTH(DATA_WIDTH)
    ) fifo_pe1_2 (
       .clk(clk),
       .rst_n(~rst),
       .wr_en(maxpool_done1),
       .din(stage_out[0]),
       .rd_en(line_buffer_en_top2 && !pad_top_pe2 && row_fill_index_out_pe2 !=0 && !pad_bottom_pe2),
       .dout(reg_out_1),
       .full(),
       .empty(fifo_pe1_2_empty)
    );


    // Layer 2: in=64, out=128
    conv2d_top #(.IN_CHANNELS(IN_CHANNELS_2), .OUT_CHANNELS(OUT_CHANNELS_2), .KERNEL_SIZE(KERNEL_SIZE), .STRIDE(STRIDE),
        .PADDING(PADDING), .IMAGE_WIDTH(IMAGE_WIDTH_2), .DATA_WIDTH(DATA_WIDTH), .MAX_POOL_KERNEL(MAX_POOL_KERNEL), .FRAC_SZ(FRAC_SZ), 
        .PE_NUM(2), .IMAGE_HEIGHT(IMAGE_HEIGHT_2)
        ) pe2 (
        .clk(clk), .rst(rst),
        .pixel_in(reg_out_1), .kernel_weights(weights_window_out_2), .maxpool_done(maxpool_done2), .ENABLE_PE(pe2_enable), 
        .num_shifts_counter(num_shifts_counter_pe2), .fill_window_ready_to_mac  (fill_window_ready_to_mac_pe2), .update_window_ready_to_mac(update_window_ready_to_mac_pe2),
        .bram_en(), .num_shifts_flag   (), .row_fill_index_out(row_fill_index_out_pe2),
        .output_feature_map(stage_out[1]) ,  .line_buffer_en_top(line_buffer_en_top2), .weights_rd_valid  (rd_valid_2), 
        .pad_top(pad_top_pe2), .pad_bottom(pad_bottom_pe2), .done_mac(done_mac_2), .bn_fifo_full_to_cu        (bnfifo_full_2), .start_mac(start_mac_2)
    );

    buffer #(
       .IMAGE_WIDTH(IMAGE_WIDTH_3*OUT_CHANNELS_2*2),
       .DATA_WIDTH(DATA_WIDTH)
    ) fifo_pe2_3 (
       .clk(clk),
       .rst_n(~rst),
       .wr_en(maxpool_done2),
       .din(stage_out[1]),
       .rd_en(line_buffer_en_top3 && !pad_top_pe3 && row_fill_index_out_pe3!=0 && !pad_bottom_pe3),
       .dout(reg_out_2),
       .full(),
       .empty(fifo_pe2_3_empty)
    );

    // Layer 3: in=128, out=256
    conv2d_top #(.IN_CHANNELS(IN_CHANNELS_3), .OUT_CHANNELS(OUT_CHANNELS_3), .KERNEL_SIZE(KERNEL_SIZE), .STRIDE(STRIDE),
        .PADDING(PADDING), .IMAGE_WIDTH(IMAGE_WIDTH_3), .DATA_WIDTH(DATA_WIDTH), .MAX_POOL_KERNEL(MAX_POOL_KERNEL), .FRAC_SZ(FRAC_SZ), 
        .PE_NUM(3), .IMAGE_HEIGHT(IMAGE_HEIGHT_3)
        ) pe3 (
        .clk(clk), .rst(rst),
        .pixel_in(reg_out_2), .kernel_weights(weights_window_out_3), .maxpool_done(maxpool_done3), .ENABLE_PE(pe3_enable),
        .bram_en(), .num_shifts_flag   (), .row_fill_index_out(row_fill_index_out_pe3), 
        .num_shifts_counter(num_shifts_counter_pe3), .fill_window_ready_to_mac  (fill_window_ready_to_mac_pe3), .update_window_ready_to_mac(update_window_ready_to_mac_pe3),
        .output_feature_map(stage_out[2]),  .line_buffer_en_top(line_buffer_en_top3), .pad_top(pad_top_pe3), .weights_rd_valid  (rd_valid_3), 
        .pad_bottom(pad_bottom_pe3), .start_mac(start_mac_3), .bn_fifo_full_to_cu        (bnfifo_full_3), .done_mac(done_mac_3)
    ); 

    buffer #(
       .IMAGE_WIDTH(IMAGE_WIDTH_4*OUT_CHANNELS_3*2),
       .DATA_WIDTH(DATA_WIDTH)
    ) fifo_pe3_4 (
       .clk(clk),
       .rst_n(~rst),
       .wr_en(maxpool_done3),
       .din(stage_out[2]),
       .rd_en(line_buffer_en_top4 && !pad_top_pe4 && row_fill_index_out_pe4!=0 && !pad_bottom_pe4),
       .dout(reg_out_3),
       .full(),
       .empty(fifo_pe3_4_empty)
    );

    // Layer 4: in=256, out=512
    conv2d_top #(.IN_CHANNELS(IN_CHANNELS_4), .OUT_CHANNELS(OUT_CHANNELS_4), .KERNEL_SIZE(KERNEL_SIZE), .STRIDE(STRIDE),
        .PADDING(PADDING), .IMAGE_WIDTH(IMAGE_WIDTH_4), .DATA_WIDTH(DATA_WIDTH), .MAX_POOL_KERNEL(MAX_POOL_KERNEL), .FRAC_SZ(FRAC_SZ), 
        .PE_NUM(4), .IMAGE_HEIGHT(IMAGE_HEIGHT_4)
        ) pe4 (
        .clk(clk), .rst(rst),
        .pixel_in(reg_out_3), .kernel_weights(weights_window_out_4), .maxpool_done(maxpool_done4), .ENABLE_PE(pe4_enable),
        .bram_en(), .num_shifts_flag   (), .row_fill_index_out(row_fill_index_out_pe4), 
        .num_shifts_counter(num_shifts_counter_pe4), .fill_window_ready_to_mac  (fill_window_ready_to_mac_pe4), .update_window_ready_to_mac(update_window_ready_to_mac_pe4),
        .output_feature_map(stage_out[3]), .line_buffer_en_top(line_buffer_en_top4), .weights_rd_valid  (rd_valid_4), 
        .pad_top(pad_top_pe4), .pad_bottom(pad_bottom_pe4) , .start_mac(start_mac_4), .bn_fifo_full_to_cu        (bnfifo_full_4), .done_mac(done_mac_4)
    ); 

    buffer #(
       .IMAGE_WIDTH(IMAGE_WIDTH_5*OUT_CHANNELS_4*2),
       .DATA_WIDTH(DATA_WIDTH)
    ) fifo_pe4_5 (
       .clk(clk),
       .rst_n(~rst),
       .wr_en(maxpool_done4),
       .din(stage_out[3]),
       .rd_en(line_buffer_en_top5 && !pad_top_pe5 && row_fill_index_out_pe5!=0 && !pad_bottom_pe5),
       .dout(reg_out_4),
       .full(),
       .empty(fifo_pe4_5_empty)
    );

    // Layer 5: in=512, out=1024
    conv2d_top #(.IN_CHANNELS(IN_CHANNELS_5), .OUT_CHANNELS(OUT_CHANNELS_5), .KERNEL_SIZE(KERNEL_SIZE), .STRIDE(STRIDE),
        .PADDING(PADDING), .IMAGE_WIDTH(IMAGE_WIDTH_5), .DATA_WIDTH(DATA_WIDTH), .MAX_POOL_KERNEL(MAX_POOL_KERNEL), .FRAC_SZ(FRAC_SZ), 
        .PE_NUM(5), .IMAGE_HEIGHT(IMAGE_HEIGHT_5)
        ) pe5 (
        .clk(clk), .rst(rst),  .ENABLE_PE(pe5_enable),
        .pixel_in(reg_out_4), .kernel_weights(weights_window_out_5), .maxpool_done(maxpool_done5), .fill_window_ready_to_mac  (fill_window_ready_to_mac_pe5), .update_window_ready_to_mac(update_window_ready_to_mac_pe5),
        .bram_en(), .num_shifts_flag   (), .row_fill_index_out(row_fill_index_out_pe5), .num_shifts_counter(num_shifts_counter_pe5),
        .output_feature_map(stage_out[4]),  .line_buffer_en_top(line_buffer_en_top5), .weights_rd_valid  (rd_valid_5), 
        .pad_top(pad_top_pe5), .pad_bottom(pad_bottom_pe5), .start_mac(start_mac_5), .bn_fifo_full_to_cu        (bnfifo_full_5), .done_mac(done_mac_5)
    ); 

    buffer #(
       .IMAGE_WIDTH(IMAGE_WIDTH_6*OUT_CHANNELS_5*2),
       .DATA_WIDTH(DATA_WIDTH)
    ) fifo_pe5_6 (
       .clk(clk),
       .rst_n(~rst),
       .wr_en(maxpool_done5),
       .din(stage_out[4]),
       .rd_en(line_buffer_en_top6 && !pad_top_reg_pe6 && !pad_bottom_pe6 && row_fill_index_out_pe6!=0 ),
       .dout(reg_out_5),
       .full(),
       .empty(fifo_pe5_6_empty)
    );

    // Layer 6: in=1024, out=6
    conv2d_top #(.IN_CHANNELS(IN_CHANNELS_6), .OUT_CHANNELS(OUT_CHANNELS_6), .KERNEL_SIZE(KERNEL_SIZE), .STRIDE(STRIDE),
        .PADDING(PADDING), .IMAGE_WIDTH(IMAGE_WIDTH_6), .DATA_WIDTH(DATA_WIDTH), .MAX_POOL_KERNEL(MAX_POOL_KERNEL), .FRAC_SZ(FRAC_SZ), 
        .PE_NUM(6), .IMAGE_HEIGHT(IMAGE_HEIGHT_6)
        ) pe6 (
        .clk(clk), .rst(rst),
        .pixel_in(reg_out_5), .kernel_weights(weights_window_out_6), .maxpool_done(maxpool_done6), .ENABLE_PE(pe6_enable),
        .bram_en(), .num_shifts_flag   (), .row_fill_index_out(row_fill_index_out_pe6), 
        .num_shifts_counter(), .fill_window_ready_to_mac  (fill_window_ready_to_mac_pe6), .update_window_ready_to_mac(update_window_ready_to_mac_pe6),
        .output_feature_map(stage_out[5]), .line_buffer_en_top(line_buffer_en_top6), .weights_rd_valid  (rd_valid_6), 
        .pad_top(pad_top_pe6), .pad_bottom(pad_bottom_pe6) , .start_mac(start_mac_6), .bn_fifo_full_to_cu        (bnfifo_full_6), .done_mac(done_mac_6) 
    ); 

    // Final output
    assign output_feature_map = stage_out[5];

endmodule

