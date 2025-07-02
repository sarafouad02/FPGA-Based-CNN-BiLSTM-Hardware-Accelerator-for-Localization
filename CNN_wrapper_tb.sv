`timescale 1ns / 1ps

module CNN_wrapper_tb;

    // Parameters
    parameter DATA_WIDTH = 16;
    parameter CLK_PERIOD = 10;
    
    // Clock and reset
    reg clk;
    reg rst_n;
    
    // CONV interface
    reg ENABLE_PE;
    reg [DATA_WIDTH-1:0] bram_image_in;
    reg write_pixel_ready;
    wire bram_en;
    wire [$clog2(4)-1:0] current_channel_out;
    wire num_shifts_flag_pe1;
    
    // FC interface
    reg fc_network_enable;
    reg fc_output_ready;
    reg fc_l1_activation_enable;
    reg fc_l2_activation_enable;
    reg fc_l3_activation_enable;
    reg fc_pipeline_reset;
    wire fc_pipeline_busy;
    wire fc_pipeline_stalled;
    wire fc_pipeline_ready;
    wire fc_l1_busy;
    wire fc_l2_busy;
    wire fc_l3_busy;
    wire [DATA_WIDTH-1:0] fc_output_data;
    wire fc_output_valid;
    
    // Counters
    integer input_count;
    integer output_count;
    
    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // DUT instantiation
    CNN_wrapper #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ENABLE_PE(ENABLE_PE),
        .bram_image_in(bram_image_in),
        .write_pixel_ready(write_pixel_ready),
        .bram_en(bram_en),
        .current_channel_out(current_channel_out),
        .num_shifts_flag_pe1(num_shifts_flag_pe1),
        .fc_network_enable(fc_network_enable),
        .fc_output_ready(fc_output_ready),
        .fc_l1_activation_enable(fc_l1_activation_enable),
        .fc_l2_activation_enable(fc_l2_activation_enable),
        .fc_l3_activation_enable(fc_l3_activation_enable),
        .fc_pipeline_reset(fc_pipeline_reset),
        .fc_pipeline_busy(fc_pipeline_busy),
        .fc_pipeline_stalled(fc_pipeline_stalled),
        .fc_pipeline_ready(fc_pipeline_ready),
        .fc_l1_busy(fc_l1_busy),
        .fc_l2_busy(fc_l2_busy),
        .fc_l3_busy(fc_l3_busy),
        .fc_output_data(fc_output_data),
        .fc_output_valid(fc_output_valid)
    );
    
    // Test stimulus
    initial begin
        // Initialize
        clk = 0;
        rst_n = 0;
        ENABLE_PE = 0;
        bram_image_in = 0;
        write_pixel_ready = 0;
        fc_network_enable = 0;
        fc_output_ready = 1;
        fc_l1_activation_enable = 1;
        fc_l2_activation_enable = 1;
        fc_l3_activation_enable = 0;
        fc_pipeline_reset = 0;
        input_count = 0;
        output_count = 0;
        
        $display("Starting CNN Wrapper Test");
        
        // Reset
        #100;
        rst_n = 1;
        #50;
        
        // Start processing
        ENABLE_PE = 1;
        fc_network_enable = 1;
        
        $display("CNN processing started at time %0t", $time);
        
        // Feed some test data
        fork
            begin
                // Input data generator
                repeat(1000) begin
                    @(posedge clk);
                    bram_image_in = $random & 16'hFFFF;
                    write_pixel_ready = 1;
                    input_count = input_count + 1;
                    @(posedge clk);
                    write_pixel_ready = 0;
                    repeat($urandom_range(0,3)) @(posedge clk);
                end
                $display("Input feeding completed. Total inputs: %0d", input_count);
            end
            
            begin
                // Output monitor
                while(output_count < 5) begin
                    @(posedge clk);
                    if(fc_output_valid) begin
                        output_count = output_count + 1;
                        $display("Output %0d: 0x%04h at time %0t", output_count, fc_output_data, $time);
                    end
                end
                $display("Got %0d outputs, finishing test", output_count);
                #1000;
                $finish;
            end
        join_any
        
        disable fork;
        $finish;
    end
    
    // Status monitoring
    always @(posedge clk) begin
        if(fc_output_valid) begin
            $display("FC Output: 0x%04h (signed: %0d) at time %0t", 
                    fc_output_data, $signed(fc_output_data), $time);
        end
    end
    
    // Periodic status
    integer cycle_count = 0;
    always @(posedge clk) begin
        if(rst_n) begin
            cycle_count = cycle_count + 1;
            if(cycle_count % 10000 == 0) begin
                $display("Cycle %0d: Inputs=%0d, Outputs=%0d, FC_busy=%b", 
                        cycle_count, input_count, output_count, fc_pipeline_busy);
            end
        end
    end

endmodule


/*`timescale 1ns / 1ps

module CNN_wrapper_tb;

    // Parameters matching the CNN_wrapper
    parameter DATA_WIDTH = 16;
    parameter CLK_PERIOD = 10; // 100MHz clock
    
    // Testbench signals
    reg clk;
    reg rst_n;
    
    // CONV layers interface
    reg ENABLE_PE;
    reg [DATA_WIDTH-1:0] bram_image_in;
    reg write_pixel_ready;
    wire bram_en;
    wire [$clog2(4)-1:0] current_channel_out;
    wire num_shifts_flag_pe1;
    
    // FC layers interface
    reg fc_network_enable;
    reg fc_output_ready;
    reg fc_l1_activation_enable;
    reg fc_l2_activation_enable;
    reg fc_l3_activation_enable;
    reg fc_pipeline_reset;
    wire fc_pipeline_busy;
    wire fc_pipeline_stalled;
    wire fc_pipeline_ready;
    wire fc_l1_busy;
    wire fc_l2_busy;
    wire fc_l3_busy;
    wire [DATA_WIDTH-1:0] fc_output_data;
    wire fc_output_valid;
    
    // Test control variables
    integer pixel_count = 0;
    integer cycle_count = 0;
    integer conv_output_count = 0;
    integer fc_output_count = 0;
    
    // Image parameters (from wrapper)
    parameter IMAGE_WIDTH = 188;
    parameter IMAGE_HEIGHT = 120;
    parameter IN_CHANNELS = 4;
    parameter TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT * IN_CHANNELS;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // DUT instantiation
    CNN_wrapper #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        // CONV interface
        .ENABLE_PE(ENABLE_PE),
        .bram_image_in(bram_image_in),
        .write_pixel_ready(write_pixel_ready),
        .bram_en(bram_en),
        .current_channel_out(current_channel_out),
        .num_shifts_flag_pe1(num_shifts_flag_pe1),
        
        // FC interface
        .fc_network_enable(fc_network_enable),
        .fc_output_ready(fc_output_ready),
        .fc_l1_activation_enable(fc_l1_activation_enable),
        .fc_l2_activation_enable(fc_l2_activation_enable),
        .fc_l3_activation_enable(fc_l3_activation_enable),
        .fc_pipeline_reset(fc_pipeline_reset),
        .fc_pipeline_busy(fc_pipeline_busy),
        .fc_pipeline_stalled(fc_pipeline_stalled),
        .fc_pipeline_ready(fc_pipeline_ready),
        .fc_l1_busy(fc_l1_busy),
        .fc_l2_busy(fc_l2_busy),
        .fc_l3_busy(fc_l3_busy),
        .fc_output_data(fc_output_data),
        .fc_output_valid(fc_output_valid)
    );
    
    // Main test sequence
    initial begin
        $display("=== CNN Wrapper Testbench Started ===");
        $display("Time: %0t", $time);
        
        // Initialize signals
        initialize_signals();
        
        // Reset sequence
        reset_dut();
        
        // Phase 1: Feed input image data through conv layers
        $display("\n=== Phase 1: Convolutional Processing ===");
        feed_image_data();
        
        // Wait for conv processing to complete
        wait_conv_completion();
        
        // Phase 2: Enable FC network processing
        $display("\n=== Phase 2: Fully Connected Processing ===");
        enable_fc_processing();
        
        // Wait for FC processing and collect outputs
        wait_fc_completion();
        
        // End simulation
        $display("\n=== Test Completed ===");
        $display("Total cycles: %0d", cycle_count);
        $display("Conv outputs generated: %0d", conv_output_count);
        $display("FC outputs generated: %0d", fc_output_count);
        
        #1000;
        $finish;
    end
    
    // Initialize all signals
    task initialize_signals;
        begin
            rst_n = 1;
            ENABLE_PE = 0;
            bram_image_in = 0;
            write_pixel_ready = 0;
            fc_network_enable = 0;
            fc_output_ready = 1; // Ready to accept outputs
            fc_l1_activation_enable = 1; // Enable activations
            fc_l2_activation_enable = 1;
            fc_l3_activation_enable = 0; // Typically disabled for output layer
            fc_pipeline_reset = 0;
        end
    endtask
    
    // Reset DUT
    task reset_dut;
        begin
            $display("Resetting DUT...");
            rst_n = 0;
            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);
            $display("Reset completed at time %0t", $time);
        end
    endtask
    
    // Feed image data to conv layers
    task feed_image_data;
        begin
            $display("Starting image data input...");
            ENABLE_PE = 1;
            
            // Feed sample image data
            for (pixel_count = 0; pixel_count < TOTAL_PIXELS; pixel_count = pixel_count + 1) begin
                @(posedge clk);
                
                // Generate sample data (you can modify this pattern)
                bram_image_in = (pixel_count % 256) + ((pixel_count/256) << 8);
                write_pixel_ready = 1;
                
                // Display progress every 1000 pixels
                if (pixel_count % 1000 == 0) begin
                    $display("Fed %0d pixels, current data: 0x%04h", pixel_count, bram_image_in);
                end
                
                @(negedge clk);
                write_pixel_ready = 0;
            end
            
            $display("Completed feeding %0d pixels", pixel_count);
        end
    endtask
    
    // Wait for conv processing to show some outputs
    task wait_conv_completion;
        integer wait_cycles;
        begin
            wait_cycles = 0;
            $display("Waiting for conv layer processing...");
            
            // Wait for some conv outputs or timeout
            while (wait_cycles < 10000 && conv_output_count < 100) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                
                if (wait_cycles % 1000 == 0) begin
                    $display("Waiting... cycles: %0d, conv outputs: %0d", wait_cycles, conv_output_count);
                end
            end
            
            $display("Conv processing wait completed. Outputs seen: %0d", conv_output_count);
        end
    endtask
    
    // Enable FC network processing
    task enable_fc_processing;
        begin
            $display("Enabling FC network...");
            fc_network_enable = 1;
            fc_pipeline_reset = 0;
            
            @(posedge clk);
            $display("FC network enabled at time %0t", $time);
        end
    endtask
    
    // Wait for FC processing completion
    task wait_fc_completion;
        integer wait_cycles;
        integer expected_outputs;
        begin
            wait_cycles = 0;
            expected_outputs = 3; // L3_OUTPUT_SIZE = 3
            $display("Waiting for FC processing completion...");
            
            while (wait_cycles < 50000 && fc_output_count < expected_outputs) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                
                if (wait_cycles % 5000 == 0) begin
                    $display("FC wait... cycles: %0d, outputs: %0d/%0d", 
                           wait_cycles, fc_output_count, expected_outputs);
                    $display("FC status - busy: %b, ready: %b, stalled: %b", 
                           fc_pipeline_busy, fc_pipeline_ready, fc_pipeline_stalled);
                end
            end
            
            $display("FC processing completed. Final outputs: %0d", fc_output_count);
        end
    endtask
    
    // Monitor conv layer internal connection
    always @(posedge clk) begin
        // Monitor the internal conv_output and conv_valid signals
        // Note: These are internal to the wrapper, so this assumes they're accessible
        if (dut.conv_valid) begin
            conv_output_count = conv_output_count + 1;
            if (conv_output_count <= 10 || conv_output_count % 100 == 0) begin
                $display("[CONV] Output %0d: 0x%04h at time %0t", 
                       conv_output_count, dut.conv_output, $time);
            end
        end
    end
    
    // Monitor FC outputs
    always @(posedge clk) begin
        if (fc_output_valid) begin
            fc_output_count = fc_output_count + 1;
            $display("[FC] Output %0d: 0x%04h (decimal: %0d) at time %0t", 
                   fc_output_count, fc_output_data, $signed(fc_output_data), $time);
        end
    end
    
    // Monitor FC layer status changes
    always @(posedge clk) begin
        if (fc_l1_busy || fc_l2_busy || fc_l3_busy) begin
            if (cycle_count % 1000 == 0) begin // Report every 1000 cycles when busy
                $display("[FC_STATUS] L1:%b L2:%b L3:%b Pipeline:%b at cycle %0d", 
                       fc_l1_busy, fc_l2_busy, fc_l3_busy, fc_pipeline_busy, cycle_count);
            end
        end
    end
    
    // Cycle counter
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
        end
    end
    
    // Timeout watchdog
    initial begin
        #500000000; // 500ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule*/