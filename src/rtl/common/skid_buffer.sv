/*
 * Module: Skid_Buffer
 * Description: 
 * A pipeline register that supports valid/ready handshake protocols.
 * It provides timing isolation by breaking the combinational path 
 * between s_ready and m_ready.
 * * - Capacity: 1 data item (essentially a 2-deep FIFO behavior during backpressure).
 * - Latency: 1 cycle.
 * - Throughput: 1 item per cycle (Full bandwidth).
 */

module Skid_Buffer #(
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic rstn,

    // Slave Interface (Input from Upstream)
    input  logic                  s_valid,
    output logic                  s_ready,
    input  logic [DATA_WIDTH-1:0] s_data,

    // Master Interface (Output to Downstream)
    output logic                  m_valid,
    input  logic                  m_ready,
    output logic [DATA_WIDTH-1:0] m_data
);

    // =================================================================
    // Internal Signals
    // =================================================================
    // State: 0 = RUN (Transparent/Pipe), 1 = SKID (Buffer Full)
    logic state;
    
    // The "Skid" storage (Secondary buffer)
    logic [DATA_WIDTH-1:0] buffer;

    // =================================================================
    // Main Logic
    // =================================================================
    
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state   <= 1'b0;
            buffer  <= '0;
            m_valid <= 1'b0;
            m_data  <= '0;
        end else begin
            case (state)
                // -----------------------------------------------------
                // State 0: RUN Mode
                // Normal pipeline operation. Data moves to output reg.
                // -----------------------------------------------------
                1'b0: begin
                    if (s_valid) begin
                        // Condition: Upstream sending data
                        
                        if (m_ready || !m_valid) begin
                            // Case A: Downstream is ready (or output is empty)
                            // Action: Pass data directly to output register (Pipeline)
                            m_valid <= 1'b1;
                            m_data  <= s_data;
                            state   <= 1'b0; // Stay in RUN
                        end else begin
                            // Case B: Downstream is NOT ready (Backpressure!)
                            // Action: We must capture this data to avoid losing it,
                            //         but we can't overwrite m_data yet.
                            //         So, save it to the 'buffer'.
                            buffer  <= s_data;
                            state   <= 1'b1; // Go to SKID
                            
                            // Keep m_valid/m_data stable for downstream
                        end
                    end else if (m_ready) begin
                        // Case C: No input, but downstream accepted old data
                        // Action: Output becomes empty
                        m_valid <= 1'b0;
                    end
                end

                // -----------------------------------------------------
                // State 1: SKID Mode
                // We have data in 'buffer' waiting to move to 'm_data'
                // -----------------------------------------------------
                1'b1: begin
                    if (m_ready) begin
                        // Condition: Downstream finally accepts the old m_data
                        
                        // Action: Move 'buffer' (the skidded data) to output
                        m_valid <= 1'b1;
                        m_data  <= buffer;
                        
                        // Check if Upstream is sending NEW data simultaneously
                        if (s_valid) begin
                            // Optimisation: Fill buffer immediately with new data
                            // State stays SKID
                            buffer <= s_data; 
                        end else begin
                            // No new data, buffer is drained
                            state <= 1'b0; // Back to RUN
                        end
                    end
                    // If !m_ready, we are stuck here.
                    // s_ready will be 0, blocking upstream.
                end
            endcase
        end
    end

    // =================================================================
    // Ready Logic
    // =================================================================
    // We are ready if:
    // 1. We are in RUN mode (Buffer is empty), OR
    // 2. We are in SKID mode BUT downstream is ready (we can drain buffer)
    //
    // Note: This effectively registers the ready signal in the skidding case,
    // breaking the timing loop.
    assign s_ready = (state == 1'b0) || m_ready;

endmodule