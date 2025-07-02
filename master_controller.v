//==============================================================================
// Pipeline Controller Module
// Manages the pipelining logic for multi-layer neural networks
//==============================================================================
module pipeline_controller #(
    parameter NUM_LAYERS = 3,
    parameter DATA_WIDTH = 16
)(
    input wire clk,
    input wire rst_n,
    
    // Global control
    input wire network_enable,
    input wire pipeline_reset,
    
    // Layer status inputs
    input wire [NUM_LAYERS-1:0] layer_busy,
    input wire [NUM_LAYERS-1:0] layer_done,
    
    // FIFO status inputs
    input wire input_fifo_empty,
    input wire [NUM_LAYERS-2:0] inter_fifo_empty,  // FIFOs between layers
    input wire output_fifo_full,
    
    // Layer control outputs
    output reg [NUM_LAYERS-1:0] layer_start,
    
    // Pipeline status outputs
    output wire pipeline_busy,
    output wire pipeline_stalled,
    output wire pipeline_ready
);

    // Internal signals
    wire [NUM_LAYERS-1:0] layer_can_start;
    wire [NUM_LAYERS-1:0] layer_should_start;
    reg [NUM_LAYERS-1:0] layer_start_reg;
    
    // Pipeline state
    reg pipeline_active;
    wire any_layer_busy;
    
    //==========================================================================
    // Layer Start Condition Logic
    //==========================================================================
    
    // Layer 0 (first layer) can start when:
    // - Network is enabled
    // - Input FIFO has data
    // - Layer is not busy
    assign layer_can_start[0] = network_enable && 
                               !input_fifo_empty && 
                               !layer_busy[0];
    
    // Generate start conditions for intermediate layers
    genvar i;
    generate
        for (i = 1; i < NUM_LAYERS; i = i + 1) begin : gen_layer_start
            assign layer_can_start[i] = network_enable && 
                                       !inter_fifo_empty[i-1] && 
                                       !layer_busy[i];
        end
    endgenerate
    
    // Determine which layers should start
    assign layer_should_start = layer_can_start;
    
    //==========================================================================
    // Layer Start Signal Generation
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || pipeline_reset) begin
            layer_start_reg <= {NUM_LAYERS{1'b0}};
        end else begin
            layer_start_reg <= layer_should_start;
        end
    end
    
    // Output layer start signals
    always @(*) begin
        layer_start = layer_start_reg;
    end
    
    //==========================================================================
    // Pipeline Status Logic
    //==========================================================================
    
    // Any layer is busy
    assign any_layer_busy = |layer_busy;
    
    // Pipeline is busy when at least one layer is processing
    assign pipeline_busy = any_layer_busy;
    
    // Pipeline is stalled when enabled but no layers are active
    assign pipeline_stalled = network_enable && !any_layer_busy;
    
    // Pipeline is ready when not busy and network is enabled
    assign pipeline_ready = network_enable && !pipeline_busy;
    
    //==========================================================================
    // Performance Monitoring
    //==========================================================================
    
    /*always @(posedge clk or negedge rst_n) begin
        if (!rst_n || pipeline_reset) begin
            pipeline_cycles <= 32'h0;
            stall_cycles <= 32'h0;
            active_cycles <= 32'h0;
        end else if (network_enable) begin
            pipeline_cycles <= pipeline_cycles + 1'b1;
            
            if (pipeline_stalled) begin
                stall_cycles <= stall_cycles + 1'b1;
            end
            
            if (pipeline_busy) begin
                active_cycles <= active_cycles + 1'b1;
            end
        end
    end*/

endmodule



//==============================================================================
// Master Controller for 3-Layer Pipelined Fully Connected Network
//==============================================================================
/*module master_controller #(
    parameter DATA_WIDTH = 16,
    parameter LAYER1_INPUT_SIZE = 784,   // Example: 28x28 image
    parameter LAYER1_OUTPUT_SIZE = 128,
    parameter LAYER2_INPUT_SIZE = 128,
    parameter LAYER2_OUTPUT_SIZE = 64,
    parameter LAYER3_INPUT_SIZE = 64,
    parameter LAYER3_OUTPUT_SIZE = 10    // Example: 10 classes
)(
    input wire clk,
    input wire rst_n,
    
    // Global control
    input wire start,
    output reg done,
    output wire busy,
    
    // Input interface (from external source)
    input wire input_valid,
    input wire [DATA_WIDTH-1:0] input_data,
    output reg input_ready,
    
    // Output interface (to external sink)
    output reg output_valid,
    output reg [DATA_WIDTH-1:0] output_data,
    input wire output_ready,
    
    // Layer control signals
    output wire layer1_start,
    output wire layer2_start, 
    output wire layer3_start,
    input wire layer1_done,
    input wire layer2_done,
    input wire layer3_done,
    input wire layer1_busy,
    input wire layer2_busy,
    input wire layer3_busy,
    
    // FIFO control signals
    input wire fifo1_full,
    input wire fifo1_empty,
    input wire fifo2_full,
    input wire fifo2_empty,
    input wire fifo3_full,
    input wire fifo3_empty,
    
    // Debug outputs
    output reg [2:0] master_state,
    output reg [15:0] input_count,
    output reg [15:0] output_count
);

    // State machine states
    localparam IDLE = 3'b000;
    localparam LOAD_DATA = 3'b001;
    localparam PROCESSING = 3'b010;
    localparam OUTPUT_DATA = 3'b011;
    localparam DONE_STATE = 3'b100;

    reg [2:0] state, next_state;
    reg [15:0] input_counter, output_counter;
    
    // Layer start control - each layer starts when previous layer has data available
    assign layer1_start = (state == LOAD_DATA) || (state == PROCESSING);
    assign layer2_start = !fifo1_empty || layer2_busy;  // Start when data available or already running
    assign layer3_start = !fifo2_empty || layer3_busy;  // Start when data available or already running
    
    assign busy = (state != IDLE) && (state != DONE_STATE);

    // State machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            input_counter <= 0;
            output_counter <= 0;
            done <= 0;
            input_ready <= 0;
            output_valid <= 0;
            output_data <= 0;
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    if (start) begin
                        input_counter <= 0;
                        output_counter <= 0;
                        done <= 0;
                        input_ready <= 1;
                    end
                end
                
                LOAD_DATA: begin
                    if (input_valid && input_ready) begin
                        input_counter <= input_counter + 1;
                        if (input_counter == LAYER1_INPUT_SIZE - 1) begin
                            input_ready <= 0;
                        end
                    end
                end
                
                PROCESSING: begin
                    // Wait for all layers to complete processing
                    // and all intermediate FIFOs to be processed
                end
                
                OUTPUT_DATA: begin
                    // Handle output data from final FIFO
                    if (!fifo3_empty && output_ready) begin
                        output_valid <= 1;
                        output_counter <= output_counter + 1;
                        if (output_counter == LAYER3_OUTPUT_SIZE - 1) begin
                            output_valid <= 0;
                        end
                    end
                end
                
                DONE_STATE: begin
                    done <= 1;
                    if (!start) begin
                        done <= 0;
                    end
                end
            endcase
        end
    end

    // Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) begin
                    next_state = LOAD_DATA;
                end
            end
            
            LOAD_DATA: begin
                if (input_counter == LAYER1_INPUT_SIZE - 1 && input_valid && input_ready) begin
                    next_state = PROCESSING;
                end
            end
            
            PROCESSING: begin
                // Move to output when final layer starts producing results
                if (!fifo3_empty) begin
                    next_state = OUTPUT_DATA;
                end
            end
            
            OUTPUT_DATA: begin
                if (output_counter == LAYER3_OUTPUT_SIZE - 1 && !fifo3_empty && output_ready) begin
                    next_state = DONE_STATE;
                end
            end
            
            DONE_STATE: begin
                if (!start) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Debug outputs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            master_state <= IDLE;
            input_count <= 0;
            output_count <= 0;
        end else begin
            master_state <= state;
            input_count <= input_counter;
            output_count <= output_counter;
        end
    end

endmodule*/

