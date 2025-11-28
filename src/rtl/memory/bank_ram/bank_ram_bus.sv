module bank_ram_bus #(
    parameter NUM_SLOTS = 4,
    parameter FIFO_DEPTH = 4
)(
    input logic clk,
    input logic rstn,

    //上行，连接Masters(slot0优先级最高)
    Bank_Cmd_If.Slave cmd_slots [NUM_SLOTS],
    Bank_Data_If.Slave data_slots [NUM_SLOTS],

    //下行，连接physical ram
    Bank_Cmd_If.Master phy_cmd_if,
    Bank_Data_If.Master phy_data_if
)

// =======================================================
    // Part A: 优先级仲裁器 (Priority Arbiter)
    // 决定当前谁有资格发送命令 (Winner)
    // =======================================================

    logic [$clog2(NUM_SLOTS)-1:0] winner_id;
    logic                         winner_valid;

    //组合逻辑找最小的索引valid
    always_comb begin
        winner_id = 0;
        winner_valid = 0;
        for(int i = 0; i < NUM_SLOTS; i++) begin
            if(cmd_slots[i].valid) begin
                winner_id = i;
                winner_valid = 1;
                break;
            end
        end
    end

    // --- MUX: 选出 Winner 的命令信号 ---
    logic win_rw;
    logic [4:0] win_mask;
    logic [8:0] win_addr;

    assign win_rw = cmd_slots[winner_id].rw;
    assign win_mask = cmd_slots[winner_id].mask;
    assign win_addr = cmd_slots[winner_id].addr;

    // =======================================================
    // Part B: 带有“源ID”标记的 FIFO
    // =======================================================

    typedef struct packed {
        logic [$clog2(NUM_SLOTS)-1:0] src_id;
        logic [4:0] mask;
        logic [8:0] addr;
    } cmd_entry_t;

    cmd_entry_t fifo_din,fifo_dout;
    logic fifo_push,fifo_pop;
    logic fifo_full,fifo_empty;

    FIFO #(
        .WIDTH($bits(cmd_entry_t)),
        .DEPTH(FIFO_DEPTH)
    ) u_fifo(
        .clk(clk),
        .rstn(rstn),
        .push(fifo_push),
        .din(fifo_din),
        .pop(fifo_pop),
        .dout(fifo_dout),
        .full(fifo_full),
        .empty(fifo_empty)
    );

// =======================================================
    // Part C: 核心控制逻辑
    // =======================================================    
    
    // --- 1. 入队逻辑 (Push) ---
    // 准备数据
    assign fifo_din.src_id = winner_id;
    assign fifo_din.mask   = win_mask;
    assign fifo_din.addr   = win_addr;

    // 条件：有赢家 + 是写操作 + FIFO没满
    assign fifo_push = winner_valid && (win_rw == 1'b1) && !fifo_full;

    // --- 2. 出队逻辑 (Pop) ---
    // 使用 FWFT 特性：先看 fifo_dout 里的 src_id，去检查对应的 Master 数据是否到了
    logic current_master_has_data;
    assign current_master_has_data = data_slots[fifo_dout.src_id].wvalid;

    // 条件：FIFO不空 + 对应Master的数据有效
    assign fifo_pop = !fifo_empty && current_master_has_data;

    // --- 3. 驱动物理接口 (Drive Physical RAM) ---
    always_comb begin
        //默认清0
        phy_cmd_if.valid = 0;
        phy_cmd_if.rw = 0;
        phy_cmd_if.mask = 0;
        phy_cmd_if.addr = 0;
        phy_data_if.wvalid = 0;
        phy_data_if.wdata = 0;
        // [优先级 1] 写操作执行 (Write Execution)
        if(fifo_pop)begin
            phy_cmd_if.valid = 1'b1;
            phy_cmd_if.rw = 1'b1;
            phy_cmd_if.mask = fifo_dout.mask;
            phy_cmd_if.addr = fifo_dout.addr;
            phy_data_if.wvalid = 1'b1;
            phy_data_if.wdata = data_slots[fifo_dout.src_id].wdata;
        end
        // [优先级 2] 读操作直通
        else if(winner_valid && (win_rw == 1'b0) && fifo_empty)begin
            // 条件：Winner 想读 + FIFO 是空的 (防止 RAW 冒险)
            phy_cmd_if.valid = 1'b1;
            phy_cmd_if.rw = 1'b0;
            phy_cmd_if.mask = win_mask;
            phy_cmd_if.addr = win_addr;
        end
    end

// =======================================================
    // Part D: 向 Master 反馈信号 (Ready / Read Data)
    // =======================================================
    always_comb begin
        for(int i=0;i<NUM_SLOTS;i++)begin
            //默认全0
            cmd_slots[i].ready = 1'b0;
            data_slots[i].wready = 1'b0;
            data_slots[i].rvalid = 1'b0;
            data_slots[i].rdata = '0;
            // --- 1. 命令握手 (Cmd Ready) ---
            // 只有当你是 Winner 时，总线才处理你的 Cmd 请求
            if (i == winner_id) begin
                if (win_rw == 1'b1) begin
                    // 写操作：看 FIFO 是否满
                    cmd_slots[i].ready = !fifo_full;
                end else begin
                    // 读操作：看物理层是否 Ready 且 FIFO 为空
                    cmd_slots[i].ready = phy_cmd_if.ready && fifo_empty;
                end
            end
            // 2. 写数据握手 (Data Ready)
            // 只有当你是 FIFO 头部正在等待的那个人，且发生了 Pop，才说明数据被收走了
            if (!fifo_empty && (i == fifo_dout.src_id)) begin
                data_slots[i].wready = fifo_pop;
            end
            // 3. 读数据返回 (Read Return)
            // 简单透传：假设物理层返回的数据就是给 Winner 的 (需要上层保证读时序)
            // 也可以增加一个 Read FIFO 来处理乱序，但在简单总线中通常直接返回
            if (i == winner_id) begin 
                 data_slots[i].rvalid = phy_data_if.rvalid;
                 data_slots[i].rdata  = phy_data_if.rdata;
            end
        end
    end



endmodule