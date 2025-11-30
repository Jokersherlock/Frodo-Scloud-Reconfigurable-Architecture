module bank_ram_bus #(
    parameter NUM_SLOTS  = 4,
    parameter FIFO_DEPTH = 4,
    // FIX: 新增参数以支持宽总线
    parameter NUM_BANKS  = 5, 
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic rstn,

    Bank_Cmd_If.Slave   cmd_slots  [NUM_SLOTS],
    Bank_Data_If.Slave  data_slots [NUM_SLOTS],

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
    
    // FIX: 修正数据位宽定义
    // 之前是 [31:0]，现在改为 [NUM_BANKS-1:0][DATA_WIDTH-1:0] (即 5x32)
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
            
            // FIX: 这里会进行整个数组的赋值，位宽现在匹配了
            assign data_wdata_vec[g]  = data_slots[g].wdata;
        end
    endgenerate

    // =======================================================
    // Part B: 仲裁与 FIFO
    // =======================================================
    
    // 1. 优先级仲裁
    logic [$clog2(NUM_SLOTS)-1:0] winner_id;
    logic                         winner_valid;

    always_comb begin
        winner_id = 0;      
        winner_valid = 1'b0;
        for (int i = 0; i < NUM_SLOTS; i++) begin
            if (req_valid_vec[i]) begin
                winner_id = i[$clog2(NUM_SLOTS)-1:0];    
                winner_valid = 1'b1;
                break; 
            end
        end
    end

    // 2. 赢家信号选择
    logic       win_rw;
    logic [4:0] win_mask;
    logic [8:0] win_addr;
    
    assign win_rw   = req_rw_vec[winner_id];
    assign win_mask = req_mask_vec[winner_id];
    assign win_addr = req_addr_vec[winner_id];

    // 3. FIFO 定义与实例化
    typedef struct packed {
        logic [$clog2(NUM_SLOTS)-1:0] src_id;
        logic [4:0] mask;
        logic [8:0] addr;
    } cmd_entry_t;

    cmd_entry_t fifo_din, fifo_dout;
    logic fifo_push, fifo_pop;
    logic fifo_full, fifo_empty;

    FIFO #(
        .WIDTH($bits(cmd_entry_t)),
        .DEPTH(FIFO_DEPTH)
    ) u_fifo(
        .clk(clk), .rstn(rstn),
        .push(fifo_push), .din(fifo_din),
        .pop(fifo_pop),   .dout(fifo_dout),
        .full(fifo_full), .empty(fifo_empty)
    );

    // =======================================================
    // Part C: 核心控制逻辑
    // =======================================================

    // 1. 入队控制
    assign fifo_din.src_id = winner_id;
    assign fifo_din.mask   = win_mask;
    assign fifo_din.addr   = win_addr;
    assign fifo_push       = winner_valid && (win_rw == 1'b1) && !fifo_full;

    // 2. 出队控制
    logic current_master_has_data;
    assign current_master_has_data = data_wvalid_vec[fifo_dout.src_id];
    assign fifo_pop = !fifo_empty && current_master_has_data;

    // 3. 驱动物理接口
    always_comb begin
        phy_cmd_if.valid = 0; phy_cmd_if.rw = 0; 
        phy_cmd_if.mask = '0; phy_cmd_if.addr = '0;
        phy_data_if.wvalid = 0; 
        // FIX: 默认值也要匹配位宽
        phy_data_if.wdata = '0; 

        // 优先级 A: 执行写操作
        if (fifo_pop) begin
            phy_cmd_if.valid = 1'b1;
            phy_cmd_if.rw    = 1'b1;
            phy_cmd_if.mask  = fifo_dout.mask;
            phy_cmd_if.addr  = fifo_dout.addr;
            
            phy_data_if.wvalid = 1'b1;
            // FIX: 这里的位宽现在匹配了 (5x32)
            phy_data_if.wdata  = data_wdata_vec[fifo_dout.src_id];
        end
        // 优先级 B: 执行读操作
        else if (winner_valid && (win_rw == 1'b0) && fifo_empty) begin
            phy_cmd_if.valid = 1'b1;
            phy_cmd_if.rw    = 1'b0;
            phy_cmd_if.mask  = win_mask;
            phy_cmd_if.addr  = win_addr;
        end
    end

    // =======================================================
    // Part D: 信号打包与反馈 (Pack Outputs)
    // =======================================================

    logic [NUM_SLOTS-1:0]       slot_cmd_ready;
    logic [NUM_SLOTS-1:0]       slot_data_wready;
    logic [NUM_SLOTS-1:0]       slot_rvalid;
    
    // FIX: 修正读数据位宽定义
    logic [NUM_SLOTS-1:0][NUM_BANKS-1:0][DATA_WIDTH-1:0] slot_rdata;

    always_comb begin
        slot_cmd_ready   = '0;
        slot_data_wready = '0;
        slot_rvalid      = '0;
        // slot_rdata 稍后赋值

        for (int i = 0; i < NUM_SLOTS; i++) begin
            // --- Cmd Ready ---
            if (i == winner_id) begin
                if (win_rw == 1'b1) slot_cmd_ready[i] = !fifo_full; 
                else                slot_cmd_ready[i] = phy_cmd_if.ready && fifo_empty; 
            end

            // --- Data Ready ---
            if (!fifo_empty && (i[$clog2(NUM_SLOTS)-1:0] == fifo_dout.src_id)) begin
                slot_data_wready[i] = fifo_pop;
            end
            
            // --- Read Return ---
            if (i == winner_id) begin
                slot_rvalid[i] = phy_data_if.rvalid;
            end
            
            // FIX: 数据广播，位宽匹配 (5x32)
            slot_rdata[i] = phy_data_if.rdata;
        end
    end

    generate
        for (g = 0; g < NUM_SLOTS; g++) begin : pack_outputs
            assign cmd_slots[g].ready   = slot_cmd_ready[g];
            assign data_slots[g].wready = slot_data_wready[g];
            assign data_slots[g].rvalid = slot_rvalid[g];
            assign data_slots[g].rdata  = slot_rdata[g];
        end
    endgenerate

endmodule