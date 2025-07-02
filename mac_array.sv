//// the module that makes the period = 6ns//////////////////the DSP to DSP cascade is pipelined////
module mac_array #(
    parameter IN_CHANNELS  = 4,
    parameter KERNEL_SIZE  = 3,
    parameter DATA_WIDTH   = 16,
    parameter IMAGE_WIDTH  = 188,
    parameter PADDING      = 1,
    parameter FRAC_SZ      = 12
)(
    input  logic clk,
    input  logic rst,
    input  logic start, 
    input  logic signed [DATA_WIDTH-1:0]
          input_feature_map [KERNEL_SIZE][KERNEL_SIZE],
    input  logic signed [DATA_WIDTH-1:0]
          kernel_weights   [KERNEL_SIZE][KERNEL_SIZE],
    input logic [$clog2(IN_CHANNELS)-1:0] output_channel,
   // input logic bnfifo_full,
    output logic signed [DATA_WIDTH-1:0] mac_output,
    output logic done
);

  // ------------------------------------------------------------------
  // 1) Multiply stage:  
  //    - For SYNTHESIS=1 (Vivado), we instantiate DSP48E1 with PREG=1.
  //    - Otherwise (simulation), we do a plain signed multiply.
  // ------------------------------------------------------------------
  wire signed [31:0] dsp_prod [KERNEL_SIZE-1:0]
                              [KERNEL_SIZE-1:0];


// wire signed [31:0] dsp_prod_q[KERNEL_SIZE-1:0]
//                               [KERNEL_SIZE-1:0];
// // â””â”€â”€ now dsp_prod_q is back in Qm.n format

  genvar gi, gj;
  generate
      for (gi = 0; gi < KERNEL_SIZE; gi = gi + 1) begin : GEN_I
        for (gj = 0; gj < KERNEL_SIZE; gj = gj + 1) begin : GEN_J

          `ifndef SYNTHESIS
            // Behavioral multiply for simulation only:
            assign dsp_prod[gi][gj] =
              ($signed(input_feature_map[gi][gj]) 
              * $signed(kernel_weights[gi][gj])) ;
          `else
        
          // PolarFire MACC_PA for synthesis, pipelined output
          MACC_PA dsp_mul_inst (
          // Clock and reset
          .CLK(clk),
          
          // Data inputs
          .A(input_feature_map[gi][gj]),
          .B(kernel_weights[gi][gj]),
          .C(18'b0),
          .D(18'b0),              // Tie to 0 if not using pre-adder
          
          // Data output
          .P(dsp_prod[gi][gj]),
          
          // Carry input - tie to 0 if not using carry chain
          .CARRYIN(1'b0),                  // Carry input
          
          // Control signals - tie unused ones to appropriate values
          .OVFL_CARRYOUT_SEL(1'b0),        // Overflow carry select
          .DOTP(1'b0),                     // Dot product mode
          .SIMD(1'b0),      // SIMD mode
          .AL_N(1'b0),
          // Input pipeline register controls
          // A input registers (if not using, bypass them)
          .A_BYPASS(1'b1),                 // Bypass A input registers
          .A_SRST_N(dsp_reset_n),          // A register synchronous reset
          .A_EN(dsp_enable),               // A register enable
          //.A_ARST_N(dsp_reset_n),          // A register asynchronous reset
          
          // B input registers 
          .B_BYPASS(1'b1),                 // Bypass B input registers
          .B_SRST_N(dsp_reset_n),          // B register synchronous reset
          .B_EN(dsp_enable),               // B register enable
          //.B_ARST_N(dsp_reset_n),          // B register asynchronous reset
          
          // C input registers
          .C_BYPASS(1'b1),                 // Bypass C input registers
          .C_SRST_N(dsp_reset_n),          // C register synchronous reset
          .C_EN(dsp_enable),               // C register enable
          .C_ARST_N(dsp_reset_n),          // C register asynchronous reset
          
          // D input registers
          .D_BYPASS(1'b1),                 // Bypass D input registers
          .D_SRST_N(dsp_reset_n),          // D register synchronous reset
          .D_EN(dsp_enable),               // D register enable
          .D_ARST_N(dsp_reset_n),          // D register asynchronous reset
          
          // Subtraction controls - disable if not needed
          .SUB_BYPASS(1'b1),               // Bypass subtraction
          .SUB_SD_N(1'b1),                 // Subtraction synchronous disable
          .SUB_AD_N(1'b1),                 // Subtraction asynchronous disable  
          .SUB_SL_N(1'b1),                 // Subtraction sleep
          .SUB_EN(1'b0),                   // Subtraction enable
          .SUB(1'b0),                      // Subtraction control
          
          // Arithmetic right shift controls - disable if not needed
          .ARSHFT17_BYPASS(1'b1),          // Bypass arithmetic right shift
          .ARSHFT17_SD_N(1'b1),            // ARSHFT synchronous disable
          .ARSHFT17_AD_N(1'b1),            // ARSHFT asynchronous disable
          .ARSHFT17_SL_N(1'b1),            // ARSHFT sleep
          .ARSHFT17_EN(1'b0),              // ARSHFT enable
          .ARSHFT17(1'b0),                 // ARSHFT control
          
          // Cascade input feedback selection - disable if not using cascade
          .CDIN_FDBK_SEL_BYPASS(1'b1),     // Bypass cascade feedback
          .CDIN_FDBK_SEL_SD_N(2'b11),      // Cascade feedback sync disable
          .CDIN_FDBK_SEL_AD_N(2'b11),      // Cascade feedback async disable
          .CDIN_FDBK_SEL_SL_N(1'b1),       // Cascade feedback sleep
          .CDIN_FDBK_SEL_EN(1'b0),         // Cascade feedback enable
          .CDIN_FDBK_SEL(2'b00),           // Cascade feedback select
          
          // Pre-adder subtraction controls - disable if not using pre-adder
          .PASUB_BYPASS(1'b1),             // Bypass pre-adder subtraction
          .PASUB_SD_N(1'b1),               // PASUB synchronous disable
          .PASUB_AD_N(1'b1),               // PASUB asynchronous disable
          .PASUB_SL_N(1'b1),               // PASUB sleep
          .PASUB_EN(1'b0),                 // PASUB enable
          .PASUB(1'b0),                    // PASUB control
          
          // Cascade data input - tie to 0 if not using cascade
          .CDIN(48'b0),                    // Cascade data input
          
          // Output pipeline register controls
          .P_BYPASS(1'b0),                 // 0 = use pipeline register
          .P_SRST_N(dsp_reset_n),          // Pipeline register reset
          .P_EN(dsp_enable)                // Pipeline register enable
      );
          `endif

        end
      end
  endgenerate


  // ------------------------------------------------------------------
  // 2) Build & pipeline the partial sums
  // ------------------------------------------------------------------
  logic signed [31:0] partial_sum ;
  logic signed [31:0] partial_sum_reg;
  logic [$clog2(IN_CHANNELS)-1:0] output_channel_reg;

  integer i, j;
  always_comb begin
      partial_sum = '0;
      for (i = 0; i < KERNEL_SIZE; i = i + 1)
        for (j = 0; j < KERNEL_SIZE; j = j + 1)
          partial_sum += dsp_prod[i][j];
      // uncomment if you need the Qâ€format shift
          partial_sum >>>= FRAC_SZ;
  end



  always_ff @(posedge clk ) begin
    if (rst) begin
        partial_sum_reg <= '0;
    end else begin
     // if(!bn_fifo_full_reg)
        partial_sum_reg <= partial_sum;
    end
  end


  // ------------------------------------------------------------------
  // 3) FSM: accumulate over IN_CHANNELS
  // ------------------------------------------------------------------
  logic signed [2*DATA_WIDTH-1:0] mac_acc ;
  logic [$clog2(IN_CHANNELS)-1:0] channel_count;
  typedef enum logic [1:0] {IDLE, ACCUMULATE} state_t;
  state_t state;
// Saturation thresholds (Q4.12)
  localparam signed [31:0] SAT_POS = ((1 << (DATA_WIDTH-FRAC_SZ-1)) - 1) << FRAC_SZ;  // +7
  localparam signed [31:0] SAT_NEG = -(((1 << (DATA_WIDTH-FRAC_SZ-1)) - 1) << FRAC_SZ); // -7

  // Saturated output logic
  logic signed [DATA_WIDTH-1:0] sat_out;
  always_comb begin
    if (!done)
      sat_out = '0;
    else if (mac_acc > SAT_POS)
      sat_out = SAT_POS[DATA_WIDTH-1:0];
    else if (mac_acc < SAT_NEG)
      sat_out = SAT_NEG[DATA_WIDTH-1:0];
    else
      sat_out = mac_acc[DATA_WIDTH-1:0];
  end

  assign mac_output=sat_out;

  always_ff @(posedge clk) begin
    if (rst) begin
      state         <= IDLE;
      channel_count <= 0;
      done          <= 1'b0;
      output_channel_reg <=0;
      mac_acc <= '0;
    end else begin
       output_channel_reg <= output_channel;
      case (state)
        IDLE: begin
          done <= 1'b0;
         // output_channel_reg <= output_channel;
          mac_acc <= '0;
          if (start) begin
            state         <= ACCUMULATE;
            channel_count <= 0;
            //output_channel_reg <= output_channel;
          end
        end

        ACCUMULATE: begin
           //output_channel_reg <= output_channel;
         
            // if(!bnfifo_full)
           mac_acc <= (mac_acc + partial_sum_reg);

          // else 
            // mac_acc[p] <= mac_acc[p];
         

          if (channel_count == IN_CHANNELS-1) begin
            if(output_channel_reg == IN_CHANNELS-1) begin
            done  <= 1'b1;
            state <= IDLE;
          end
          end else
            channel_count <= channel_count + 1;
        end
      endcase
    end
  end

endmodule




// // the module that makes the period = 15.5ns//////////////////critical path is the DSP to DSP cascade///////////////////////////////////////////////
// module mac_array #(
//     parameter IN_CHANNELS  = 4,    // Total number of channels to accumulate
//     parameter KERNEL_SIZE  = 3,
//     parameter DATA_WIDTH   = 16,
//     parameter NUM_PIXELS   = 3,    // Process NUM_PIXELS at a time
//     parameter IMAGE_WIDTH  = 188,
//     parameter PADDING      = 1,
//     parameter FRAC_SZ      = 12
// )(
//     input  logic clk,
//     input  logic rst,
//     // 'start' should be pulsed once each time a new channel window is ready.
//     input  logic start,  
//     // Window for a single channel: [KERNEL_SIZE][KERNEL_SIZE+NUM_PIXELS-1]
//     input  logic signed [DATA_WIDTH-1:0] input_feature_map [KERNEL_SIZE][KERNEL_SIZE+NUM_PIXELS-1],
//     // Kernel weights for the current channel: [KERNEL_SIZE][KERNEL_SIZE]
//     input  logic signed [DATA_WIDTH-1:0] kernel_weights [KERNEL_SIZE][KERNEL_SIZE],
//     // (Optional) window column index (retained for interface consistency)
//     input  logic [DATA_WIDTH-1:0] col_index_window,
//     // Output: computed result (for example, using the first of the NUM_PIXELS outputs)
//     output logic signed [DATA_WIDTH-1:0] mac_output,
//     // 'done' asserts when the accumulation over all channels is complete.
//     output logic done
// );

//   // Accumulators & partial sums (32-bit to hold Q4.12)
//   logic signed [31:0] mac_acc         [NUM_PIXELS];
//   logic signed [31:0] partial_sum     [NUM_PIXELS];
//   // <<< PIPELINE REGISTER for partial_sum
//   logic signed [31:0] partial_sum_reg [NUM_PIXELS];

//   // Track how many channels have been added
//   logic [$clog2(IN_CHANNELS)-1:0] channel_count;

//   // FSM: IDLE → ACCUMULATE → back to IDLE
//   typedef enum logic [1:0] {IDLE, ACCUMULATE} state_t;
//   state_t state;

//   integer i, j, k, p;

//   // 1) Combinational: compute this channel’s partial_sum
//   always_comb begin
//     for (k = 0; k < NUM_PIXELS; k = k + 1) begin
//       partial_sum[k] = 0;
//       for (i = 0; i < KERNEL_SIZE; i = i + 1)
//         for (j = 0; j < KERNEL_SIZE; j = j + 1)
//           partial_sum[k] += input_feature_map[i][j + k] * kernel_weights[i][j];
//       // if you need the Q4.12 shift: partial_sum[k] >>>= FRAC_SZ;
//     end
//   end

//   // 2) Pipeline register: break comb→acc add path
//   always_ff @(posedge clk or posedge rst) begin
//     if (rst) begin
//       for (p = 0; p < NUM_PIXELS; p = p + 1)
//         partial_sum_reg[p] <= '0;
//     end else begin
//       for (p = 0; p < NUM_PIXELS; p = p + 1)
//         partial_sum_reg[p] <= partial_sum[p];
//     end
//   end

//   // 3) Drive mac_output when done
//   always_comb begin
//     if (done)
//       mac_output = mac_acc[0][DATA_WIDTH-1:0];
//     else
//       mac_output = '0;
//   end

//   // 4) FSM + accumulate each registered partial_sum
//   always_ff @(posedge clk or posedge rst) begin
//     if (rst) begin
//       state         <= IDLE;
//       channel_count <= '0;
//       done          <= 1'b0;
//       for (p = 0; p < NUM_PIXELS; p = p + 1)
//         mac_acc[p] <= '0;
//     end else begin
//       case (state)
//         IDLE: begin
//           done <= 1'b0;
//           // clear accumulators any time we're idle
//           for (p = 0; p < NUM_PIXELS; p = p + 1)
//             mac_acc[p] <= '0;

//           if (start) begin
//             // on start, go accumulate—but don't add until next cycle
//             channel_count <= '0;
//             state         <= ACCUMULATE;
//           end
//         end

//         ACCUMULATE: begin
//           // add the *registered* partial sum
//           for (p = 0; p < NUM_PIXELS; p = p + 1)
//             mac_acc[p] <= mac_acc[p] + partial_sum_reg[p];

//           if (channel_count == IN_CHANNELS - 1) begin
//             // last channel done
//             done  <= 1'b1;
//             state <= IDLE;
//           end else begin
//             // otherwise keep counting
//             channel_count <= channel_count + 1;
//           end
//         end

//       endcase
//     end
//   end

// endmodule
