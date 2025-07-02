//==============================================================================
// Modified FC Controller with Bias Support (Refactored)
//==============================================================================
module fc_controller #(
    parameter DATA_WIDTH = 16,
    parameter INPUT_SIZE = 12,
    parameter OUTPUT_SIZE = 100,
    parameter WEIGHT_ADDR_WIDTH = 12,
    parameter BIAS_ADDR_WIDTH = 8,  // Added for bias addressing
    parameter ENABLE_ACTIVATION = 1,
    parameter FRAC_SZ = 12
)(
    input wire clk,
    input wire rst_n,
    
    // Control interface
    input wire start,
    input wire use_activation,     // Runtime activation control
    output reg done,
    output reg busy,
    
    // Input FIFO interface
    input wire signed [DATA_WIDTH-1:0] input_data,
    input wire input_empty,
    input wire input_valid,
    output reg input_rd_en,
    
    // Weight BRAM interface
    input wire signed [DATA_WIDTH-1:0] weight_data,
    input wire weight_valid,
    output reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr,
    output reg weight_rd_en,
    
    // Bias BRAM interface (New)
    input wire signed [DATA_WIDTH-1:0] bias_data,
    input wire bias_valid,
    output reg [BIAS_ADDR_WIDTH-1:0] bias_addr,
    output reg bias_rd_en,
    
    // MAC unit interface
    input wire signed [2*DATA_WIDTH-1:0] mac_result,
    input wire mac_valid,
    output reg mac_enable,
    output reg mac_acc_clear,
    output reg signed [DATA_WIDTH-1:0] mac_input_a,
    output reg signed [DATA_WIDTH-1:0] mac_input_b,
    
    // Activation function interface (only used when ENABLE_ACTIVATION=1)
    input wire signed [DATA_WIDTH-1:0] activation_output,
    input wire activation_valid,
    output reg activation_enable,
    output reg signed [2*DATA_WIDTH-1:0] activation_input,
    
    // Output FIFO interface
    input wire output_full,
    output reg signed [DATA_WIDTH-1:0] output_data,
    output reg output_wr_en
);

    // State machine states
    localparam IDLE = 4'b0000;
    localparam LOAD_INPUT = 4'b0001;
    localparam COMPUTE = 4'b0010;
    localparam WAIT_MAC = 4'b0011;
    localparam LOAD_BIAS = 4'b0100;  // New state for bias loading
    localparam ADD_BIAS = 4'b0101;   // New state for bias addition
    localparam ACTIVATION = 4'b0110;
    localparam WRITE_OUTPUT = 4'b0111;
    localparam NEXT_OUTPUT = 4'b1000;

    reg [3:0] current_state, next_state;
    
    // Counters and indices
    reg [15:0] input_idx;
    reg [15:0] output_idx;
    reg [15:0] weight_base_addr;
    reg [15:0] weight_addr_idx;
    
    // Input buffer to store current input vector
    reg signed [DATA_WIDTH-1:0] input_buffer [INPUT_SIZE-1:0];
    reg [15:0] input_load_count;
    reg input_loaded;
    
    // Pipeline registers
    reg mac_enable_d1;
    reg [15:0] compute_count;
    reg output_ready;
    reg acc_cleared;
    
    // Bias handling registers
    reg signed [2*DATA_WIDTH-1:0] mac_with_bias;
    reg bias_loaded;
    
    // Internal activation bypass logic
    reg signed [DATA_WIDTH-1:0] bypass_output;
    reg bypass_valid;
    
    // Determine if we should use activation or bypass
    wire should_use_activation = ENABLE_ACTIVATION && use_activation;

    // Saturation thresholds (Q4.12)
    localparam signed [2*DATA_WIDTH-1:0] SAT_POS = ((1 << (DATA_WIDTH-FRAC_SZ-1)) - 1) << FRAC_SZ;  // +7
    localparam signed [2*DATA_WIDTH-1:0] SAT_NEG = -(((1 << (DATA_WIDTH-FRAC_SZ-1)) - 1) << FRAC_SZ); // -7
    
    // Internal activation bypass logic with bias
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bypass_output <= 0;
            bypass_valid <= 1'b0;
        end else if (current_state == ADD_BIAS && bias_loaded && !should_use_activation) begin
            // Handle bypass with saturation after bias addition
            if (mac_with_bias > SAT_POS) begin
                bypass_output <= SAT_POS[DATA_WIDTH-1:0] ; // Max positive
            end else if (mac_with_bias < SAT_NEG) begin
                bypass_output <= SAT_NEG[DATA_WIDTH-1:0]; // Max negative  
            end else begin
                bypass_output <= mac_with_bias[DATA_WIDTH-1:0];
            end
            bypass_valid <= 1'b1;
        end else begin
            bypass_valid <= 1'b0;
        end
    end


 

    // State transition
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Next state logic
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (start && !input_empty)
                    next_state = LOAD_INPUT;
            end
            
            LOAD_INPUT: begin
                if (input_loaded)
                    next_state = COMPUTE;
            end
            
            COMPUTE: begin
                if (input_idx >= INPUT_SIZE)
                    next_state = WAIT_MAC;
            end
            
            WAIT_MAC: begin
                if (mac_valid && output_ready)
                    next_state = LOAD_BIAS;
            end
            
            LOAD_BIAS: begin
                if (bias_valid)
                    next_state = ADD_BIAS;
            end
            
            ADD_BIAS: begin
                if (bias_loaded) begin
                    if (should_use_activation)
                        next_state = ACTIVATION;
                    else
                        next_state = WRITE_OUTPUT;
                end
            end
            
            ACTIVATION: begin
                if (activation_valid)
                    next_state = WRITE_OUTPUT;
            end
            
            WRITE_OUTPUT: begin
                if (!output_full)
                    next_state = NEXT_OUTPUT;
            end
            
            NEXT_OUTPUT: begin
                if (output_idx >= OUTPUT_SIZE - 1)
                    next_state = IDLE;
                else
                    next_state = COMPUTE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // Main control logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers
            input_idx <= 0;
            output_idx <= 0;
            weight_base_addr <= 0;
            weight_addr_idx <= 0;
            input_loaded <= 0;
            input_load_count <= 0;
            compute_count <= 0;
            output_ready <= 0;
            bias_loaded <= 0;
            mac_with_bias <= 0;
            
            // Reset control signals
            input_rd_en <= 0;
            weight_rd_en <= 0;
            bias_rd_en <= 0;
            bias_addr <= 0;
            mac_enable <= 0;
            mac_acc_clear <= 0;
            mac_input_a <= 0;
            mac_input_b <= 0;
            activation_enable <= 0;
            activation_input <= 0;
            output_wr_en <= 0;
            output_data <= 0;
            
            // Reset status signals
            done <= 0;
            busy <= 0;
            mac_enable_d1 <= 0;
            acc_cleared <= 0;
            
        end else begin
            
            // Pipeline the MAC enable signal
            mac_enable_d1 <= mac_enable;
            
            case (current_state)
                IDLE: begin
                    done <= 0;
                    busy <= 0;
                    input_loaded <= 0;
                    input_load_count <= 0;
                    input_idx <= 0;
                    output_idx <= 0;
                    weight_base_addr <= 0;
                    weight_addr_idx <= 0;
                    mac_acc_clear <= 0;
                    output_ready <= 0;
                    bias_loaded <= 0;
                end
                
                LOAD_INPUT: begin
                    busy <= 1;
                    input_rd_en <= !input_empty && (input_load_count < INPUT_SIZE);
                    
                    if (input_valid && input_load_count < INPUT_SIZE) begin
                        input_buffer[input_load_count] <= input_data;
                        input_load_count <= input_load_count + 1;
                    end
                    
                    if (input_load_count >= INPUT_SIZE) begin
                        input_loaded <= 1;
                        input_rd_en <= 0;
                    end
                end
                
                COMPUTE: begin
                    input_rd_en <= 0;
                    
                    if (input_idx == 0 && !acc_cleared) begin
                        mac_acc_clear <= 1;
                        compute_count <= 0;
                        acc_cleared <= 1;
                        weight_addr_idx <= 1;
                        weight_addr <= weight_base_addr;
                        weight_rd_en <= 1;
                    end else begin
                        mac_acc_clear <= 0;
                        
                        if (weight_addr_idx < INPUT_SIZE) begin
                            weight_addr <= weight_base_addr + weight_addr_idx;
                            weight_rd_en <= 1;
                            weight_addr_idx <= weight_addr_idx + 1;
                        end else begin
                            weight_rd_en <= 0;
                        end
                        
                        if (weight_valid && input_idx < INPUT_SIZE) begin
                            mac_input_a <= input_buffer[input_idx];
                            mac_input_b <= weight_data;
                            mac_enable <= 1;
                            input_idx <= input_idx + 1;
                            compute_count <= compute_count + 1;
                        end else begin
                            mac_enable <= 0;
                        end
                        
                        if (input_idx >= INPUT_SIZE) begin
                            output_ready <= 1;
                        end
                    end
                end
                
                WAIT_MAC: begin
                    weight_rd_en <= 0;
                    mac_enable <= 0;
                    activation_enable <= 0;
                    bias_rd_en <= 0;
                end
                
                LOAD_BIAS: begin
                    // Load bias for current output neuron
                    bias_addr <= output_idx[BIAS_ADDR_WIDTH-1:0];
                    bias_rd_en <= 1;
                    bias_loaded <= 0;
                end
                
                ADD_BIAS: begin
                    bias_rd_en <= 0;
                    if (bias_valid && !bias_loaded) begin
                        // Add bias to MAC result (sign extend bias to match MAC result width)
                        mac_with_bias <= ($signed(mac_result)>>> FRAC_SZ)+$signed({{DATA_WIDTH{bias_data[DATA_WIDTH-1]}}, bias_data});
                       // mac_with_bias <= ($signed(mac_result)+ $signed({{DATA_WIDTH{bias_data[DATA_WIDTH-1]}}, bias_data})) >>> FRAC_SZ;
                        bias_loaded <= 1;
                        
                        if (should_use_activation) begin
                            activation_input <= ($signed(mac_result)>>> FRAC_SZ)+$signed({{DATA_WIDTH{bias_data[DATA_WIDTH-1]}}, bias_data});
                            //activation_input <= ($signed(mac_result)+ $signed({{DATA_WIDTH{bias_data[DATA_WIDTH-1]}}, bias_data})) >>> FRAC_SZ;
                            activation_enable <= 1;
                        end
                    end
                end
                
                ACTIVATION: begin
                    if (activation_valid) begin
                        output_data <= activation_output;
                        activation_enable <= 0;
                    end
                end
                
                WRITE_OUTPUT: begin
                    // Use activation output or bypass output based on configuration
                    if (current_state == WRITE_OUTPUT && next_state == NEXT_OUTPUT) begin
                        if (!should_use_activation && bypass_valid) begin
                            output_data <= bypass_output;
                        end
                    end
                    
                    if (!output_full) begin
                        output_wr_en <= 1;
                    end else begin
                        output_wr_en <= 0;
                    end
                end
                
                NEXT_OUTPUT: begin
                    output_wr_en <= 0;
                    output_ready <= 0;
                    acc_cleared <= 0;
                    bias_loaded <= 0;
                    
                    if (output_idx < OUTPUT_SIZE - 1) begin
                        output_idx <= output_idx + 1;
                        weight_base_addr <= weight_base_addr + INPUT_SIZE;
                        input_idx <= 0;
                        weight_addr_idx <= 0;
                    end else begin
                        done <= 1;
                        busy <= 0;
                    end
                end
                
                default: begin
                    done <= 0;
                    busy <= 0;
                    input_rd_en <= 0;
                    weight_rd_en <= 0;
                    bias_rd_en <= 0;
                    mac_enable <= 0;
                    activation_enable <= 0;
                    output_wr_en <= 0;
                end
            endcase
        end
    end

endmodule



//==============================================================================
// Modified FC Controller with Activation Control (Refactored)
//==============================================================================
/*module fc_controller #(
    parameter DATA_WIDTH = 16,
    parameter INPUT_SIZE = 12,
    parameter OUTPUT_SIZE = 100,
    parameter WEIGHT_ADDR_WIDTH = 12,
    parameter ENABLE_ACTIVATION = 1,
    parameter FRAC_SZ = 12
)(
    input wire clk,
    input wire rst_n,
    
    // Control interface
    input wire start,
    input wire use_activation,     // Runtime activation control
    output reg done,
    output reg busy,
    
    // Input FIFO interface
    input wire [DATA_WIDTH-1:0] input_data,
    input wire input_empty,
    input wire input_valid,
    output reg input_rd_en,
    
    // Weight BRAM interface
    input wire [DATA_WIDTH-1:0] weight_data,
    input wire weight_valid,
    output reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr,
    output reg weight_rd_en,
    
    // MAC unit interface
    input wire signed [2*DATA_WIDTH-1:0] mac_result,
    input wire mac_valid,
    output reg mac_enable,
    output reg mac_acc_clear,
    output reg signed [DATA_WIDTH-1:0] mac_input_a,
    output reg signed [DATA_WIDTH-1:0] mac_input_b,
    
    // Activation function interface (only used when ENABLE_ACTIVATION=1)
    input wire signed [DATA_WIDTH-1:0] activation_output,
    input wire activation_valid,
    output reg activation_enable,
    output reg signed [2*DATA_WIDTH-1:0] activation_input,
    
    // Output FIFO interface
    input wire output_full,
    output reg [DATA_WIDTH-1:0] output_data,
    output reg output_wr_en
);

    // State machine states
    localparam IDLE = 3'b000;
    localparam LOAD_INPUT = 3'b001;
    localparam COMPUTE = 3'b010;
    localparam WAIT_MAC = 3'b011;
    localparam ACTIVATION = 3'b100;
    localparam WRITE_OUTPUT = 3'b110;
    localparam NEXT_OUTPUT = 3'b111;

    reg [2:0] current_state, next_state;
    
    // Counters and indices
    reg [15:0] input_idx;
    reg [15:0] output_idx;
    reg [15:0] weight_base_addr;
    //reg [WEIGHT_ADDR_WIDTH-1:0] current_weight_addr;
    reg [15:0] weight_addr_idx;
    
    // Input buffer to store current input vector
    reg [DATA_WIDTH-1:0] input_buffer [INPUT_SIZE-1:0];
    reg [15:0] input_load_count;
    reg input_loaded;
    
    // Pipeline registers
    reg mac_enable_d1;
    reg [15:0] compute_count;
    reg output_ready;
    reg acc_cleared;
    
    // Internal activation bypass logic
    reg signed [DATA_WIDTH-1:0] bypass_output;
    reg bypass_valid;
    
    // Determine if we should use activation or bypass
    wire should_use_activation = ENABLE_ACTIVATION && use_activation;

    // Saturation thresholds (Q4.12)
    localparam signed [2*DATA_WIDTH-1:0] SAT_POS = ((1 << (DATA_WIDTH-FRAC_SZ-1)) - 1) << FRAC_SZ;  // +7
    localparam signed [2*DATA_WIDTH-1:0] SAT_NEG = -(((1 << (DATA_WIDTH-FRAC_SZ-1)) - 1) << FRAC_SZ); // -7
    
    // Internal activation bypass logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bypass_output <= 0;
            bypass_valid <= 1'b0;
        end else if (current_state == WAIT_MAC && mac_valid && !should_use_activation) begin
            // Handle bypass with saturation
            if (mac_result > SAT_POS) begin
                bypass_output <= SAT_POS[DATA_WIDTH-1:0] ; // Max positive
            end else if (mac_result < SAT_NEG) begin
                bypass_output <= SAT_NEG[DATA_WIDTH-1:0]; // Max negative  
            end else begin
                bypass_output <= mac_result[DATA_WIDTH-1:0];
            end
            bypass_valid <= 1'b1;
        end else begin
            bypass_valid <= 1'b0;
        end
    end

    // State transition
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Next state logic
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (start && !input_empty)
                    next_state = LOAD_INPUT;
            end
            
            LOAD_INPUT: begin
                if (input_loaded)
                    next_state = COMPUTE;
            end
            
            COMPUTE: begin
                if (input_idx >= INPUT_SIZE)
                    next_state = WAIT_MAC;
            end
            
            WAIT_MAC: begin
                if (mac_valid && output_ready) begin
                    if (should_use_activation)
                        next_state = ACTIVATION;
                    else
                        next_state = WRITE_OUTPUT;
                end
            end
            
            ACTIVATION: begin
                if (activation_valid)
                    next_state = WRITE_OUTPUT;
            end
            
            WRITE_OUTPUT: begin
                if (!output_full)
                    next_state = NEXT_OUTPUT;
            end
            
            NEXT_OUTPUT: begin
                if (output_idx >= OUTPUT_SIZE - 1)
                    next_state = IDLE;
                else
                    next_state = COMPUTE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // Main control logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers
            input_idx <= 0;
            output_idx <= 0;
            weight_base_addr <= 0;
            //current_weight_addr <= 0;
            weight_addr_idx <= 0;
            input_loaded <= 0;
            input_load_count <= 0;
            compute_count <= 0;
            output_ready <= 0;
            
            // Reset control signals
            input_rd_en <= 0;
            weight_rd_en <= 0;
            mac_enable <= 0;
            mac_acc_clear <= 0;
            mac_input_a <= 0;
            mac_input_b <= 0;
            activation_enable <= 0;
            activation_input <= 0;
            output_wr_en <= 0;
            output_data <= 0;
            
            // Reset status signals
            done <= 0;
            busy <= 0;
            mac_enable_d1 <= 0;
            acc_cleared <= 0;
            
        end else begin
            
            // Pipeline the MAC enable signal
            mac_enable_d1 <= mac_enable;
            
            case (current_state)
                IDLE: begin
                    done <= 0;
                    busy <= 0;
                    input_loaded <= 0;
                    input_load_count <= 0;
                    input_idx <= 0;
                    output_idx <= 0;
                    weight_base_addr <= 0;
                    weight_addr_idx <= 0;
                    mac_acc_clear <= 0;
                    output_ready <= 0;
                end
                
                LOAD_INPUT: begin
                    busy <= 1;
                    input_rd_en <= !input_empty && (input_load_count < INPUT_SIZE);
                    
                    if (input_valid && input_load_count < INPUT_SIZE) begin
                        input_buffer[input_load_count] <= input_data;
                        input_load_count <= input_load_count + 1;
                    end
                    
                    if (input_load_count >= INPUT_SIZE) begin
                        input_loaded <= 1;
                        input_rd_en <= 0;
                    end
                end
                
                COMPUTE: begin
                    input_rd_en <= 0;
                    
                    if (input_idx == 0 && !acc_cleared) begin
                        mac_acc_clear <= 1;
                        compute_count <= 0;
                        acc_cleared <= 1;
                        weight_addr_idx <= 1;
                        weight_addr <= weight_base_addr;
                        weight_rd_en <= 1;
                    end else begin
                        mac_acc_clear <= 0;
                        
                        if (weight_addr_idx < INPUT_SIZE) begin
                            weight_addr <= weight_base_addr + weight_addr_idx;
                            weight_rd_en <= 1;
                            weight_addr_idx <= weight_addr_idx + 1;
                        end else begin
                            weight_rd_en <= 0;
                        end
                        
                        if (weight_valid && input_idx < INPUT_SIZE) begin
                            mac_input_a <= input_buffer[input_idx];
                            mac_input_b <= weight_data;
                            mac_enable <= 1;
                            input_idx <= input_idx + 1;
                            compute_count <= compute_count + 1;
                        end else begin
                            mac_enable <= 0;
                        end
                        
                        if (input_idx >= INPUT_SIZE) begin
                            output_ready <= 1;
                        end
                    end
                end
                
                WAIT_MAC: begin
                    weight_rd_en <= 0;
                    mac_enable <= 0;
                    activation_enable <= 0;
                    
                    if (mac_valid && compute_count >= INPUT_SIZE) begin
                        if (should_use_activation) begin
                            activation_input <= mac_result;
                            activation_enable <= 1;
                        end
                        // Bypass logic is handled in separate always block
                    end
                end
                
                ACTIVATION: begin
                    if (activation_valid) begin
                        output_data <= activation_output;
                        activation_enable <= 0;
                    end
                end
                
                WRITE_OUTPUT: begin
                    // Use activation output or bypass output based on configuration
                    if (current_state == WRITE_OUTPUT && next_state == NEXT_OUTPUT) begin
                        if (!should_use_activation && bypass_valid) begin
                            output_data <= bypass_output;
                        end
                    end
                    
                    if (!output_full) begin
                        output_wr_en <= 1;
                    end else begin
                        output_wr_en <= 0;
                    end
                end
                
                NEXT_OUTPUT: begin
                    output_wr_en <= 0;
                    output_ready <= 0;
                    acc_cleared <= 0;
                    
                    if (output_idx < OUTPUT_SIZE - 1) begin
                        output_idx <= output_idx + 1;
                        weight_base_addr <= weight_base_addr + INPUT_SIZE;
                        input_idx <= 0;
                        weight_addr_idx <= 0;
                    end else begin
                        done <= 1;
                        busy <= 0;
                    end
                end
                
                default: begin
                    done <= 0;
                    busy <= 0;
                    input_rd_en <= 0;
                    weight_rd_en <= 0;
                    mac_enable <= 0;
                    activation_enable <= 0;
                    output_wr_en <= 0;
                end
            endcase
        end
    end

endmodule*/