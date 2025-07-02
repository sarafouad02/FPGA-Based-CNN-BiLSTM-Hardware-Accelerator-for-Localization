
// ------------------------------------------------------------------
// 2) Fixed-point batch normalization in Q4.12
// ------------------------------------------------------------------
module batch_norm #(
  parameter DATA_WIDTH = 16,
  parameter FRAC_SZ    = 12
)(
  input  logic                         clk,
  input  logic                         rst,
  input  logic                         enable, bnfifo_read_flag,
  input  logic signed [DATA_WIDTH-1:0] bn_input,  // Q4.12
  input  logic signed [DATA_WIDTH-1:0] mean_mov,    // Q4.12
  input  logic signed [DATA_WIDTH-1:0] std_mov,     // Q4.12
  input  logic signed [DATA_WIDTH-1:0] gamma,       // Q4.12
  input  logic signed [DATA_WIDTH-1:0] beta,        // Q4.12
  output logic                         bn_done, ready,
  output logic signed [DATA_WIDTH-1:0] bn_output    // Q4.12
);

  typedef enum logic [2:0] {IDLE, CALC, START_DIV, WAIT_DIV, SCALE} state_t;
  state_t state, next_state;

  // Latch inputs
  logic signed [DATA_WIDTH-1:0] mac_reg, mean_reg, std_reg, gamma_reg, beta_reg;
  logic signed [DATA_WIDTH-1:0] std_dev_reg;
  logic signed [DATA_WIDTH-1:0] normalized_reg;

  // Division interface
  logic div_start, div_done, bnfifo_read_flag_reg;
  reg [DATA_WIDTH-1:0] div_q, div_r;


  // FSM
  always_comb begin
    next_state = state;
    case (state)
      IDLE:       next_state = enable   ? CALC      : IDLE;
      CALC:       next_state = bnfifo_read_flag_reg? START_DIV : CALC;
      START_DIV:  next_state = WAIT_DIV; //bnfifo_read_flag_reg? WAIT_DIV : 
      WAIT_DIV:   next_state = div_done  ? SCALE     : WAIT_DIV;
      SCALE:      next_state = IDLE;
    endcase
  end
wire signed [31: 0] product ;
assign product = gamma_reg * normalized_reg;

  always_ff @(posedge clk) begin
    if (rst) begin
      state          <= IDLE;
      bn_done        <= 1'b0;
      mac_reg        <= 0;
      mean_reg       <= 0;
      // std_reg        <= 0;
      gamma_reg      <= 0;
      beta_reg       <= 0;
      std_reg    <= (1<<FRAC_SZ);
      normalized_reg <= 0;
      div_start      <= 0;
      bnfifo_read_flag_reg <= 0;
      ready     <= 0;
    end else begin
      state <= next_state;
      case (state)
        IDLE: begin
          bn_done   <= 0;
          div_start <= 0;
          ready     <= 0;

          if (enable) begin
            ready     <= 1;
            // bnfifo_read_flag_reg <= bnfifo_read_flag;
            // mac_reg   <= bn_input;
            mean_reg  <= mean_mov;
            std_reg   <= std_mov;
            gamma_reg <= gamma;
            beta_reg  <= beta;
          end
        end
        
        CALC: begin
          ready     <= 0;
          bnfifo_read_flag_reg <= bnfifo_read_flag;
          if (bnfifo_read_flag_reg) begin
            mac_reg   <= bn_input;
          end else begin
            mac_reg<= 0;
          end
        end

        START_DIV: begin
          div_start <= 1;
          ready     <= 0;
          
        end

        WAIT_DIV: begin
          div_start <= 0;
          if (div_done)
            normalized_reg <= div_q;  // already Q4.12
        end

        SCALE: begin
          // gamma * normalized => Q8.24, then shift back
          bn_output <= (product>>> FRAC_SZ) + beta_reg;
          bn_done   <= 1'b1;
        end
      endcase
    end
  end

  // instantiate our fixed-point divider
  cordic_div #(
    .WIDTH(DATA_WIDTH),
    .FRAC_SZ   (FRAC_SZ)
  ) u_div (
    .clk      (clk),
    .reset    (rst),
    .start    (div_start),
    .numerator((mac_reg - mean_reg)),
    .denominator(std_reg),
    .quotient (div_q),
    .done     (div_done)
  );

endmodule


