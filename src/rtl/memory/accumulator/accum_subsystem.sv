module Accum_Subsystem #(
    parameter FIFO_DEPTH         = 4,
    parameter NUM_BANKS          = 4,
    parameter ADDR_WIDTH         = 9,
    parameter DATA_WIDTH         = 64,
    parameter ZONE_WIDTH         = 2,
    parameter NUM_ROUTED_MASTERS = 1
)(
    input  logic clk,
    input  logic rstn,

    // ============================================================
    // IMPORTANT: Top-level interfaces use NO modport!
    // This allows Router to connect via .Slave and Zone via .Slave.
    // ============================================================
    Accum_Cmd_If  routed_cmd_ports  [NUM_ROUTED_MASTERS],
    Accum_Data_If routed_data_ports [NUM_ROUTED_MASTERS],

    Accum_Cmd_If  direct_cmd_ports  [(1<<ZONE_WIDTH)],
    Accum_Data_If direct_data_ports [(1<<ZONE_WIDTH)]
);

    localparam NUM_ZONES      = (1 << ZONE_WIDTH);
    localparam SLOTS_PER_ZONE = 1 + NUM_ROUTED_MASTERS;  // slot0 = direct


    // ============================================================
    // Router Output Interfaces
    // ============================================================
    Accum_Cmd_If #(.NUM_BANKS(NUM_BANKS), .ADDR_WIDTH(ADDR_WIDTH), .ZONE_WIDTH(ZONE_WIDTH))
        router_m_cmd_ports  [NUM_ROUTED_MASTERS][NUM_ZONES] (clk, rstn);

    Accum_Data_If #(.NUM_BANKS(NUM_BANKS), .DATA_WIDTH(DATA_WIDTH))
        router_m_data_ports [NUM_ROUTED_MASTERS][NUM_ZONES] (clk, rstn);


    // ============================================================
    // Routers
    // ============================================================
    genvar rm;
    generate
        for (rm = 0; rm < NUM_ROUTED_MASTERS; rm++) begin : gen_router

            Accum_Router #(
                .NUM_ZONES  (NUM_ZONES),
                .ZONE_WIDTH (ZONE_WIDTH),
                .NUM_BANKS  (NUM_BANKS),
                .DATA_WIDTH (DATA_WIDTH),
                .ADDR_WIDTH (ADDR_WIDTH)
            ) u_router (
                .clk    (clk),
                .rstn   (rstn),

                // Router input MUST use .Slave
                .s_cmd  (routed_cmd_ports[rm].Slave),
                .s_data (routed_data_ports[rm].Slave),

                // Router output is .Master (array)
                .m_cmd  (router_m_cmd_ports[rm]),
                .m_data (router_m_data_ports[rm])
            );

        end
    endgenerate


    // ============================================================
    // Zone Slot Matrix
    // ============================================================
    Accum_Cmd_If #(.NUM_BANKS(NUM_BANKS), .ADDR_WIDTH(ADDR_WIDTH), .ZONE_WIDTH(ZONE_WIDTH))
        zone_in_cmd  [NUM_ZONES][SLOTS_PER_ZONE] (clk, rstn);

    Accum_Data_If #(.NUM_BANKS(NUM_BANKS), .DATA_WIDTH(DATA_WIDTH))
        zone_in_data [NUM_ZONES][SLOTS_PER_ZONE] (clk, rstn);


    // ============================================================
    // Direct Masters → Slot0
    // ============================================================
    genvar z;
    generate
        for (z = 0; z < NUM_ZONES; z++) begin : gen_direct

            // Forward direct → zone slot0
            assign zone_in_cmd[z][0].wr_valid   = direct_cmd_ports[z].wr_valid;
            assign zone_in_cmd[z][0].wr_zone_id = direct_cmd_ports[z].wr_zone_id;
            assign zone_in_cmd[z][0].accum_en   = direct_cmd_ports[z].accum_en;
            assign zone_in_cmd[z][0].wr_mask    = direct_cmd_ports[z].wr_mask;
            assign zone_in_cmd[z][0].wr_addr    = direct_cmd_ports[z].wr_addr;

            assign zone_in_cmd[z][0].rd_valid   = direct_cmd_ports[z].rd_valid;
            assign zone_in_cmd[z][0].rd_zone_id = direct_cmd_ports[z].rd_zone_id;
            assign zone_in_cmd[z][0].rd_mask    = direct_cmd_ports[z].rd_mask;
            assign zone_in_cmd[z][0].rd_addr    = direct_cmd_ports[z].rd_addr;

            assign zone_in_data[z][0].wvalid = direct_data_ports[z].wvalid;
            assign zone_in_data[z][0].wdata  = direct_data_ports[z].wdata;

            // Backward (Zone → Master)
            assign direct_cmd_ports[z].wr_ready = zone_in_cmd[z][0].wr_ready;
            assign direct_cmd_ports[z].rd_ready = zone_in_cmd[z][0].rd_ready;

            assign direct_data_ports[z].wready = zone_in_data[z][0].wready;
            assign direct_data_ports[z].rvalid = zone_in_data[z][0].rvalid;
            assign direct_data_ports[z].rdata  = zone_in_data[z][0].rdata;

        end
    endgenerate


    // ============================================================
    // Routed Masters → Slot 1..N
    // ============================================================
    genvar s;
    generate
        for (z = 0; z < NUM_ZONES; z++) begin : gen_routed
            for (s = 0; s < NUM_ROUTED_MASTERS; s++) begin : gen_rslot

                // FW routed → slot
                assign zone_in_cmd[z][s+1].wr_valid   = router_m_cmd_ports[s][z].wr_valid;
                assign zone_in_cmd[z][s+1].wr_zone_id = router_m_cmd_ports[s][z].wr_zone_id;
                assign zone_in_cmd[z][s+1].accum_en   = router_m_cmd_ports[s][z].accum_en;
                assign zone_in_cmd[z][s+1].wr_mask    = router_m_cmd_ports[s][z].wr_mask;
                assign zone_in_cmd[z][s+1].wr_addr    = router_m_cmd_ports[s][z].wr_addr;

                assign zone_in_cmd[z][s+1].rd_valid   = router_m_cmd_ports[s][z].rd_valid;
                assign zone_in_cmd[z][s+1].rd_zone_id = router_m_cmd_ports[s][z].rd_zone_id;
                assign zone_in_cmd[z][s+1].rd_mask    = router_m_cmd_ports[s][z].rd_mask;
                assign zone_in_cmd[z][s+1].rd_addr    = router_m_cmd_ports[s][z].rd_addr;

                assign zone_in_data[z][s+1].wvalid = router_m_data_ports[s][z].wvalid;
                assign zone_in_data[z][s+1].wdata  = router_m_data_ports[s][z].wdata;

                // BW (Zone → Router)
                assign router_m_cmd_ports[s][z].wr_ready = zone_in_cmd[z][s+1].wr_ready;
                assign router_m_cmd_ports[s][z].rd_ready = zone_in_cmd[z][s+1].rd_ready;

                assign router_m_data_ports[s][z].wready = zone_in_data[z][s+1].wready;
                assign router_m_data_ports[s][z].rvalid = zone_in_data[z][s+1].rvalid;
                assign router_m_data_ports[s][z].rdata  = zone_in_data[z][s+1].rdata;

            end
        end
    endgenerate


    // ============================================================
    // Instantiate Zones
    // ============================================================
    generate
        for (z = 0; z < NUM_ZONES; z++) begin : gen_zone

            Accum_Zone #(
                .NUM_SLOTS  (SLOTS_PER_ZONE),
                .FIFO_DEPTH (FIFO_DEPTH),
                .NUM_BANKS  (NUM_BANKS),
                .DATA_WIDTH (DATA_WIDTH),
                .ADDR_WIDTH (ADDR_WIDTH),
                .ZONE_WIDTH (ZONE_WIDTH)
            ) u_zone (
                .clk              (clk),
                .rstn             (rstn),
                .slave_cmd_ports  (zone_in_cmd[z]),
                .slave_data_ports (zone_in_data[z])
            );

        end
    endgenerate

endmodule
