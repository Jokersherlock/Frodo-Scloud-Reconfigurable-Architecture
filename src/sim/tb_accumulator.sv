`timescale 1ns/1ps

module tb_accumulator;

    // ============================================================
    // 1. 参数与信号定义
    // ============================================================
    parameter ADDR_WIDTH = 9;
    parameter DATA_WIDTH = 64;

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
    // 4. 辅助 Task (让主测试流程更清晰)
    // ============================================================
    
    // 发送写/累加请求 (单拍脉冲)
    task send_req(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data, input logic is_accumulate);
        // 在时钟下降沿驱动，确保 setup time，或者直接在上升沿后驱动
        @(posedge clk);
        mode             <= is_accumulate;
        ext_wr_if.en     <= 1;
        ext_wr_if.we     <= 1;
        ext_wr_if.addr   <= addr;
        ext_wr_if.wdata  <= data;
        
        @(posedge clk);
        // 撤销请求
        ext_wr_if.en     <= 0;
        ext_wr_if.we     <= 0;
        // 保持数据总线为0 (可选，方便看波形)
        ext_wr_if.wdata  <= '0; 
    endtask

    // 发起读请求并检查结果
    task check_result(input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] expected_val);
        @(posedge clk);
        ext_rd_if.en   <= 1;
        ext_rd_if.addr <= addr;
        
        @(posedge clk);
        ext_rd_if.en   <= 0; // 读请求结束

        // RAM Latency = 1，所以数据在下一个周期有效
        // 此时 ext_rd_if.rdata 应该已经出来了
        @(posedge clk); 
        #1; // 稍微延时一点点进行采样，确保稳定
        
        if (ext_rd_if.rdata !== expected_val) begin
            $error("[FAIL] Addr 0x%h: Expected %0d, Got %0d", addr, expected_val, ext_rd_if.rdata);
        end else begin
            $display("[PASS] Addr 0x%h: Read %0d Correctly", addr, ext_rd_if.rdata);
        end
    endtask

    // ============================================================
    // 5. 主测试流程
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
        // TEST 1: 覆盖模式 (Mode 0) - 初始化内存
        // --------------------------------------------------------
        $display("\n--- Test 1: Overwrite Mode (Init) ---");
        // 向地址 0x10 写入 100
        send_req(.addr(10'h10), .data(32'd100), .is_accumulate(0));
        
        // 向地址 0x20 写入 200
        send_req(.addr(10'h20), .data(32'd200), .is_accumulate(0));

        // 等待流水线完成 (至少3拍)
        repeat(5) @(posedge clk);
        
        // 检查写入结果
        check_result(10'h10, 100);
        check_result(10'h20, 200);

        // --------------------------------------------------------
        // TEST 2: 基础累加 (Mode 1) - 无冲突
        // --------------------------------------------------------
        $display("\n--- Test 2: Basic Accumulate (No Hazard) ---");
        // 地址 0x10 原值 100，累加 50 -> 期望 150
        send_req(.addr(10'h10), .data(32'd50), .is_accumulate(1));
        
        repeat(5) @(posedge clk);
        check_result(10'h10, 150);

        // --------------------------------------------------------
        // TEST 3: 流水线冲突测试 (Back-to-Back Hazard) - 核心测试
        // --------------------------------------------------------
        $display("\n--- Test 3: Pipeline Hazard (Bypass Check) ---");
        // 目标：对地址 0x50 进行连续累加
        // 1. 先初始化为 0
        send_req(.addr(10'h50), .data(32'd0), .is_accumulate(0));
        repeat(3) @(posedge clk); // 确保初始化写入完成

        // 2. 连续发射 4 个累加指令，每个加 10
        // 期望结果：0 -> 10 -> 20 -> 30 -> 40
        $display("Sending 4 consecutive accumulate requests...");
        
        // 这里手动写，为了实现背靠背 (Back-to-Back) 的满流水效果
        @(posedge clk);
        mode            <= 1;
        ext_wr_if.en    <= 1; 
        ext_wr_if.we    <= 1;
        ext_wr_if.wdata <= 32'd10; // 增量 10

        ext_wr_if.addr  <= 10'h50; // Req 1
        @(posedge clk);
        ext_wr_if.addr  <= 10'h50; // Req 2 (Hazard with 1)
        @(posedge clk);
        ext_wr_if.addr  <= 10'h50; // Req 3 (Hazard with 2)
        @(posedge clk);
        ext_wr_if.addr  <= 10'h50; // Req 4 (Hazard with 3)
        
        @(posedge clk);
        ext_wr_if.en    <= 0;      // 结束发送
        ext_wr_if.we    <= 0;

        // 3. 等待流水线排空
        repeat(10) @(posedge clk);

        // 4. 检查结果
        // 如果旁路逻辑(History Buffer)有问题，这里读出来的可能是 10 或者 20
        // 如果正确，应该是 40
        check_result(10'h50, 40);

        // --------------------------------------------------------
        // TEST 4: 混合地址压力测试
        // --------------------------------------------------------
        $display("\n--- Test 4: Mixed Address Stress ---");
        // 同时对 A(0x10) 和 B(0x20) 操作
        // A(150) + 10 = 160
        // B(200) + 20 = 220
        // A(160) + 5  = 165
        @(posedge clk);
        mode <= 1; ext_wr_if.en <= 1; ext_wr_if.we <= 1;
        
        ext_wr_if.addr <= 10'h10; ext_wr_if.wdata <= 10;
        @(posedge clk);
        ext_wr_if.addr <= 10'h20; ext_wr_if.wdata <= 20;
        @(posedge clk);
        ext_wr_if.addr <= 10'h10; ext_wr_if.wdata <= 5; // 回头操作 A，测试历史是否混淆
        @(posedge clk);
        ext_wr_if.en <= 0;

        repeat(10) @(posedge clk);
        check_result(10'h10, 165);
        check_result(10'h20, 220);

        $display("\n=== All Tests Finished ===");
        $finish;
    end


endmodule