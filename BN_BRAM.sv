module dual_port_bn_bram #(
  // --------------------------------------------------------------------------
  // Parameter declarations
  // --------------------------------------------------------------------------
  parameter int DATA_WIDTH    = 16,           // Width of each stored word
  parameter int OUT_CHANNELS  = 64,
  parameter PE_NUM              =1,           // Base channel count
  parameter IS_MEAN_VAR         =1

)(
  input  logic                  clk,       // Shared clock
  input  logic                  rst_n,     // Active‑low reset

  // ------------------ Port A (streaming read only) ------------------------
  input  logic                  enable_a,   // When high, advance port‑A pointer
  output logic signed [DATA_WIDTH-1:0] data_out_a, // Port‑A data output

  // ------------------ Port B (streaming read only) ------------------------
  input  logic                  enable_b,   // When high, advance port‑B pointer
  output logic signed [DATA_WIDTH-1:0] data_out_b  // Port‑B data output
);
	
  // We need twice that many entries in the BRAM
  localparam int DEPTH        = 2 * OUT_CHANNELS;
  localparam int ADDR_WIDTH   = $clog2(DEPTH);  // Bits needed to address DEPTH entries
  // --------------------------------------------------------------------------
  // 1) Memory array
  // --------------------------------------------------------------------------
  (* rom_style = "block" *)  reg  [DATA_WIDTH-1:0] mem_array [0:DEPTH-1];

  // --------------------------------------------------------------------------
  // 2) Read pointers for each port
  // --------------------------------------------------------------------------
  logic [ADDR_WIDTH-1:0] rd_ptr_a, rd_ptr_b;

  // Wrap‑around counters
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_ptr_a <= '0;
      rd_ptr_b <= OUT_CHANNELS;
    end else begin
      if (enable_a) begin
        if (rd_ptr_a == OUT_CHANNELS-1)
          rd_ptr_a <= 0;
        else
          rd_ptr_a <= rd_ptr_a + 1;
      end
      if (enable_b) begin
        if (rd_ptr_b == DEPTH-1)
          rd_ptr_b <= OUT_CHANNELS;
        else
          rd_ptr_b <= rd_ptr_b + 1;
      end
    end
  end

  // --------------------------------------------------------------------------
  // 3) Data outputs (registered for one‑cycle latency)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    data_out_a <= mem_array[rd_ptr_a];
    data_out_b <= mem_array[rd_ptr_b];
  end

  // --------------------------------------------------------------------------
  // 4) Initialization (simulation & synthesis‑time preload)
  //    Provide your own 2*OUT_CHANNELS‑line hex file named "init_data.hex"
  // --------------------------------------------------------------------------
  initial begin
  	case (PE_NUM)
  		1: if (IS_MEAN_VAR)
  				$readmemh("conv1_bn_mean_std.mem", mem_array);
  			else
  		 		$readmemh("conv1_bn_gamma_beta.mem", mem_array);
  		2: if (IS_MEAN_VAR) 
  				$readmemh("conv2_bn_mean_std.mem", mem_array);
  			else
  				$readmemh("conv2_bn_gamma_beta.mem", mem_array);
  		3: if(IS_MEAN_VAR)
  				$readmemh("conv3_bn_mean_std.mem", mem_array);
  			else
  				$readmemh("conv3_bn_gamma_beta.mem", mem_array);
  		4: if(IS_MEAN_VAR)
  				$readmemh("conv4_bn_mean_std.mem", mem_array);
  			else
  				$readmemh("conv4_bn_gamma_beta.mem", mem_array);
  		5: if (IS_MEAN_VAR)
  		 		$readmemh("conv5_bn_mean_std.mem", mem_array);
  		 	else
  		 		$readmemh("conv5_bn_gamma_beta.mem", mem_array);
  		6: if(IS_MEAN_VAR)
  				$readmemh("conv6_bn_mean_std.mem", mem_array);
  			else
  				$readmemh("conv6_bn_gamma_beta.mem", mem_array);
  	
  		default : /* default */;
  	endcase
    
  end

endmodule

