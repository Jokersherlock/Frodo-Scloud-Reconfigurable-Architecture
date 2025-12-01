`timescale 1ns/1ps

module tb_accumulator;

    // ============================================================
    // 1. 参数与信号定义
    // ============================================================
    parameter ADDR_WIDTH = 9;
    parameter DATA_WIDTH = 64;
    parameter BATCH_COUNT = 10000; // 批量测试次数

    logic clk, rstn;
    logic mode;

    // 实例化接口 (TB 作为 Master 驱动这些接口)
    ram_if #(ADDR_WIDTH, DATA_WIDTH) ext_wr_if(clk);
    ram_if #(ADDR_WIDTH, DATA_WIDTH) ext_rd_if(clk);

    // ============================================================
    // 2. 实例化 DUT (Device Under Test)
    // ============================================================
    accumulator #(ADDR_WIDTH, DATA_WIDTH) dut (
        .clk     (clk),
        .rstn    (rstn),
        .wr_port (ext_wr_if.write_slave), // DUT 作为 Slave
        .rd_port (ext_rd_if.read_slave),  // DUT 作为 Slave
        .mode    (mode)
    );

    // ============================================================
    // 3. 时钟生成
    // ============================================================
    initial clk = 0;
    always #5 clk = ~clk; // 10ns 周期

    // ============================================================
    // 4. 定向测试辅助 Task
    // ============================================================
    
    // 发送写/累加请求
    task send_req(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data, input logic is_accumulate);
        @(posedge clk);
        mode            <= is_accumulate;
        ext_wr_if.en    <= 1;
        ext_wr_if.we    <= 1;
        ext_wr_if.addr  <= addr;
        ext_wr_if.wdata <= data;
        
        @(posedge clk);
        // 撤销请求
        ext_wr_if.en    <= 0;
        ext_wr_if.we    <= 0;
        ext_wr_if.wdata <= '0; 
    endtask

    // 发起读请求并检查结果
    task check_result(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] expected_val);
        @(posedge clk);
        ext_rd_if.en   <= 1;
        ext_rd_if.addr <= addr;
        
        @(posedge clk);
        ext_rd_if.en   <= 0; // 读请求结束

        // RAM Latency = 1，所以数据在下一个周期有效
        @(posedge clk); 
        #1; // 延时采样
        
        if (ext_rd_if.rdata !== expected_val) begin
            $error("[FAIL] Addr 0x%h: Expected 0x%h, Got 0x%h", addr, expected_val, ext_rd_if.rdata);
        end else begin
            $display("[PASS] Addr 0x%h: Read 0x%h Correctly", addr, ext_rd_if.rdata);
        end
    endtask

    // ============================================================
    // 5. 批量随机测试 Task (Batch Test)
    // ============================================================
    
    // Scoreboard: 模拟理想内存
    // Key: Address, Value: Data
    logic [DATA_WIDTH-1:0] ref_mem [int]; 

    task run_batch_test(input int iterations);
        $display("\n========================================");
        $display("STARTING BATCH TEST (%0d iterations)", iterations);
        $display("========================================");

        // 1. 复位逻辑
        rstn = 0;
        ref_mem.delete(); // 清空 Scoreboard
        repeat(5) @(posedge clk);
        rstn = 1;
        repeat(5) @(posedge clk);

        // ====================================================
        // [关键修复] 2. 硬件内存清洗 (Memory Scrubbing)
        // 必须显式地把硬件 RAM 写成 0，清除之前定向测试残留的数据
        // 否则 Scoreboard (0) 和 Hardware (Dirty) 不一致会导致累加错误
        // ====================================================
        $display("Initializing Hardware RAM to 0...");
        for (int i = 0; i < (1<<ADDR_WIDTH); i++) begin
            @(posedge clk);
            mode            <= 0;  // 覆盖模式 (Mode 0)
            ext_wr_if.en    <= 1;
            ext_wr_if.we    <= 1;
            ext_wr_if.addr  <= i[ADDR_WIDTH-1:0]; 
            ext_wr_if.wdata <= '0; // 写入 0
        end
        
        // 撤销写信号
        @(posedge clk);
        ext_wr_if.en <= 0;
        ext_wr_if.we <= 0;
        
        // 等待流水线排空
        repeat(5) @(posedge clk);
        $display("RAM Initialization Done.");
        // ====================================================

        // 3. 开始随机循环
        for (int i = 0; i < iterations; i++) begin
            // --- 随机变量 ---
            logic [ADDR_WIDTH-1:0] rand_addr;
            logic [DATA_WIDTH-1:0] rand_data;
            logic                  is_acc;
            int                    op_type; // 0: Write/Acc, 1: Read

            void'(std::randomize(rand_addr, rand_data, is_acc, op_type) with {
                op_type dist {0:=70, 1:=30}; // 70% 概率写/累加, 30% 概率读
                is_acc  dist {0:=40, 1:=60}; // 如果是写，60% 概率是累加
            });

            // --- 执行操作 ---
            if (op_type == 0) begin
                // >>> WRITE / ACCUMULATE <<<
                
                // 1. 更新 Scoreboard
                logic [DATA_WIDTH-1:0] old_val;
                if (ref_mem.exists(rand_addr)) old_val = ref_mem[rand_addr];
                else old_val = 0;

                if (is_acc) begin
                    ref_mem[rand_addr] = old_val + rand_data;
                end else begin
                    ref_mem[rand_addr] = rand_data;
                end

                // 2. 驱动 DUT
                @(posedge clk);
                mode            <= is_acc;
                ext_wr_if.en    <= 1;
                ext_wr_if.we    <= 1;
                ext_wr_if.addr  <= rand_addr;
                ext_wr_if.wdata <= rand_data;
                
                @(posedge clk);
                ext_wr_if.en    <= 0;
                ext_wr_if.we    <= 0;

            end else begin
                // >>> READ & CHECK <<<
                
                // 1. 获取期望值
                logic [DATA_WIDTH-1:0] exp_val;
                if (ref_mem.exists(rand_addr)) exp_val = ref_mem[rand_addr];
                else exp_val = 0;

                // 2. 驱动读
                // 注意：在 Accumulate 模式下内部会占用读口
                // 所以我们这里强制 mode=0 来进行外部安全读取
                @(posedge clk);
                mode           <= 0; 
                ext_rd_if.en   <= 1;
                ext_rd_if.addr <= rand_addr;
                @(posedge clk);
                ext_rd_if.en   <= 0;

                // 3. 等待并校验 (Latency=1)
                @(posedge clk); 
                #1;
                
                if (ext_rd_if.rdata !== exp_val) begin
                    $error("[BATCH FAIL] Iter:%0d Addr:0x%h Exp:0x%h Got:0x%h", 
                           i, rand_addr, exp_val, ext_rd_if.rdata);
                    $stop; // 遇到错误停止，方便调试
                end
            end
            
            // 每次操作后稍微等一下，让流水线完成写回
            // 确保 Read-After-Write 时序宽松，主要验证功能正确性
            repeat(3) @(posedge clk);
            
            if (i > 0 && i % 1000 == 0) $display("Progress: %0d / %0d", i, iterations);
        end
        
        $display("\n>>> BATCH TEST PASSED! (%0d ops) <<<", iterations);
    endtask

    // ============================================================
    // 6. 主测试流程
    // ============================================================
    initial begin
        // --- 初始化 ---
        rstn = 0;
        mode = 0;
        ext_wr_if.en = 0; ext_wr_if.we = 0; ext_wr_if.addr = 0; ext_wr_if.wdata = 0;
        ext_rd_if.en = 0; ext_rd_if.addr = 0;
        
        repeat(5) @(posedge clk);
        rstn = 1;
        $display("=== Simulation Start ===");
        repeat(2) @(posedge clk);

        // --------------------------------------------------------
        // PHASE 1: 定向测试 (Directed Tests)
        // --------------------------------------------------------
        
        // TEST 1: Overwrite Mode
        $display("\n--- Test 1: Overwrite Mode (Init) ---");
        send_req(10'h10, 64'd100, 0);
        send_req(10'h20, 64'd200, 0);
        repeat(5) @(posedge clk);
        check_result(10'h10, 100);
        check_result(10'h20, 200);

        // TEST 2: Basic Accumulate
        $display("\n--- Test 2: Basic Accumulate ---");
        send_req(10'h10, 64'd50, 1);
        repeat(5) @(posedge clk);
        check_result(10'h10, 150);

        // TEST 3: Pipeline Hazard (Back-to-Back)
        $display("\n--- Test 3: Pipeline Hazard ---");
        send_req(10'h50, 0, 0); // Init
        repeat(3) @(posedge clk);
        
        @(posedge clk);
        mode <= 1; ext_wr_if.en <= 1; ext_wr_if.we <= 1; ext_wr_if.wdata <= 10;
        ext_wr_if.addr <= 10'h50;
        @(posedge clk); ext_wr_if.addr <= 10'h50;
        @(posedge clk); ext_wr_if.addr <= 10'h50;
        @(posedge clk); ext_wr_if.addr <= 10'h50;
        @(posedge clk); ext_wr_if.en <= 0; ext_wr_if.we <= 0;
        
        repeat(10) @(posedge clk);
        check_result(10'h50, 40);

        // TEST 4: Mixed Address
        $display("\n--- Test 4: Mixed Address Stress ---");
        @(posedge clk);
        mode <= 1; ext_wr_if.en <= 1; ext_wr_if.we <= 1;
        ext_wr_if.addr <= 10'h10; ext_wr_if.wdata <= 10;
        @(posedge clk);
        ext_wr_if.addr <= 10'h20; ext_wr_if.wdata <= 20;
        @(posedge clk);
        ext_wr_if.addr <= 10'h10; ext_wr_if.wdata <= 5;
        @(posedge clk); ext_wr_if.en <= 0;

        repeat(10) @(posedge clk);
        check_result(10'h10, 165);
        check_result(10'h20, 220);

        // TEST 5: Simultaneous R/W
        $display("\n--- Test 5: Simultaneous R/W ---");
        @(posedge clk);
        mode <= 0; 
        ext_wr_if.en <= 1; ext_wr_if.we <= 1; ext_wr_if.addr <= 10'h80; ext_wr_if.wdata <= 64'hDEAD_BEEF;
        ext_rd_if.en <= 1; ext_rd_if.addr <= 10'h10;
        @(posedge clk);
        ext_wr_if.en <= 0; ext_wr_if.we <= 0; ext_rd_if.en <= 0;
        
        #1;
        if (ext_rd_if.rdata !== 64'd165) $error("[FAIL] Sim Read Error");
        else $display("[PASS] Sim Read OK");
        
        repeat(5) @(posedge clk);
        check_result(10'h80, 64'hDEAD_BEEF);

        // TEST 6: Accumulate Robustness
        $display("\n--- Test 6: Accumulate Robustness ---");
        @(posedge clk);
        mode <= 1; 
        ext_wr_if.en <= 1; ext_wr_if.we <= 1; ext_wr_if.addr <= 10'h10; ext_wr_if.wdata <= 10;
        ext_rd_if.en <= 1; ext_rd_if.addr <= 10'h00; // Disturbance
        @(posedge clk);
        ext_wr_if.en <= 0; ext_rd_if.en <= 0;
        repeat(5) @(posedge clk);
        check_result(10'h10, 175);

        // --------------------------------------------------------
        // PHASE 2: 批量随机测试 (Batch Test)
        // --------------------------------------------------------
        run_batch_test(BATCH_COUNT);

        $display("\n=== All Tests Finished ===");
        $finish;
    end

endmodule