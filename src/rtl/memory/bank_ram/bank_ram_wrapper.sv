module Bank_Ram_Wrapper #(
    parameter NUM_BANKS  = 5,
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 32,
    parameter RAM_LATENCY = 2  // **关键参数**: 设为 2
)(
    input logic clk,
    input logic rstn,

    // 1. 来自 Bus Controller 的宽接口
    Bank_Cmd_If.Slave   bus_cmd_if,
    Bank_Data_If.Slave  bus_data_if,

    // 2. 连接到底层 RAM 的物理接口 (数组)
    ram_if.master       ram_ports [NUM_BANKS]
);

    // =======================================================
    // 1. 握手信号处理
    // =======================================================
    // 物理 RAM (BRAM) 是流水线设备，始终 Ready
    assign bus_cmd_if.ready   = 1'b1;
    assign bus_data_if.wready = 1'b1;

    // =======================================================
    // 2. RAM 驱动逻辑 (拆分宽接口 -> 5路窄接口)
    // =======================================================
    genvar i;
    generate
        for (i = 0; i < NUM_BANKS; i++) begin : gen_bank_ctrl
            
            // --- A. 地址与写数据 (直连) ---
            // SIMD 模式：所有 Bank 共享同一个地址
            assign ram_ports[i].addr  = bus_cmd_if.addr;
            // 数据拆分：每个 Bank 拿自己那一份
            assign ram_ports[i].wdata = bus_data_if.wdata[i];

            // --- B. 读数据回传 ---
            // 将 5 个 RAM 的读数据拼起来送回总线
            assign bus_data_if.rdata[i] = ram_ports[i].rdata;

            // --- C. 控制信号生成 (En & We) ---
            always_comb begin
                // 默认关闭
                ram_ports[i].en = 1'b0;
                ram_ports[i].we = 1'b0;

                // 场景 1: 写操作 (Write)
                // 条件：总线送来了数据 (wvalid) 且 该 Bank 在 Mask 中
                // 注意：Controller 保证了 wvalid 有效时，cmd 也是匹配的
                if (bus_data_if.wvalid) begin
                    if (bus_cmd_if.mask[i]) begin
                        ram_ports[i].en = 1'b1;
                        ram_ports[i].we = 1'b1;
                    end
                end
                
                // 场景 2: 读操作 (Read)
                // 条件：总线送来了读命令 (valid && rw=0) 且 该 Bank 在 Mask 中
                else if (bus_cmd_if.valid && (bus_cmd_if.rw == 1'b0)) begin
                    if (bus_cmd_if.mask[i]) begin
                        ram_ports[i].en = 1'b1;
                        ram_ports[i].we = 1'b0;
                    end
                end
            end
        end
    endgenerate

    // =======================================================
    // 3. 读数据有效信号 (rvalid) 生成逻辑
    //    这里处理 RAM_LATENCY = 2
    // =======================================================
    
    // 定义移位寄存器：位宽 = 延迟周期数
    logic [RAM_LATENCY-1:0] rvalid_pipe;
    logic                   read_req_valid;

    // 当前周期是否有有效的读请求发出？
    // 必须 cmd.valid=1 且 rw=0 (读)
    assign read_req_valid = bus_cmd_if.valid && (bus_cmd_if.rw == 1'b0);

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rvalid_pipe <= '0;
        end else begin
            // 移位逻辑：新请求进入最低位 [0]，随着时钟向高位移动
            // Pipe[0] <- Req (Cycle 0)
            // Pipe[1] <- Pipe[0] (Cycle 1) ... 输出
            if (RAM_LATENCY == 1) begin
                rvalid_pipe[0] <= read_req_valid;
            end 
            else begin
                // 左移，LSB 补入新请求
                rvalid_pipe <= {rvalid_pipe[RAM_LATENCY-2:0], read_req_valid};
            end
        end
    end

    // 输出最高位作为最终的 rvalid
    // 当 RAM_LATENCY=2 时，rvalid_pipe[1] 就是延迟了 2 拍的信号
    assign bus_data_if.rvalid = rvalid_pipe[RAM_LATENCY-1];

endmodule