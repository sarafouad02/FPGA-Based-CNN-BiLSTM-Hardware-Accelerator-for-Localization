`timescale 1ns/1ps

module cordic_div_tb;
    // Parameters
    parameter WIDTH   = 16;
    parameter FRAC_SZ = 12;

    // Inputs to DUT
    reg clk;
    reg reset;
    reg start;
    reg signed [WIDTH-1:0] numerator;
    reg signed [WIDTH-1:0] denominator;

    // Outputs from DUT
    wire signed [WIDTH-1:0] quotient;
    wire done;

    // Instantiate the DUT
    cordic_div #(
        .WIDTH(WIDTH),
        .FRAC_SZ(FRAC_SZ)
    ) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .numerator(numerator),
        .denominator(denominator),
        .quotient(quotient),
        .done(done)
    );

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Task to drive a single division operation
    task do_divide;
        input signed [WIDTH-1:0] num;
        input signed [WIDTH-1:0] den;
        begin
            @(negedge clk);
            numerator   = num;
            denominator = den;
            start       = 1;
            @(negedge clk);
            start       = 0;
            // Wait for done
            wait (done == 1);
            @(negedge clk);
            $display("DIV %0d / %0d -> Q=%0d (fixed Q4.12 format)", num, den, quotient);
        end
    endtask

    // Stimulus
    initial begin
        // Initialize signals
        reset       = 1;
        start       = 0;
        numerator   = 0;
        denominator = 1;

        // Deassert reset after a couple cycles
        #20;
        reset = 0;

        // Testcases
        do_divide(16'sd4096, 16'sd2048);   // 1.0 / 0.5 = 2.0
        do_divide(16'sd2048, 16'sd4096);   // 0.5 / 1.0 = 0.5
        do_divide(-16'sd4096, 16'sd2048);  // -1.0 / 0.5 = -2.0
        do_divide(16'sd6144, 16'sd2048);   // 1.5 / 0.5 = 3.0
        do_divide(16'sd0,     16'sd2048);   // 0.0 / 0.5 = 0.0
        do_divide(16'sd4096,  16'sd0);      // divide by zero case

        // // Random tests
        // repeat (5) begin
        //     reg signed [WIDTH-1:0] rnum, rden;
        //     rnum = $random;
        //     rden = $random;
        //     if (rden == 0) rden = 1;
        //     do_divide(rnum, rden);
        // end

        $display("Testbench completed.");
        $stop;
    end

endmodule
