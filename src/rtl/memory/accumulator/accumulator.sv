module accumulator #(
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 64
)(
    input  logic clk,
    input  logic rstn,
    ram_if.write_slave wr_port,
    ram_if.read_slave  rd_port,
    input  logic mode
);

    // 内部接口实例化 & RAM 实例化 (保持不变)
    ram_if #(ADDR_WIDTH, DATA_WIDTH) int_wr_if (clk);
    ram_if #(ADDR_WIDTH, DATA_WIDTH) int_rd_if (clk);
    
    `ifdef USE_IP
        dual_ram u_ram( 
            .addra(int_wr_if.addr), .clka(clk), .dina(int_wr_if.wdata), .ena(int_wr_if.en),
            .addrb(int_rd_if.addr), .clkb(clk), .doutb(int_rd_if.rdata), .enb(int_rd_if.en)
        );
    `else
        pseudo_dpram u_ram ( 
            .wr_port (int_wr_if.write_slave), 
            .rd_port (int_rd_if.read_slave) 
        );
    `endif

    // ============================================================
    // 流水线定义: 3级 [0:2]
    // ============================================================
    typedef struct packed {
        logic valid;
        logic mode;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] wdata;
    } pipe_ctrl_t;

    pipe_ctrl_t pipe [0:2]; 

    // History (2 级深度)
    typedef struct packed { 
        logic valid;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
    } history_t;
    history_t history [0:1]; 

    // ALU 结果锁存 (Stage 2 Register)
    logic [DATA_WIDTH-1:0] alu_result_reg; 
    
    // Write Command Latch (Stage 2 Register)
    pipe_ctrl_t wr_cmd_reg;
    
    // Module 级组合逻辑信号
    logic [DATA_WIDTH-1:0] base_data;
    logic [DATA_WIDTH-1:0] final_wdata; 

    // ============================================================
    // 时序逻辑 (Sequential)
    // ============================================================
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (int i = 0; i < 3; i++) pipe[i] <= '0; 
            alu_result_reg <= '0; 
            wr_cmd_reg <= '0;
            history[0] <= '0;
            history[1] <= '0;
        end else begin
            // 1. 流水线移位 (收缩回 3 级)
            pipe[0].valid <= wr_port.en && wr_port.we;
            pipe[0].mode  <= mode;
            pipe[0].addr  <= wr_port.addr;
            pipe[0].wdata <= wr_port.wdata;

            pipe[1] <= pipe[0];
            pipe[2] <= pipe[1]; 

            // 2. 写命令锁存 (Stage 2 Register)
            wr_cmd_reg <= pipe[2]; 

            // 3. 更新旁路历史 (在 pipe[2] 处写回)
            history[1] <= history[0]; // T-2 <= T-1 (History 移位)

            if (pipe[2].valid) begin // P2 是最终 ALU 级
                history[0].valid <= 1'b1;
                history[0].addr  <= pipe[2].addr;
                history[0].data  <= alu_result_reg; 
            end else begin
                history[0].valid <= 1'b0; // 清楚有效位
            end
            
            // 4. ALU 结果锁存 (Stage 2 寄存器)
            alu_result_reg <= final_wdata;
        end
    end

    // ============================================================
    // 组合逻辑 (Combinational)
    // ============================================================

    // --- STAGE 0: 读请求分发 ---
    always_comb begin
        // 默认透传外部读
        int_rd_if.en  = rd_port.en;
        int_rd_if.addr = rd_port.addr;
        rd_port.rdata = int_rd_if.rdata; 

        // 累加器内部读优先 (修正为组合发射)
        if (wr_port.en && wr_port.we && mode == 1'b1) begin 
            int_rd_if.en  = 1'b1;
            int_rd_if.addr = wr_port.addr; // 使用外部输入的地址 (T0 地址)
        end
        // 外部读透传逻辑
        else if (pipe[0].valid && pipe[0].mode == 1'b1) begin
            int_rd_if.en  = 1'b1;
            int_rd_if.addr = pipe[0].addr;
        end
    end

    // --- STAGE 2: ALU & 写回 & 旁路 ---
    always_comb begin
        // 1. 旁路选择逻辑 (Forwarding Mux)
        if (pipe[2].mode == 1'b1) begin
            
            // 检查历史记录 (只检查 T-1, T-2)
            if (history[0].valid && (history[0].addr == pipe[2].addr)) begin
                base_data = history[0].data; // 命中 T-1 结果
            end else if (history[1].valid && (history[1].addr == pipe[2].addr)) begin
                base_data = history[1].data; // 命中 T-2 结果
            end else begin // 【关键语法修正点】: 去掉前面的 '}'
                // 无冲突：使用 RAM 的输出线 (Lat=2 数据)
                base_data = int_rd_if.rdata; 
            end
        end else begin
            base_data = '0;
        end

        // 2. ALU 计算
        if (pipe[2].mode == 1'b0)
            final_wdata = pipe[2].wdata;
        else
            final_wdata = base_data + pipe[2].wdata; // 累加

        // 3. 驱动写端口 (Port A)
        int_wr_if.en = wr_cmd_reg.valid;
        int_wr_if.we = wr_cmd_reg.valid;
        int_wr_if.addr = wr_cmd_reg.addr;
        int_wr_if.wdata = alu_result_reg; // 写入 T3 锁存后的结果
    end
endmodule