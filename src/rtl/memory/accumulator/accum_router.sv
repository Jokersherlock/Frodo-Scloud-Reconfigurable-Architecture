module Accum_Router #(
    parameter NUM_ZONES  = 4,
    parameter ZONE_WIDTH = 2,
    // 辅助参数
    parameter NUM_BANKS  = 4,
    parameter DATA_WIDTH = 64,
    parameter ADDR_WIDTH = 9    // 【修正】：补上缺失的 ADDR_WIDTH 参数
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
    // 1. Payload 定义 (将所有前向信号打包，用于过 Buffer)
    // =================================================================
    
    // 写通道 Payload (包含 Command 和 WData)
    typedef struct packed {
        logic [ZONE_WIDTH-1:0]                  zone_id;
        logic                                   accum_en;
        logic [NUM_BANKS-1:0]                   mask;
        logic [ADDR_WIDTH-1:0]                  addr;
        logic [NUM_BANKS-1:0][DATA_WIDTH-1:0]   wdata; // 256 bits of data
    } wr_payload_t;

    // 读通道 Payload (只包含 Command)
    typedef struct packed {
        logic [ZONE_WIDTH-1:0]  zone_id;
        logic [NUM_BANKS-1:0]   mask;
        logic [ADDR_WIDTH-1:0]  addr;
    } rd_payload_t;

    // =================================================================
    // 2. 内部信号定义
    // =================================================================
    
    // Skid Buffer 输入
    logic [NUM_ZONES-1:0] wr_valid_in_vec;
    wr_payload_t          s_wr_payload;

    logic [NUM_ZONES-1:0] rd_valid_in_vec;
    rd_payload_t          s_rd_payload;

    // 反向 Ready 信号
    logic [NUM_ZONES-1:0] skid_wr_ready_vec; // 之前报错是因为上面的 struct 报错导致解析中断
    logic [NUM_ZONES-1:0] skid_rd_ready_vec;


    // =================================================================
    // 3. 组合逻辑路由 (Pre-Buffer Logic)
    // =================================================================
    
    // --- 3.1 准备 Payload ---
    always_comb begin
        s_wr_payload.zone_id  = s_cmd.wr_zone_id;
        s_wr_payload.accum_en = s_cmd.accum_en;
        s_wr_payload.mask     = s_cmd.wr_mask;
        s_wr_payload.addr     = s_cmd.wr_addr;
        s_wr_payload.wdata    = s_data.wdata;

        s_rd_payload.zone_id  = s_cmd.rd_zone_id;
        s_rd_payload.mask     = s_cmd.rd_mask;
        s_rd_payload.addr     = s_cmd.rd_addr;
    end

    // --- 3.2 Valid Demux ---
    always_comb begin
        for (int i = 0; i < NUM_ZONES; i++) begin
            // 写通道 Demux
            wr_valid_in_vec[i] = (s_cmd.wr_zone_id == i[ZONE_WIDTH-1:0]) ? (s_cmd.wr_valid && s_data.wvalid) : 1'b0;
            // 读通道 Demux
            rd_valid_in_vec[i] = (s_cmd.rd_zone_id == i[ZONE_WIDTH-1:0]) ? s_cmd.rd_valid : 1'b0;
        end
    end

    // =================================================================
    // 4. 实例化 Skid Buffers (Pipeline Stage)
    // =================================================================
    
    // 收集反向数据
    logic [NUM_ZONES-1:0] zone_rvalid_vec;
    logic [NUM_ZONES-1:0][NUM_BANKS-1:0][DATA_WIDTH-1:0] zone_rdata_vec;

    genvar z;
    generate
        for (z = 0; z < NUM_ZONES; z++) begin : gen_skid
            
            wr_payload_t wr_payload_out;
            rd_payload_t rd_payload_out;

            // -------------------
            // 4.1 写通道 Skid Buffer
            // -------------------
            Skid_Buffer #(
                .DATA_WIDTH($bits(wr_payload_t)) 
            ) u_wr_skid (
                .clk     (clk), .rstn(rstn),
                // Input
                .s_valid (wr_valid_in_vec[z]),
                .s_ready (skid_wr_ready_vec[z]), 
                .s_data  (s_wr_payload),
                // Output
                .m_valid (m_cmd[z].wr_valid), 
                .m_ready (m_cmd[z].wr_ready),
                .m_data  (wr_payload_out)
            );

            // 解包赋值 Control/Data
            assign m_cmd[z].wr_zone_id = wr_payload_out.zone_id;
            assign m_cmd[z].accum_en   = wr_payload_out.accum_en;
            assign m_cmd[z].wr_mask    = wr_payload_out.mask;
            assign m_cmd[z].wr_addr    = wr_payload_out.addr;
            
            assign m_data[z].wvalid    = m_cmd[z].wr_valid; 
            assign m_data[z].wdata     = wr_payload_out.wdata;


            // -------------------
            // 4.2 读通道 Skid Buffer
            // -------------------
            Skid_Buffer #(
                .DATA_WIDTH($bits(rd_payload_t))
            ) u_rd_skid (
                .clk     (clk), .rstn(rstn),
                .s_valid (rd_valid_in_vec[z]),
                .s_ready (skid_rd_ready_vec[z]),
                .s_data  (s_rd_payload),
                .m_valid (m_cmd[z].rd_valid),
                .m_ready (m_cmd[z].rd_ready),
                .m_data  (rd_payload_out)
            );

            // 解包赋值
            assign m_cmd[z].rd_zone_id = rd_payload_out.zone_id;
            assign m_cmd[z].rd_mask    = rd_payload_out.mask;
            assign m_cmd[z].rd_addr    = rd_payload_out.addr;

            // -------------------
            // 4.3 反向数据采集
            // -------------------
            assign zone_rvalid_vec[z] = m_data[z].rvalid;
            assign zone_rdata_vec[z]  = m_data[z].rdata;

        end
    endgenerate


    // =================================================================
    // 5. 反向反馈 (Backward Muxing)
    // =================================================================

    always_comb begin
        // --- A. Ready 信号选择 (Mux) ---
        s_cmd.wr_ready = skid_wr_ready_vec[s_cmd.wr_zone_id];
        s_data.wready  = skid_wr_ready_vec[s_cmd.wr_zone_id]; 
        
        s_cmd.rd_ready = skid_rd_ready_vec[s_cmd.rd_zone_id];

        // --- B. 读数据返回聚合 (Mux) ---
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