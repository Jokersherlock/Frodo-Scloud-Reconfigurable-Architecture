module pseudo_dpram (
    // 端口 A：专门用于写
    ram_if.write_slave wr_port,
    // 端口 B：专门用于读
    ram_if.read_slave rd_port
);

    // ============================================================
    // 1. 参数获取与存储阵列定义
    // ============================================================
    // 从接口获取参数，确保模块的通用性
    localparam AW = wr_port.ADDR_WIDTH;
    localparam DW = wr_port.DATA_WIDTH;
    localparam DEPTH = 1 << AW; // 例如：1 << 9 = 512

    // 存储阵列 (32位或64位，由DW决定)
    logic [DW-1:0] mem [0:DEPTH-1];

    // 新增：读数据一级寄存器 (R1) - 模拟 Core Output Register 前的寄存器
    // R1 负责保存 RAM 阵列的读出数据
    logic [DW-1:0] rdata_pipe_reg; 

    // ============================================================
    // 2. 内存初始化 (Simulation/Synthesis INIT)
    // ============================================================
    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = '0; // 初始化所有内存为 0
        end
    end

    // ============================================================
    // 3. 写逻辑 (Port A)
    // ============================================================
    always_ff @(posedge wr_port.clk) begin
        if (wr_port.en) begin
            if (wr_port.we) begin
                mem[wr_port.addr] <= wr_port.wdata;
            end
        end
    end

    // ============================================================
    // 4. 读逻辑 (Port B) - Latency = 2
    // ============================================================
    always_ff @(posedge rd_port.clk) begin
        // Stage 1: 内存读取到 R1 寄存器 (Latency 1)
        if (rd_port.en) begin
            rdata_pipe_reg <= mem[rd_port.addr]; 
        end

        // Stage 2: R1 寄存器到输出端口 (Latency 2)
        // 这个输出寄存器是始终被时钟驱动的，保证流水线传输
        rd_port.rdata <= rdata_pipe_reg; 
    end

    // ============================================================
    // 5. 调试打印逻辑 (Hardcoded Path - 仅仿真)
    // ============================================================
    `ifdef PRINT_RAM
        initial begin
            int fd;
            string filename;
            forever begin
                // 1. 等待全局触发信号变为特定值
                wait($root.tb_accumulator.dump_trigger == 1); 
    
                // 2. 尝试打开文件
                $sformat(filename, "../../../../../../temp/accumulator_data/%m.txt");
                fd = $fopen(filename, "w");
    
                if (fd) begin
                    $display("[%0t] Dumping memory content to %s ...", $time, filename);
                    $writememh(filename, mem);
                    $fclose(fd);
                end else begin
                    // 假设目录不存在，不停止仿真
                    $error("Failed to open file %s", filename);
                end
    
                // 3. 等待触发信号消失，防止重复打印
                wait($root.tb_accumulator.dump_trigger == 0);
            end
        end
    `endif

endmodule