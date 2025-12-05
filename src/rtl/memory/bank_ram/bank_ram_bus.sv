module bank_ram_bus #(
    parameter NUM_SLOTS  = 4,   // 连接的主设备数量
    parameter FIFO_DEPTH = 4,   // 写缓冲深度
    parameter NUM_BANKS  = 5,   // SIMD Bank 数量
    parameter DATA_WIDTH = 32   // 单个 Bank 的位宽
)(
    input logic clk,
    input logic rstn,

    // 上行接口：连接 Masters (Slot 0 优先级最高)
    Bank_Cmd_If.Slave   cmd_slots  [NUM_SLOTS],
    Bank_Data_If.Slave  data_slots [NUM_SLOTS],

    // 下行接口：连接 Physical RAM Wrapper
    Bank_Cmd_If.Master  phy_cmd_if,
    Bank_Data_If.Master phy_data_if
);

    // =======================================================
    // Part A: 信号解包 (Unpack Inputs)
    // =======================================================
    
    logic [NUM_SLOTS-1:0]       req_valid_vec;
    logic [NUM_SLOTS-1:0]       req_rw_vec;
    logic [NUM_SLOTS-1:0][4:0]  req_mask_vec;
    logic [NUM_SLOTS-1:0][8:0]  req_addr_vec;
    
    logic [NUM_SLOTS-1:0]       data_wvalid_vec;
    logic [NUM_SLOTS-1:0][NUM_BANKS-1:0][DATA_WIDTH-1:0] data_wdata_vec; 

    genvar g;
    generate
        for (g = 0; g < NUM_SLOTS; g++) begin : unpack_inputs
            // Cmd 接口解包
            assign req_valid_vec[g] = cmd_slots[g].valid;
            assign req_rw_vec[g]    = cmd_slots[g].rw;
            assign req_mask_vec[g]  = cmd_slots[g].mask;
            assign req_addr_vec[g]  = cmd_slots[g].addr;
            
            // Data 接口解包
            assign data_wvalid_vec[g] = data_slots[g].wvalid;
            assign data_wdata_vec[g]  = data_slots[g].wdata;
        end
    endgenerate

    // =======================================================
    // Part B: 仲裁逻辑 (Arbitration)
    // =======================================================
    
    // 1. 优先级仲裁 (Fixed Priority: 0 > 1 > ... > N)
    logic [$clog2(NUM_SLOTS)-1:0] winner_id;
    logic                         winner_valid;

    always_comb begin
        winner_id = 0;      
        winner_valid = 1'b0;
        // 遍历解包后的数组，找到第一个 Valid
        for (int i = 0; i < NUM_SLOTS; i++) begin
            if (req_valid_vec[i]) begin
                winner_id = i[$clog2(NUM_SLOTS)-1:0];    
                winner_valid = 1'b1;
                break; 
            end
        end
    end

    // 2. 获取赢家的命令信号
    logic       win_rw;
    logic [4:0] win_mask;
    logic [8:0] win_addr;
    
    assign win_rw   = req_rw_vec[winner_id];
    assign win_mask = req_mask_vec[winner_id];
    assign win_addr = req_addr_vec[winner_id];


    // =======================================================
    // Part C: 写路径处理 (Write Path: FIFO & Bypass)
    // =======================================================
    
    // 定义写指令 FIFO 结构
    typedef struct packed {
        logic [$clog2(NUM_SLOTS)-1:0] src_id;
        logic [4:0] mask;
        logic [8:0] addr;
    } cmd_entry_t;

    cmd_entry_t fifo_din, fifo_dout;
    logic fifo_push, fifo_pop;
    logic fifo_full, fifo_empty;

    // 【新增】旁路条件：FIFO空 + 赢家是写操作 + 写数据也同步到达
    logic do_bypass;
    assign do_bypass = fifo_empty && winner_valid && (win_rw == 1'b1) && data_wvalid_vec[winner_id];

    // 实例化 FIFO (存储待处理的写地址)
    FIFO #(
        .WIDTH($bits(cmd_entry_t)),
        .DEPTH(FIFO_DEPTH)
    ) u_cmd_fifo(
        .clk(clk), .rstn(rstn),
        .push(fifo_push), .din(fifo_din),
        .pop(fifo_pop),   .dout(fifo_dout),
        .full(fifo_full), .empty(fifo_empty)
    );

    // 入队逻辑：有赢家 + 是写操作 + FIFO没满 + 【不走旁路】
    assign fifo_din.src_id = winner_id;
    assign fifo_din.mask   = win_mask;
    assign fifo_din.addr   = win_addr;
    assign fifo_push       = winner_valid && (win_rw == 1'b1) && !fifo_full && !do_bypass;

    // 出队逻辑：FIFO不空 + 对应 Master 的数据已到达
    // (注意：如果走了旁路，数据直接被消费，不会进入这里)
    logic current_master_has_data;
    assign current_master_has_data = data_wvalid_vec[fifo_dout.src_id];
    assign fifo_pop = !fifo_empty && current_master_has_data;


    // =======================================================
    // Part D: 读路径处理 (Read Path: ID Tracking)
    // =======================================================
    
    // 读 ID FIFO 用于记录“发出的读请求是谁的”，以便数据返回时路由给正确的人
    logic rd_fifo_push, rd_fifo_pop;
    logic rd_fifo_full, rd_fifo_empty;
    logic [$clog2(NUM_SLOTS)-1:0] rd_fifo_din;
    logic [$clog2(NUM_SLOTS)-1:0] rd_fifo_dout;

    // 实例化读 ID FIFO
    FIFO #(
        .WIDTH($clog2(NUM_SLOTS)),
        .DEPTH(8) 
    ) u_rd_id_fifo (
        .clk(clk), .rstn(rstn),
        .push(rd_fifo_push), .din(rd_fifo_din),
        .pop(rd_fifo_pop),   .dout(rd_fifo_dout),
        .full(rd_fifo_full), .empty(rd_fifo_empty)
    );

    // 读请求是否被物理层接受？
    // 条件：有赢家 + 是读操作 + 物理层Ready + 没有积压的写操作(fifo_empty) + 读ID FIFO没满
    // 注意：如果是旁路写操作，win_rw为1，这里read_accepted自然为0，互斥
    logic read_accepted;
    assign read_accepted = winner_valid && (win_rw == 1'b0) && phy_cmd_if.ready && fifo_empty && !rd_fifo_full;

    // 入队：记录 ID
    assign rd_fifo_push = read_accepted;
    assign rd_fifo_din  = winner_id;

    // 出队：物理层返回有效数据
    assign rd_fifo_pop  = phy_data_if.rvalid;


    // =======================================================
    // Part E: 驱动物理层 (Drive Physical Layer)
    // =======================================================
    always_comb begin
        // 默认复位值
        phy_cmd_if.valid = 0; 
        phy_cmd_if.rw = 0; 
        phy_cmd_if.mask = '0; 
        phy_cmd_if.addr = '0;
        phy_data_if.wvalid = 0; 
        phy_data_if.wdata = '0;

        if (do_bypass) begin
            // [A] 旁路写 (Bypass Write) - 优先级最高 (0 latency)
            phy_cmd_if.valid = 1'b1;
            phy_cmd_if.rw    = 1'b1;
            phy_cmd_if.mask  = win_mask;
            phy_cmd_if.addr  = win_addr;
            
            phy_data_if.wvalid = 1'b1;
            phy_data_if.wdata  = data_wdata_vec[winner_id]; // 直接取输入数据
        end
        else if (fifo_pop) begin
            // [B] FIFO 写 (FIFO Write)
            phy_cmd_if.valid = 1'b1;
            phy_cmd_if.rw    = 1'b1;
            phy_cmd_if.mask  = fifo_dout.mask;
            phy_cmd_if.addr  = fifo_dout.addr;
            
            phy_data_if.wvalid = 1'b1;
            phy_data_if.wdata  = data_wdata_vec[fifo_dout.src_id]; // 从 FIFO 指向的源取数据
        end
        else if (read_accepted) begin
            // [C] 读操作 (Read Passthrough)
            phy_cmd_if.valid = 1'b1;
            phy_cmd_if.rw    = 1'b0;
            phy_cmd_if.mask  = win_mask;
            phy_cmd_if.addr  = win_addr;
        end
    end


    // =======================================================
    // Part F: 信号打包与反馈 (Pack Outputs)
    // =======================================================

    logic [NUM_SLOTS-1:0]       slot_cmd_ready;
    logic [NUM_SLOTS-1:0]       slot_data_wready;
    logic [NUM_SLOTS-1:0]       slot_rvalid;
    logic [NUM_SLOTS-1:0][NUM_BANKS-1:0][DATA_WIDTH-1:0] slot_rdata;

    always_comb begin
        // 默认值
        slot_cmd_ready   = '0;
        slot_data_wready = '0;
        slot_rvalid      = '0;
        // slot_rdata 稍后赋值

        for (int i = 0; i < NUM_SLOTS; i++) begin
            // --- 1. Cmd Ready ---
            if (i == winner_id) begin
                if (win_rw == 1'b1) begin
                    // 写操作：
                    if (do_bypass) begin
                        slot_cmd_ready[i] = 1'b1; // 旁路模式直接 Ready
                    end else begin
                        slot_cmd_ready[i] = !fifo_full; // 否则看 FIFO
                    end
                end else begin
                    // 读操作：取决于物理 Ready + 写 FIFO 空 + 读 ID FIFO 未满
                    slot_cmd_ready[i] = phy_cmd_if.ready && fifo_empty && !rd_fifo_full;
                end
            end

            // --- 2. Data Write Ready ---
            if (do_bypass && (i == winner_id)) begin
                // 【新增】旁路模式：数据当拍被消费
                slot_data_wready[i] = 1'b1;
            end 
            else if (!fifo_empty && (i[$clog2(NUM_SLOTS)-1:0] == fifo_dout.src_id)) begin
                // 传统模式：FIFO 出队时消耗数据
                slot_data_wready[i] = fifo_pop; 
            end
            
            // --- 3. Read Data Valid ---
            // 只有当读 ID FIFO 不空，且当前 ID 匹配时，才发 rvalid
            if (phy_data_if.rvalid && !rd_fifo_empty) begin
                if (i[$clog2(NUM_SLOTS)-1:0] == rd_fifo_dout) begin
                    slot_rvalid[i] = 1'b1;
                end
            end
            
            // --- 4. Read Data (Broadcast) ---
            slot_rdata[i] = phy_data_if.rdata;
        end
    end

    // 将中间信号赋值回 Interface
    generate
        for (g = 0; g < NUM_SLOTS; g++) begin : pack_outputs
            assign cmd_slots[g].ready   = slot_cmd_ready[g];
            assign data_slots[g].wready = slot_data_wready[g];
            assign data_slots[g].rvalid = slot_rvalid[g];
            assign data_slots[g].rdata  = slot_rdata[g];
        end
    endgenerate

endmodule