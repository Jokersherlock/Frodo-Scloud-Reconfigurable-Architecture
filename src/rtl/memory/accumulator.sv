module accumulator #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32
)(
    input  logic                    clk,
    input  logic                    rstn,
    ram_if.write_slave              wr_port,
    ram_if.read_slave               rd_port,
    input  logic                    mode
);

    // 内部接口实例化
    ram_if #(ADDR_WIDTH, DATA_WIDTH) int_wr_if (clk);
    ram_if #(ADDR_WIDTH, DATA_WIDTH) int_rd_if (clk);

    `ifdef USE_IP
        dual_ram u_ram(
            .addra(int_wr_if.addr),
            .clka(clk),
            .dina(int_wr_if.wdata),
            .ena(int_wr_if.en),
            .addrb(int_rd_if.addr),
            .clkb(clk),
            .doutb(int_rd_if.rdata),
            .enb(int_rd_if.en)
        );
    `else
        pseudo_dpram u_ram (
            .wr_port (int_wr_if.write_slave),
            .rd_port (int_rd_if.read_slave)
        );
    `endif
    // ============================================================
    // 流水线定义: 3级
    // ============================================================
    typedef struct packed {
        logic                    valid;
        logic                    mode;
        logic [ADDR_WIDTH-1:0]   addr;
        logic [DATA_WIDTH-1:0]   wdata;
    } pipe_ctrl_t;

    // pipe[0]: STAGE 1 - Dispatch & Read Addr
    // pipe[1]: STAGE 2 - RAM Data Available & Latch
    // pipe[2]: STAGE 3 - ALU & Write Back
    pipe_ctrl_t pipe [0:2];

    // 用户要求的"一级寄存器"
    logic [DATA_WIDTH-1:0] ram_rdata_reg;

    // ============================================================
    // 旁路历史 (Forwarding History)
    // ============================================================
    typedef struct packed {
        logic                    valid;
        logic [ADDR_WIDTH-1:0]   addr;
        logic [DATA_WIDTH-1:0]   data;
    } history_t;
    
    // 需要 Depth=2 来覆盖 Read-to-Write 的延迟
    // 因为 Instr 2 在 T1 读，Instr 1 在 T2 才写。Instr 2 读到的是旧的。
    // Instr 2 在 T2 计算时，需要 Instr 1 (刚刚写完) 的结果。
    history_t history [0:1];

    // ============================================================
    // 时序逻辑 (Sequential)
    // ============================================================
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (int i = 0; i < 3; i++) pipe[i] <= '0;
            ram_rdata_reg <= '0;
            history[0] <= '0;
            history[1] <= '0;
        end else begin
            // 1. 流水线移位
            // ------------------------------------------------
            pipe[0].valid <= wr_port.en && wr_port.we;
            pipe[0].mode  <= mode;
            pipe[0].addr  <= wr_port.addr;
            pipe[0].wdata <= wr_port.wdata;

            pipe[1] <= pipe[0];
            pipe[2] <= pipe[1];

            // 2. 数据锁存 (修正点：在 pipe[1] 处锁存)
            // ------------------------------------------------
            // 此时(T1) RAM 输出口 int_rd_if.rdata 已经是对应 pipe[1] 的数据了
            // 我们在 T1 结束的边沿将其存入 reg，供 T2 使用
            if (pipe[1].valid) begin
                ram_rdata_reg <= int_rd_if.rdata;
            end

            // 3. 更新旁路历史
            // ------------------------------------------------
            // 每一拍 Stage 3 (pipe[2]) 产生的结果都要记录
            if (pipe[2].valid) begin
                history[0].valid <= 1'b1;
                history[0].addr  <= pipe[2].addr;
                history[0].data  <= int_wr_if.wdata; // 存入计算结果
                
                history[1] <= history[0];
            end else begin
                history[0].valid <= 1'b0;
                history[1] <= history[0];
            end
        end
    end

    // ============================================================
    // 组合逻辑 (Combinational)
    // ============================================================

    // --- STAGE 0: 读请求分发 ---
    always_comb begin
        // 默认透传外部读
        int_rd_if.en   = rd_port.en;
        int_rd_if.addr = rd_port.addr;
        rd_port.rdata  = int_rd_if.rdata; 

        // 累加器内部读优先
        if (pipe[0].valid && pipe[0].mode == 1'b1) begin
            int_rd_if.en   = 1'b1;
            int_rd_if.addr = pipe[0].addr;
        end
    end

    // --- STAGE 2: ALU & 写回 & 旁路 ---
    logic [DATA_WIDTH-1:0] base_data;
    logic [DATA_WIDTH-1:0] final_wdata;

    always_comb begin
        // 1. 旁路选择逻辑 (Forwarding Mux)
        // ------------------------------------
        // 我们在 pipe[2] (T2时刻) 进行计算。
        // 我们需要的数据原本应该来自 ram_rdata_reg (在T1读取RAM)。
        // 但是，如果在 T1 时刻 RAM 里是旧值（因为前一条指令 T1 才写，或者 T0 才写），
        // 那 ram_rdata_reg 就是脏数据，需要从 history 里找最新的。

        if (pipe[2].mode == 1'b1) begin
            // 优先级：History[0] (上一拍刚写的) > History[1] (上上拍写的) > Reg
            
            if (history[0].valid && (history[0].addr == pipe[2].addr)) begin
                // 命中：紧邻的前一条指令刚写了这个地址
                base_data = history[0].data;
            end else if (history[1].valid && (history[1].addr == pipe[2].addr)) begin
                // 命中：前前一条指令写了这个地址
                // (这种情况发生在：Instr 3 读的时候，Instr 1 正在写，导致读到旧值)
                base_data = history[1].data;
            end else begin
                // 无冲突：使用寄存器里的数据
                base_data = ram_rdata_reg;
            end
        end else begin
            base_data = '0;
        end

        // 2. ALU 计算
        // ------------------------------------
        if (pipe[2].mode == 1'b0)
            final_wdata = pipe[2].wdata;      // 覆盖模式
        else
            final_wdata = base_data + pipe[2].wdata; // 累加模式

        // 3. 驱动写端口
        // ------------------------------------
        int_wr_if.en    = pipe[2].valid;
        int_wr_if.we    = pipe[2].valid;
        int_wr_if.addr  = pipe[2].addr;
        int_wr_if.wdata = final_wdata;
    end

endmodule