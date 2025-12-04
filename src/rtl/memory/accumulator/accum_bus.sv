module Accum_Bus #(
    parameter NUM_SLOTS  = 2,   // 连接的主设备数量 (通常是 DMA + Frodo)
    parameter FIFO_DEPTH = 4,   // 写缓冲深度
    parameter NUM_BANKS  = 4,   // SIMD Bank 数量
    parameter DATA_WIDTH = 64,  // 单个 Bank 的位宽
    parameter ADDR_WIDTH = 9,
    parameter ZONE_WIDTH = 2
)(
    input logic clk,
    input logic rstn,

    // =======================================================
    // 上行接口：连接 Masters (Slot 0, Slot 1...)
    // =======================================================
    Accum_Cmd_If   cmd_slots  [NUM_SLOTS],
    Accum_Data_If  data_slots [NUM_SLOTS],

    // =======================================================
    // 下行接口：连接 Physical Wrapper
    // =======================================================
    Accum_Cmd_If.Master  phy_cmd_if,
    Accum_Data_If.Master phy_data_if
);

    // =======================================================
    // Part A: 信号解包 (Unpack Inputs)
    // 将 Interface 数组转换为 Logic 数组，方便索引
    // =======================================================
    
    // --- 写通道信号 ---
    logic [NUM_SLOTS-1:0]       wr_valid_vec;
    logic [NUM_SLOTS-1:0]       wr_accum_en_vec;
    logic [NUM_SLOTS-1:0][NUM_BANKS-1:0] wr_mask_vec;
    logic [NUM_SLOTS-1:0][ADDR_WIDTH-1:0] wr_addr_vec;
    
    logic [NUM_SLOTS-1:0]       data_wvalid_vec;
    logic [NUM_SLOTS-1:0][NUM_BANKS-1:0][DATA_WIDTH-1:0] data_wdata_vec; 

    // --- 读通道信号 ---
    logic [NUM_SLOTS-1:0]       rd_valid_vec;
    logic [NUM_SLOTS-1:0][NUM_BANKS-1:0] rd_mask_vec;
    logic [NUM_SLOTS-1:0][ADDR_WIDTH-1:0] rd_addr_vec;

    genvar g;
    generate
        for (g = 0; g < NUM_SLOTS; g++) begin : unpack_inputs
            // Write Command
            assign wr_valid_vec[g]    = cmd_slots[g].wr_valid;
            assign wr_accum_en_vec[g] = cmd_slots[g].accum_en;
            assign wr_mask_vec[g]     = cmd_slots[g].wr_mask;
            assign wr_addr_vec[g]     = cmd_slots[g].wr_addr;
            
            // Read Command
            assign rd_valid_vec[g]    = cmd_slots[g].rd_valid;
            assign rd_mask_vec[g]     = cmd_slots[g].rd_mask;
            assign rd_addr_vec[g]     = cmd_slots[g].rd_addr;

            // Write Data
            assign data_wvalid_vec[g] = data_slots[g].wvalid;
            assign data_wdata_vec[g]  = data_slots[g].wdata;
        end
    endgenerate


    // ########################################################################
    //                          SECTION 1: 写通道逻辑
    //                  (Write Arbitration & Command FIFO)
    // ########################################################################

    // --- 1.1 写优先级仲裁 (Write Arbiter) ---
    logic [$clog2(NUM_SLOTS)-1:0] wr_winner_id;
    logic                         wr_winner_valid;

    always_comb begin
        wr_winner_id = 0;      
        wr_winner_valid = 1'b0;
        for (int i = 0; i < NUM_SLOTS; i++) begin
            if (wr_valid_vec[i]) begin
                wr_winner_id = i[$clog2(NUM_SLOTS)-1:0];    
                wr_winner_valid = 1'b1;
                break; 
            end
        end
    end

    // --- 1.2 选出写赢家的信号 ---
    logic       win_accum_en;
    logic [NUM_BANKS-1:0] win_wr_mask;
    logic [ADDR_WIDTH-1:0] win_wr_addr;

    assign win_accum_en = wr_accum_en_vec[wr_winner_id];
    assign win_wr_mask  = wr_mask_vec[wr_winner_id];
    assign win_wr_addr  = wr_addr_vec[wr_winner_id];

    // --- 1.3 写指令 FIFO (存储 Cmd 等待 Data) ---
    typedef struct packed {
        logic [$clog2(NUM_SLOTS)-1:0] src_id;
        logic                         accum_en;
        logic [NUM_BANKS-1:0]         mask;
        logic [ADDR_WIDTH-1:0]        addr;
    } wr_cmd_entry_t;

    wr_cmd_entry_t wr_fifo_din, wr_fifo_dout;
    logic wr_fifo_push, wr_fifo_pop;
    logic wr_fifo_full, wr_fifo_empty;

    FIFO #(
        .WIDTH($bits(wr_cmd_entry_t)), .DEPTH(FIFO_DEPTH)
    ) u_wr_cmd_fifo (
        .clk(clk), .rstn(rstn),
        .push(wr_fifo_push), .din(wr_fifo_din),
        .pop(wr_fifo_pop),   .dout(wr_fifo_dout),
        .full(wr_fifo_full), .empty(wr_fifo_empty)
    );

    // 入队逻辑
    assign wr_fifo_din.src_id   = wr_winner_id;
    assign wr_fifo_din.accum_en = win_accum_en;
    assign wr_fifo_din.mask     = win_wr_mask;
    assign wr_fifo_din.addr     = win_wr_addr;
    assign wr_fifo_push         = wr_winner_valid && !wr_fifo_full; // 只要 FIFO 没满就收

    // 出队逻辑：FIFO 不空且对应的数据已到达
    logic wr_data_arrived;
    assign wr_data_arrived = data_wvalid_vec[wr_fifo_dout.src_id];
    assign wr_fifo_pop     = !wr_fifo_empty && wr_data_arrived;


    // ########################################################################
    //                          SECTION 2: 读通道逻辑
    //                  (Read Arbitration & ID Tracking FIFO)
    // ########################################################################

    // --- 2.1 读优先级仲裁 (Read Arbiter) ---
    logic [$clog2(NUM_SLOTS)-1:0] rd_winner_id;
    logic                         rd_winner_valid;

    always_comb begin
        rd_winner_id = 0;      
        rd_winner_valid = 1'b0;
        for (int i = 0; i < NUM_SLOTS; i++) begin
            if (rd_valid_vec[i]) begin
                rd_winner_id = i[$clog2(NUM_SLOTS)-1:0];    
                rd_winner_valid = 1'b1;
                break; 
            end
        end
    end

    // --- 2.2 选出读赢家的信号 ---
    logic [NUM_BANKS-1:0] win_rd_mask;
    logic [ADDR_WIDTH-1:0] win_rd_addr;

    assign win_rd_mask = rd_mask_vec[rd_winner_id];
    assign win_rd_addr = rd_addr_vec[rd_winner_id];

    // --- 2.3 读 ID 追踪 FIFO ---
    logic rd_fifo_push, rd_fifo_pop;
    logic rd_fifo_full, rd_fifo_empty;
    logic [$clog2(NUM_SLOTS)-1:0] rd_fifo_din;
    logic [$clog2(NUM_SLOTS)-1:0] rd_fifo_dout;

    // 深度建议设大一点，以覆盖流水线延迟并支持多个读请求排队
    FIFO #(
        .WIDTH($clog2(NUM_SLOTS)), .DEPTH(FIFO_DEPTH) 
    ) u_rd_id_fifo (
        .clk(clk), .rstn(rstn),
        .push(rd_fifo_push), .din(rd_fifo_din),
        .pop(rd_fifo_pop),   .dout(rd_fifo_dout),
        .full(rd_fifo_full), .empty(rd_fifo_empty)
    );

    // 入队逻辑：只有当物理层接受了读请求 (rd_ready=1) 时才入队
    // 注意：Wrapper 会在累加器忙碌时拉低 rd_ready
    logic rd_accepted;
    assign rd_accepted = rd_winner_valid && phy_cmd_if.rd_ready && !rd_fifo_full;

    assign rd_fifo_push = rd_accepted;
    assign rd_fifo_din  = rd_winner_id;

    // 出队逻辑：物理层返回了 rvalid
    assign rd_fifo_pop  = phy_data_if.rvalid;


    // ########################################################################
    //                          SECTION 3: 驱动物理接口
    // ########################################################################

    always_comb begin
        // --- 3.1 驱动写通道 (Port A) ---
        phy_cmd_if.wr_valid   = 1'b0;
        phy_cmd_if.accum_en   = 1'b0;
        phy_cmd_if.wr_mask    = '0;
        phy_cmd_if.wr_addr    = '0;
        phy_cmd_if.wr_zone_id = '0; // Subsystem 内部不关心 Zone ID
        
        phy_data_if.wvalid    = 1'b0;
        phy_data_if.wdata     = '0;

        if (wr_fifo_pop) begin
            phy_cmd_if.wr_valid = 1'b1;
            phy_cmd_if.accum_en = wr_fifo_dout.accum_en;
            phy_cmd_if.wr_mask  = wr_fifo_dout.mask;
            phy_cmd_if.wr_addr  = wr_fifo_dout.addr;
            
            phy_data_if.wvalid  = 1'b1;
            // 动态选择数据
            phy_data_if.wdata   = data_wdata_vec[wr_fifo_dout.src_id];
        end

        // --- 3.2 驱动读通道 (Port B) ---
        // 直通模式：仲裁赢家直接连到物理接口
        phy_cmd_if.rd_valid   = rd_accepted; // 只有被接受才发 Valid
        phy_cmd_if.rd_mask    = win_rd_mask;
        phy_cmd_if.rd_addr    = win_rd_addr;
        phy_cmd_if.rd_zone_id = '0;
        // phy_cmd_if.rd_ready 是输入，不用驱动
    end


    // ########################################################################
    //                          SECTION 4: 反馈给 Master
    // ########################################################################

    logic [NUM_SLOTS-1:0]       slot_wr_ready;
    logic [NUM_SLOTS-1:0]       slot_rd_ready;
    logic [NUM_SLOTS-1:0]       slot_wdata_ready;
    logic [NUM_SLOTS-1:0]       slot_rvalid;
    logic [NUM_SLOTS-1:0][NUM_BANKS-1:0][DATA_WIDTH-1:0] slot_rdata;

    always_comb begin
        slot_wr_ready    = '0;
        slot_rd_ready    = '0;
        slot_wdata_ready = '0;
        slot_rvalid      = '0;
        // slot_rdata 稍后统一赋值

        for (int i = 0; i < NUM_SLOTS; i++) begin
            // 4.1 写命令握手
            if (i == wr_winner_id) begin
                slot_wr_ready[i] = !wr_fifo_full;
            end

            // 4.2 读命令握手
            if (i == rd_winner_id) begin
                // 物理层准备好 && ID FIFO 没满
                slot_rd_ready[i] = phy_cmd_if.rd_ready && !rd_fifo_full;
            end

            // 4.3 写数据握手
            // 如果 FIFO 不空，且当前 Slot 是 FIFO 头部的源
            if (!wr_fifo_empty && (i[$clog2(NUM_SLOTS)-1:0] == wr_fifo_dout.src_id)) begin
                slot_wdata_ready[i] = wr_fifo_pop;
            end

            // 4.4 读数据返回 (定向路由)
            if (phy_data_if.rvalid && !rd_fifo_empty) begin
                if (i[$clog2(NUM_SLOTS)-1:0] == rd_fifo_dout) begin
                    slot_rvalid[i] = 1'b1;
                end
            end

            // 4.5 读数据广播 (为了简化逻辑，数据总是广播的，靠 rvalid 区分)
            slot_rdata[i] = phy_data_if.rdata;
        end
    end

    // 打包输出
    generate
        for (g = 0; g < NUM_SLOTS; g++) begin : pack_outputs
            assign cmd_slots[g].wr_ready = slot_wr_ready[g];
            assign cmd_slots[g].rd_ready = slot_rd_ready[g];
            
            assign data_slots[g].wready  = slot_wdata_ready[g];
            assign data_slots[g].rvalid  = slot_rvalid[g];
            assign data_slots[g].rdata   = slot_rdata[g];
        end
    endgenerate

endmodule