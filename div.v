module cordic_div #(
    parameter WIDTH = 16,   // Fixed-point precision (Q4.12 format)
    parameter FRAC_SZ = 12  // Fractional part size
)(
    input wire clk,
    input wire reset,
    input wire start,  // Signal to start division
    input wire signed [WIDTH-1:0] numerator,   
    input wire signed [WIDTH-1:0] denominator, 
    output reg signed [WIDTH-1:0] quotient,    
    output reg done // Indicates division completion
);

    reg signed [2*WIDTH-1:0] num;  // Extended numerator
    reg signed [WIDTH-1:0] denom;
    reg signed [WIDTH:0] remainder;  // One extra bit for precision
    reg [5:0] count;  // Loop counter (max WIDTH+FRAC_SZ iterations)
    reg [2:0] state;  // One-hot encoding
    wire sign; // Store the sign of the result
    wire signed [WIDTH-1:0] rounded_quotient; // Temporary signal for rounding

    assign sign = numerator[WIDTH-1] ^ denominator[WIDTH-1]; // XOR for sign

    // State encoding
    localparam IDLE   = 3'b001;
    localparam DIVIDE = 3'b010;
    localparam DONE   = 3'b100;

    assign rounded_quotient = (remainder > (1 <<< FRAC_SZ)) ? quotient + 1 : quotient; // Rounding logic

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            quotient <= 0;
            num <= 0;
            denom <= 0;
            remainder <= 0;
            count<=0;
            done <= 0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start && denominator != 0) begin
                        num <= (numerator[WIDTH-1] ? -numerator : numerator) <<< FRAC_SZ; // Absolute value of numerator and scale
                        denom <= (denominator[WIDTH-1] ? -denominator : denominator); // Absolute value of denominator
                        remainder <= 0;
                        quotient <= 0;
                        count <= WIDTH << 1;
                        state <= DIVIDE;
                    end else if (denominator == 0) begin
                        quotient <= 0; // Handle divide-by-zero
                        state <= IDLE;
                    end else state <= IDLE;
                end

                DIVIDE: begin
                    if (count > 0) begin
                        remainder <= {remainder[WIDTH-1:0], num[2*WIDTH-1]}; // left Shift numerator into remainder
                        num <= num << 1;

                        if (remainder >= denom) begin
                            remainder <= remainder - denom;
                            quotient <= quotient + 1;
                        end else begin
                            quotient <= quotient << 1;
                            count <= count - 1;
                        end
                        
                    end else begin
                        quotient <= sign ? -rounded_quotient : rounded_quotient; // Restore sign
                        done <= 1;
                        state <= DONE;
                    end
                end

                DONE: begin
                    if (!start) state <= IDLE; // Wait for reset signal
                end
            endcase
        end
    end

endmodule
// module Div #(
//   parameter DATA_WIDTH = 16,
//   parameter FRAC_SZ    = 12,
//   parameter STEP       = 4
// )(
//   input                        clk,
//   input                        reset,     // active-high
//   input                        start,     // one-cycle pulse
//   input  signed [DATA_WIDTH-1:0] dividend, // Q4.12, signed
//   input  signed [DATA_WIDTH-1:0] divisor,  // Q4.12, signed
//   output reg signed [DATA_WIDTH-1:0] quotient,  // Q4.12, signed
//   output reg signed [DATA_WIDTH-1:0] remainder, // same sign as dividend
//   output reg                   done
// );

//   // Extend width for fractional bits
//   localparam ACC_W  = DATA_WIDTH + FRAC_SZ;
//   localparam CYCLES = ACC_W / STEP;

//   // FSM states
//   localparam IDLE    = 1'b0,
//              EXECUTE = 1'b1;
//   reg state;

//   // Sign flags
//   reg sign_dividend, sign_divisor, sign_q;

//   // Magnitude inputs
//   reg [DATA_WIDTH-1:0] mag_dividend, mag_divisor;

//   // Extended magnitude accumulators
//   reg [ACC_W-1:0] partial_q;
//   reg [ACC_W-1:0] partial_r;
//   reg [$clog2(CYCLES+1)-1:0] cycle_cnt;

//   // Temporaries for inner loop
//   integer i;
//   reg [ACC_W-1:0] tmp_q, tmp_r;
//   reg [DATA_WIDTH-1:0] raw_q;
//   reg [DATA_WIDTH-1:0] raw_r;

//   always @(posedge clk or posedge reset) begin
//     if (reset) begin
//       quotient       <= 0;
//       remainder      <= 0;
//       partial_q      <= 0;
//       partial_r      <= 0;
//       cycle_cnt      <= 0;
//       done           <= 1'b0;
//       state          <= IDLE;
//     end else begin
//       case (state)
//         IDLE: begin
//           done <= 1'b0;
//           if (start) begin
//             // Grab signs and magnitudes
//             sign_dividend  <= dividend[DATA_WIDTH-1];
//             sign_divisor   <= divisor[DATA_WIDTH-1];
//             sign_q         <= dividend[DATA_WIDTH-1] ^ divisor[DATA_WIDTH-1];
//             mag_dividend   <= dividend[DATA_WIDTH-1]
//                              ? -dividend
//                              : dividend ;
//             mag_divisor    <= divisor[DATA_WIDTH-1]
//                              ? -divisor
//                              : divisor;
//             // Initialize accumulator: shift mag_dividend into high bits
//             partial_q      <= {{FRAC_SZ{1'b0}}, mag_dividend} << FRAC_SZ;
//             partial_r      <= 0;
//             cycle_cnt      <= CYCLES;
//             state          <= EXECUTE;
//           end
//         end

//         EXECUTE: begin
//           if (cycle_cnt != 0) begin
//             // do STEP bits of restoring division
//             tmp_q = partial_q;
//             tmp_r = partial_r;
//             for (i = 0; i < STEP; i = i + 1) begin
//               tmp_r = { tmp_r[ACC_W-2:0], tmp_q[ACC_W-1] };
//               tmp_q = tmp_q << 1;
//               if (tmp_r >= {{FRAC_SZ{1'b0}}, mag_divisor}) begin
//                 tmp_r = tmp_r - {{FRAC_SZ{1'b0}}, mag_divisor};
//                 tmp_q[0] = 1'b1;
//               end else begin
//                 tmp_q[0] = 1'b0;
//               end
//             end
//             partial_q <= tmp_q;
//             partial_r <= tmp_r;
//             cycle_cnt <= cycle_cnt - 1;
//           end else begin
//             // Extract the raw (unsigned) quotient & remainder
//             raw_q <= partial_q[ACC_W-1 -: DATA_WIDTH];
//             raw_r <= partial_r[ACC_W-1 -: DATA_WIDTH];
//             // Apply signs
//             quotient  <= sign_q ? -raw_q : raw_q;
//             remainder <= sign_dividend ? -raw_r : raw_r;
//             done      <= 1'b1;
//             state     <= IDLE;
//           end
//         end

//       endcase
//     end
//   end

// endmodule






// module Div #(
//     parameter DATA_WIDTH = 16,  // Bit width of dividend and divisor.
//     parameter STEP       = 4    // How many bits to process each cycle.
// )(
//     input                     clk,
//     input                     reset,   // active-low reset
//     input                     start,   // start pulse (should be at least one clock cycle)
//     input  [DATA_WIDTH-1:0]   dividend,
//     input  [DATA_WIDTH-1:0]   divisor,
//     output reg [DATA_WIDTH-1:0] quotient,
//     output reg [DATA_WIDTH-1:0] remainder,
//     output reg                done
// );

//   // Number of cycles required = DATA_WIDTH / STEP (assumes DATA_WIDTH is multiple of STEP)
//   localparam CYCLES = DATA_WIDTH / STEP;

//   // FSM states.
//   localparam IDLE    = 2'd0,
//              EXECUTE = 2'd1;
//   reg [1:0] state;

//   // We use registers to hold the ongoing quotient and remainder.
//   reg [DATA_WIDTH-1:0] partial_quotient;
//   reg [DATA_WIDTH-1:0] partial_remainder;
  
//   // Cycle counter for how many "big" cycles remain.
//   reg [$clog2(CYCLES+1)-1:0] cycle_count;

//   // Temporary variables for inner loop unrolling.
//   integer i;
//   reg [DATA_WIDTH-1:0] tmp_quotient;
//   reg [DATA_WIDTH-1:0] tmp_remainder;

//   // Main FSM.
//   always @(negedge clk or posedge reset) begin
//     if (reset) begin
//       quotient          <= {DATA_WIDTH{1'b0}};
//       remainder         <= {DATA_WIDTH{1'b0}};
//       partial_quotient  <= {DATA_WIDTH{1'b0}};
//       partial_remainder <= {DATA_WIDTH{1'b0}};
//       cycle_count       <= 0;
//       done              <= 1'b0;
//       state             <= IDLE;
//     end
//     else begin
//       case (state)
//         IDLE: begin
//           done <= 1'b0;
//           if (start) begin
//             // Initialize algorithm.
//             partial_quotient  <= dividend;
//             partial_remainder <= {DATA_WIDTH{1'b0}};
//             cycle_count       <= CYCLES;
//             state             <= EXECUTE;
//           end
//         end

//         EXECUTE: begin
//           if (cycle_count > 0) begin
//             // Copy registers into temporary variables for the inner for-loop.
//             tmp_quotient  = partial_quotient;
//             tmp_remainder = partial_remainder;
//             // Unroll "STEP" iterations of the restoring division algorithm:
//             for (i = 0; i < STEP; i = i + 1) begin
//               // Shift left: Bring in the MSB of tmp_quotient into tmp_remainder.
//               tmp_remainder = {tmp_remainder[DATA_WIDTH-2:0], tmp_quotient[DATA_WIDTH-1]};
//               // Left shift the quotient.
//               tmp_quotient = tmp_quotient << 1;
//               // Compare, subtract, and set the current LSB of quotient if possible.
//               if (tmp_remainder >= divisor) begin
//                 tmp_remainder = tmp_remainder - divisor;
//                 tmp_quotient[0] = 1'b1;
//               end
//               else begin
//                 tmp_quotient[0] = 1'b0;
//               end
//             end
//             // Write back the results of the inner unrolled loop.
//             partial_quotient  <= tmp_quotient;
//             partial_remainder <= tmp_remainder;
//             cycle_count       <= cycle_count - 1;
//           end
//           else begin
//             // When all cycles are done, output the final quotient and remainder.
//             quotient  <= partial_quotient;
//             remainder <= partial_remainder;
//             done      <= 1'b1;
//             state     <= IDLE;
//           end
//         end

//         default: state <= IDLE;
//       endcase
//     end
//   end

// endmodule


// module Div #(
//     parameter DATA_WIDTH = 16,  // Bit width of dividend and divisor.
//     parameter STEP       = 7    // Number of iterations to process per cycle.
// )(
//     input                         clk,
//     input                         reset,    // Active-low reset.
//     input                         start,    // Start pulse (assert at least one clock cycle).
//     input      [DATA_WIDTH-1:0]   dividend,
//     input      [DATA_WIDTH-1:0]   divisor,
//     output reg [DATA_WIDTH-1:0]   quotient,
//     output reg [DATA_WIDTH-1:0]   remainder,
//     output reg                    done
// );

//   // FSM states.
//   localparam IDLE    = 2'd0,
//              EXECUTE = 2'd1;
//   reg [1:0] state;

//   // Working registers for quotient and remainder.
//   reg [DATA_WIDTH-1:0] partial_quotient;
//   reg [DATA_WIDTH-1:0] partial_remainder;

//   // Counter for remaining single-bit iterations.
//   reg [$clog2(DATA_WIDTH+1)-1:0] iter_count;

//   // Temporary variables for unrolling iterations.
//   integer i;
//   reg [DATA_WIDTH-1:0] tmp_quotient;
//   reg [DATA_WIDTH-1:0] tmp_remainder;

//   // Compute the number of iterations to perform this cycle.
//   // This is a combinational value and will be either STEP or the remaining iterations.
//   wire [$clog2(DATA_WIDTH+1)-1:0] current_step;
//   assign current_step = (iter_count < STEP) ? iter_count : STEP;

//   always @(posedge clk or negedge reset) begin
//     if (!reset) begin
//       quotient          <= {DATA_WIDTH{1'b0}};
//       remainder         <= {DATA_WIDTH{1'b0}};
//       partial_quotient  <= {DATA_WIDTH{1'b0}};
//       partial_remainder <= {DATA_WIDTH{1'b0}};
//       iter_count        <= 0;
//       done              <= 1'b0;
//       state             <= IDLE;
//     end else begin
//       case (state)
//         IDLE: begin
//           done <= 1'b0;
//           if (start) begin
//             // Load the dividend and initialize iteration counter.
//             partial_quotient  <= dividend;
//             partial_remainder <= {DATA_WIDTH{1'b0}};
//             iter_count        <= DATA_WIDTH; // A total of DATA_WIDTH iterations.
//             state             <= EXECUTE;
//           end
//         end

//         EXECUTE: begin
//           if (iter_count > 0) begin
//             // Copy working registers to temporary variables.
//             tmp_quotient  = partial_quotient;
//             tmp_remainder = partial_remainder;
            
//             // Unroll current_step iterations of the restoring division algorithm.
//             for (i = 0; i < current_step; i = i + 1) begin
//               // Shift left: bring in the MSB of tmp_quotient to tmp_remainder.
//               tmp_remainder = {tmp_remainder[DATA_WIDTH-2:0], tmp_quotient[DATA_WIDTH-1]};
//               // Left shift the quotient.
//               tmp_quotient = tmp_quotient << 1;
//               // If remainder is big enough, subtract divisor and set LSB.
//               if (tmp_remainder >= divisor) begin
//                 tmp_remainder = tmp_remainder - divisor;
//                 tmp_quotient[0] = 1'b1;
//               end
//               else begin
//                 tmp_quotient[0] = 1'b0;
//               end
//             end
            
//             // Update our registers with the unrolled loop results.
//             partial_quotient  <= tmp_quotient;
//             partial_remainder <= tmp_remainder;
//             iter_count        <= iter_count - current_step;
//           end else begin
//             // When all iterations are complete, produce outputs.
//             quotient  <= partial_quotient;
//             remainder <= partial_remainder;
//             done      <= 1'b1;
//             state     <= IDLE;
//           end
//         end

//         default: state <= IDLE;
//       endcase
//     end
//   end
// endmodule


