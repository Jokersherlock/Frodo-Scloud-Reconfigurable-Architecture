module Accum_Router #(
    parameter NUM_ZONES  = 4,
    parameter ZONE_WIDTH = 2,
    // 辅助参数，用于计算数据位宽
    parameter NUM_BANKS  = 4,
    parameter DATA_WIDTH = 64
)(
    input logic clk,
    input logic rstn,

    // Slave Port (from Master)
    Accum_Cmd_If.Slave   s_cmd,
    Accum_Data_If.Slave  s_data,

    // Master Ports (to Zones)
    Accum_Cmd_If.Master  m_cmd  [NUM_ZONES],
    Accum_Data_If.Master m_data [NUM_ZONES]
);

    // =================================================================
    // 1. 定义中间信号数组 (用于反向路径解包)
    //    这是为了让我们可以用 s_cmd.wr_zone_id 来动态索引它们
    // =================================================================
    logic [NUM_ZONES-1:0] zone_wr_ready_vec;
    logic [NUM_ZONES-1:0] zone_rd_ready_vec;
    logic [NUM_ZONES-1:0] zone_wdata_ready_vec;
    
    logic [NUM_ZONES-1:0] zone_rvalid_vec;
    logic [NUM_ZONES-1:0][NUM_BANKS-1:0][DATA_WIDTH-1:0] zone_rdata_vec;


    // =================================================================
    // 2. 前向驱动 & 反向采集 (使用 Generate)
    // =================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_ZONES; i++) begin : router_logic
            
            // --- A. 前向驱动 (Forward Drive: Master -> Zones) ---
            // 这是一个 1-to-N 的解复用 (Demux) 逻辑
            // 必须在 generate 块里赋值，因为 m_cmd[i] 只能静态索引
            
            always_comb begin
                // 1. 静态信号广播 (直接连过去)
                m_cmd[i].wr_zone_id = s_cmd.wr_zone_id;
                m_cmd[i].accum_en   = s_cmd.accum_en;
                m_cmd[i].wr_mask    = s_cmd.wr_mask;
                m_cmd[i].wr_addr    = s_cmd.wr_addr;
                
                m_cmd[i].rd_zone_id = s_cmd.rd_zone_id;
                m_cmd[i].rd_mask    = s_cmd.rd_mask;
                m_cmd[i].rd_addr    = s_cmd.rd_addr;
                
                m_data[i].wdata     = s_data.wdata; // 数据广播

                // 2. 动态 Valid 门控 (Routing)
                // 只有目标 ID 匹配的 Zone 才会收到 Valid=1
                
                // 写通道
                if (s_cmd.wr_zone_id == i[ZONE_WIDTH-1:0]) begin
                    m_cmd[i].wr_valid = s_cmd.wr_valid;
                    m_data[i].wvalid  = s_data.wvalid;
                end else begin
                    m_cmd[i].wr_valid = 1'b0;
                    m_data[i].wvalid  = 1'b0;
                end

                // 读通道
                if (s_cmd.rd_zone_id == i[ZONE_WIDTH-1:0]) begin
                    m_cmd[i].rd_valid = s_cmd.rd_valid;
                end else begin
                    m_cmd[i].rd_valid = 1'b0;
                end
            end

            // --- B. 反向采集 (Backward Unpack: Zones -> Vector) ---
            // 将 Interface 里的反馈信号提取到普通 logic 数组中
            assign zone_wr_ready_vec[i]    = m_cmd[i].wr_ready;
            assign zone_rd_ready_vec[i]    = m_cmd[i].rd_ready;
            assign zone_wdata_ready_vec[i] = m_data[i].wready;
            assign zone_rvalid_vec[i]      = m_data[i].rvalid;
            assign zone_rdata_vec[i]       = m_data[i].rdata;

        end
    endgenerate


    // =================================================================
    // 3. 反向反馈 (Backward Muxing: Vectors -> Master)
    //    现在我们可以使用动态 ID 安全地索引 Vector 了
    // =================================================================
    
    always_comb begin
        // --- A. 握手信号 Mux ---
        // Master 看到的 Ready 取决于它当前想去哪 (target_id)
        s_cmd.wr_ready = zone_wr_ready_vec[s_cmd.wr_zone_id];
        s_cmd.rd_ready = zone_rd_ready_vec[s_cmd.rd_zone_id];
        
        // 写数据的 Ready 通常跟随 Write ID
        s_data.wready  = zone_wdata_ready_vec[s_cmd.wr_zone_id];

        // --- B. 读数据返回聚合 ---
        // 任何一个 Zone 返回数据，都透传给 Master。
        // 这里使用简单的轮询/或逻辑，因为对于单一 Master，同一时刻理论上只有一个 Zone 会回数据
        s_data.rvalid = 1'b0;
        s_data.rdata  = '0;

        for (int k = 0; k < NUM_ZONES; k++) begin
            if (zone_rvalid_vec[k]) begin
                s_data.rvalid = 1'b1;
                s_data.rdata  = zone_rdata_vec[k];
            end
        end
    end

endmodule