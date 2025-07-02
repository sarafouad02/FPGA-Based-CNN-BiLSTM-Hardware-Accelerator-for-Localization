`timescale 1ns/1ps

module maxpool2x2_tb;
    parameter DATA_WIDTH = 16;
    parameter OUT_CHANNELS = 8;

    reg clk;
    reg rst;
    reg valid_in;
    logic signed [DATA_WIDTH-1:0] pixel_00 [OUT_CHANNELS]; // Top-left pixel
    logic signed [DATA_WIDTH-1:0] pixel_01 [OUT_CHANNELS]; // Top-right pixel
    logic signed [DATA_WIDTH-1:0] pixel_10 [OUT_CHANNELS]; // Bottom-left pixel
    logic signed [DATA_WIDTH-1:0] pixel_11 [OUT_CHANNELS]; // Bottom-right pixel
    logic signed [DATA_WIDTH-1:0] pooled_pixel [OUT_CHANNELS]; // Max-pooled output
    wire valid_out;

    logic signed [DATA_WIDTH-1:0] expected_pooled_pixel [OUT_CHANNELS];

    // Test cases
        logic signed [DATA_WIDTH-1:0] test_case_1 [OUT_CHANNELS];
        logic signed [DATA_WIDTH-1:0] test_case_2 [OUT_CHANNELS];
        logic signed [DATA_WIDTH-1:0] test_case_3 [OUT_CHANNELS];
        logic signed [DATA_WIDTH-1:0] test_case_4 [OUT_CHANNELS];

    // Instantiate the maxpool2x2 module
    maxpool_2x2 #(.DATA_WIDTH(DATA_WIDTH), .OUT_CHANNELS(OUT_CHANNELS)) uut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .pixel_00(pixel_00),
        .pixel_01(pixel_01),
        .pixel_10(pixel_10),
        .pixel_11(pixel_11),
        .pooled_pixel(pooled_pixel),
        .valid_out(valid_out)
    );

    // Clock generation
    always #5 clk = ~clk; // 10ns period

    task apply_test_case(input logic signed [DATA_WIDTH-1:0] p00[], p01[], p10[], p11[]);
        valid_in = 1;
        for (int i = 0; i < OUT_CHANNELS; i++) begin
            pixel_00[i] = p00[i];
            pixel_01[i] = p01[i];
            pixel_10[i] = p10[i];
            pixel_11[i] = p11[i];

            // Compute expected max value per channel
            expected_pooled_pixel[i] = max(p00[i], p01[i], p10[i], p11[i]);
        end
        #10; // Wait for one clock cycle
        valid_in = 0;
    endtask

    function logic signed [DATA_WIDTH-1:0] max(logic signed [DATA_WIDTH-1:0] a, b, c, d);
        return (a > b ? a : b) > (c > d ? c : d) ? (a > b ? a : b) : (c > d ? c : d);
    endfunction

    // Self-checking process
    task check_output();
        if (1) begin
            for (int i = 0; i < OUT_CHANNELS; i++) begin
                if (pooled_pixel[i] !== expected_pooled_pixel[i]) begin
                    $display("ERROR: Mismatch at channel %0d | Expected: %0d, Got: %0d", 
                             i, expected_pooled_pixel[i], pooled_pixel[i]);
                end else begin
                    $display("PASS: Channel %0d | Output: %0d (Matches Expected)", 
                             i, pooled_pixel[i]);
                end
            end
        end
    endtask

    initial begin
        // Initialize signals
        clk = 0;
        rst = 1;
        valid_in = 0;
        
        for (int i = 0; i < OUT_CHANNELS; i++) begin
            pixel_00[i] = 0;
            pixel_01[i] = 0;
            pixel_10[i] = 0;
            pixel_11[i] = 0;
        end
        
        // Apply reset
        #20 rst = 0;

        // Test cases
        test_case_1 = '{10, 20, 500, 15, 3, 7, 25, 30};
        test_case_2 = '{-8, 3, 12, 7, -5, 0, 6, 4};
        test_case_3 = '{100, 200, 150, 250, 50, 175, 225, 90};
        test_case_4 = '{-30, -25, -40, -35, -10, -15, -20, -5};

        // Apply test cases and check results
        apply_test_case(test_case_1, test_case_2, test_case_3, test_case_4); #10 check_output();
        // apply_test_case(test_case_2, test_case_2, test_case_2, test_case_2); #10 check_output();
        // apply_test_case(test_case_3, test_case_3, test_case_3, test_case_3); #10 check_output();
        // apply_test_case(test_case_4, test_case_4, test_case_4, test_case_4); #10 check_output();

        // Deassert valid_in
        #10 valid_in = 0;

        // Wait some cycles and finish
        #20;
        $stop;
    end

    // Monitor output
    // initial begin
    //     $monitor("Time=%0t | valid_in=%b | valid_out=%b | Max Value=%p", 
    //              $time, valid_in, valid_out, pooled_pixel);
    // end

endmodule
