module Accum_Subsystem #(    
    parameter FIFO_DEPTH = 4,
    parameter NUM_BANKS  = 4,
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 64,
    parameter ZONE_WIDTH = 2,
    parameter NUM_ROUTED_MASTERS = 1
)(
    input logic clk,
    input logic rstn,

    // 需要经过 Router 的 Master 接口 (e.g. DMA)
    Accum_Cmd_If.Slave   routed_cmd_ports  [NUM_ROUTED_MASTERS],
    Accum_Data_If.Slave  routed_data_ports [NUM_ROUTED_MASTERS],

    // 直接连接到特定 Zone 的 Master 接口 (e.g. 直连的计算单元)
    // 假设有 4 个 Zone，每个 Zone 有一个直连口
    Accum_Cmd_If.Slave   direct_cmd_ports  [4],
    Accum_Data_If.Slave  direct_data_ports [4]
);
    
    // 每个 Zone 的插槽数 = 1个直连 + N个路由
    localparam SLOTS_PER_ZONE  = 1 + NUM_ROUTED_MASTERS;

    // ========================================================================
    // 1. Router 实例化与互联
    // ========================================================================
    
    // 定义 Router 的输出接口 (Master 侧)：[Master ID][Dest Zone ID]
    Accum_Cmd_If  router_m_cmd_ports  [NUM_ROUTED_MASTERS][4] (clk, rstn);
    Accum_Data_If router_m_data_ports [NUM_ROUTED_MASTERS][4] (clk, rstn);

    genvar z;
    generate
        for (z = 0; z < NUM_ROUTED_MASTERS; z++) begin : gen_routers
            Accum_Router #(
                .NUM_ZONES  (4),
                .ZONE_WIDTH (ZONE_WIDTH),
                .NUM_BANKS  (NUM_BANKS),
                .DATA_WIDTH (DATA_WIDTH),
                .ADDR_WIDTH (ADDR_WIDTH)
            ) u_router (
                .clk      (clk),
                .rstn     (rstn),
                // 【优化】：直接连接外部 Slave 接口，移除冗余中间层
                .s_cmd    (routed_cmd_ports[z]),
                .s_data   (routed_data_ports[z]),
                // 输出连接到中间接口数组
                .m_cmd    (router_m_cmd_ports[z]),
                .m_data   (router_m_data_ports[z])
            );
        end
    endgenerate

    // ========================================================================
    // 2. Zone 输入聚合 (Aggregation / Matrix Transpose)
    // ========================================================================
    
    // 定义 Zone 的输入聚合接口：[Zone ID][Slot ID]
    Accum_Cmd_If  zone_in_cmd_ports  [4][SLOTS_PER_ZONE] (clk, rstn);
    Accum_Data_If zone_in_data_ports [4][SLOTS_PER_ZONE] (clk, rstn);

    genvar d; // Destination Zone ID
    generate
        for (d = 0; d < 4; d++) begin : gen_zone_wiring
            
            // ----------------------------------------------------
            // Slot 0: 直连端口 (Direct Port)
            // ----------------------------------------------------
            always_comb begin
                // Forward: Direct(Slave) -> ZoneIn(Master view)
                zone_in_cmd_ports[d][0].wr_valid   = direct_cmd_ports[d].wr_valid;
                zone_in_cmd_ports[d][0].wr_zone_id = direct_cmd_ports[d].wr_zone_id;
                zone_in_cmd_ports[d][0].accum_en   = direct_cmd_ports[d].accum_en;
                zone_in_cmd_ports[d][0].wr_mask    = direct_cmd_ports[d].wr_mask;
                zone_in_cmd_ports[d][0].wr_addr    = direct_cmd_ports[d].wr_addr;
                
                zone_in_cmd_ports[d][0].rd_valid   = direct_cmd_ports[d].rd_valid;
                zone_in_cmd_ports[d][0].rd_zone_id = direct_cmd_ports[d].rd_zone_id;
                zone_in_cmd_ports[d][0].rd_mask    = direct_cmd_ports[d].rd_mask;
                zone_in_cmd_ports[d][0].rd_addr    = direct_cmd_ports[d].rd_addr;

                zone_in_data_ports[d][0].wvalid    = direct_data_ports[d].wvalid;
                zone_in_data_ports[d][0].wdata     = direct_data_ports[d].wdata;

                // Backward: ZoneIn(Master view) -> Direct(Slave)
                direct_cmd_ports[d].wr_ready       = zone_in_cmd_ports[d][0].wr_ready;
                direct_cmd_ports[d].rd_ready       = zone_in_cmd_ports[d][0].rd_ready;
                direct_data_ports[d].wready        = zone_in_data_ports[d][0].wready;
                direct_data_ports[d].rvalid        = zone_in_data_ports[d][0].rvalid;
                direct_data_ports[d].rdata         = zone_in_data_ports[d][0].rdata;
            end

            // ----------------------------------------------------
            // Slot 1..N: 来自 Routers 的连接 (Matrix Transpose)
            // Router[z] 的第 [d] 个输出 -> Zone[d] 的第 [z+1] 个 Slot
            // ----------------------------------------------------
            for (z = 0; z < NUM_ROUTED_MASTERS; z++) begin : gen_router_slots
                always_comb begin
                    // Forward: RouterOut -> ZoneIn
                    zone_in_cmd_ports[d][z+1].wr_valid   = router_m_cmd_ports[z][d].wr_valid;
                    zone_in_cmd_ports[d][z+1].wr_zone_id = router_m_cmd_ports[z][d].wr_zone_id;
                    zone_in_cmd_ports[d][z+1].accum_en   = router_m_cmd_ports[z][d].accum_en;
                    zone_in_cmd_ports[d][z+1].wr_mask    = router_m_cmd_ports[z][d].wr_mask;
                    zone_in_cmd_ports[d][z+1].wr_addr    = router_m_cmd_ports[z][d].wr_addr;

                    zone_in_cmd_ports[d][z+1].rd_valid   = router_m_cmd_ports[z][d].rd_valid;
                    zone_in_cmd_ports[d][z+1].rd_zone_id = router_m_cmd_ports[z][d].rd_zone_id;
                    zone_in_cmd_ports[d][z+1].rd_mask    = router_m_cmd_ports[z][d].rd_mask;
                    zone_in_cmd_ports[d][z+1].rd_addr    = router_m_cmd_ports[z][d].rd_addr;

                    zone_in_data_ports[d][z+1].wvalid    = router_m_data_ports[z][d].wvalid;
                    zone_in_data_ports[d][z+1].wdata     = router_m_data_ports[z][d].wdata;

                    // Backward: ZoneIn -> RouterOut
                    router_m_cmd_ports[z][d].wr_ready    = zone_in_cmd_ports[d][z+1].wr_ready;
                    router_m_cmd_ports[z][d].rd_ready    = zone_in_cmd_ports[d][z+1].rd_ready;
                    router_m_data_ports[z][d].wready     = zone_in_data_ports[d][z+1].wready;
                    router_m_data_ports[z][d].rvalid     = zone_in_data_ports[d][z+1].rvalid;
                    router_m_data_ports[z][d].rdata      = zone_in_data_ports[d][z+1].rdata;
                end
            end

            // ----------------------------------------------------
            // 3. Zone 实例化
            // ----------------------------------------------------
            Accum_Zone #(
                .NUM_SLOTS  (SLOTS_PER_ZONE),
                .FIFO_DEPTH (FIFO_DEPTH),
                .NUM_BANKS  (NUM_BANKS),
                .DATA_WIDTH (DATA_WIDTH),
                .ADDR_WIDTH (ADDR_WIDTH),
                .ZONE_WIDTH (ZONE_WIDTH)
            ) u_zone (
                .clk  (clk),
                .rstn (rstn),
                // 传入聚合好的一维接口数组 (对应当前 Zone 的所有 Slot)
                .slave_cmd_ports  (zone_in_cmd_ports[d]), 
                .slave_data_ports (zone_in_data_ports[d])
            );
        end
    endgenerate

endmodule