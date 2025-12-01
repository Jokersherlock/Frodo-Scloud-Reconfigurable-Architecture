`timescale 1ns / 1ps

module tb_bank_ram_subsystem_batch;

    // =======================================================
    // 1. 参数定义
    // =======================================================
    parameter NUM_SLOTS   = 2;   
    parameter FIFO_DEPTH  = 4;
    parameter NUM_BANKS   = 5;
    parameter ADDR_WIDTH  = 9;
    parameter DATA_WIDTH  = 32;
    parameter RAM_LATENCY = 2;

    // 测试轮数 (可以根据需要增加)
    parameter TEST_ITERATIONS = 10000; 

    // =======================================================
    // 2. 接口与信号
    // =======================================================
    logic clk;
    logic rstn;

    // 物理接口 (静态硬件连线)
    Bank_Cmd_If  cmd_if[NUM_SLOTS]  (clk, rstn);
    Bank_Data_If data_if[NUM_SLOTS] (clk, rstn);

    // 虚接口 (动态软件句柄)
    virtual Bank_Cmd_If  v_cmd_if[NUM_SLOTS];
    virtual Bank_Data_If v_data_if[NUM_SLOTS];

    // =======================================================
    // 3. DUT 实例化
    // =======================================================
    bank_ram_subsystem #(
        .NUM_SLOTS   (NUM_SLOTS),
        .FIFO_DEPTH  (FIFO_DEPTH),
        .NUM_BANKS   (NUM_BANKS),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .RAM_LATENCY (RAM_LATENCY)
    ) u_dut (
        .clk        (clk),
        .rstn       (rstn),
        .cmd_slots  (cmd_if), 
        .data_slots (data_if)
    );

    // =======================================================
    // 4. 基础设置 (时钟 & VIF 连接)
    // =======================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 使用 generate 块解决 "Index not constant" 问题
    genvar k;
    generate
        for (k = 0; k < NUM_SLOTS; k++) begin : vif_assign
            initial begin
                v_cmd_if[k]  = cmd_if[k];
                v_data_if[k] = data_if[k];
            end
        end
    endgenerate

    // =======================================================
    // 5. Scoreboard (参考模型)
    // =======================================================
    
    // 【关键修复】：定义为 Packed Array (合并数组)
    // 格式：logic [NUM_BANKS-1:0][DATA_WIDTH-1:0]
    // 这样才能直接赋值给 Interface 里的 wdata
    typedef logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] row_t;
    
    // 关联数组 (Associative Array) 模拟稀疏内存
    // Key: 9-bit Address, Value: row_t
    row_t ref_mem [int]; 

    // 统计变量
    int error_count = 0;
    int success_count = 0;

    // =======================================================
    // 6. 驱动与监测任务 (Driver & Monitor Tasks)
    // =======================================================

    // --- 复位任务 ---
    task sys_reset();
        rstn = 0;
        for(int i=0; i<NUM_SLOTS; i++) begin
            v_cmd_if[i].valid = 0; v_cmd_if[i].rw = 0; 
            v_cmd_if[i].mask = 0; v_cmd_if[i].addr = 0;
            v_data_if[i].wvalid = 0;
            v_data_if[i].wdata = '0; 
        end
        ref_mem.delete(); // 清空参考模型
        repeat(10) @(posedge clk);
        rstn = 1;
        repeat(5) @(posedge clk);
    endtask

    // --- 写任务 (Driver) ---
    task drive_write(
        input int slot,
        input logic [4:0] mask,
        input logic [8:0] addr,
        input row_t wdata_payload
    );
        // 1. 更新 Scoreboard
        if (!ref_mem.exists(addr)) begin
            ref_mem[addr] = '0; // 初始化全0
        end
        
        // 模拟掩码写
        for(int b=0; b<NUM_BANKS; b++) begin
            if (mask[b]) begin
                // 这里可以用 [b] 索引 Packed Array
                ref_mem[addr][b] = wdata_payload[b];
            end
        end

        // 2. 驱动 RTL (下降沿驱动，确保 Setup Time)
        @(negedge clk);
        v_cmd_if[slot].valid = 1;
        v_cmd_if[slot].rw    = 1; // Write
        v_cmd_if[slot].mask  = mask;
        v_cmd_if[slot].addr  = addr;
        
        v_data_if[slot].wvalid = 1;
        v_data_if[slot].wdata  = wdata_payload; // 类型匹配，直接赋值

        // 3. 握手等待 (Cmd 和 Data 独立等待)
        fork
            begin
                do @(posedge clk); while(v_cmd_if[slot].ready == 0);
                // 握手成功，下降沿撤销 (确保 Hold Time)
                @(negedge clk); v_cmd_if[slot].valid = 0;
            end
            begin
                do @(posedge clk); while(v_data_if[slot].wready == 0);
                // 握手成功，下降沿撤销
                @(negedge clk); v_data_if[slot].wvalid = 0;
            end
        join
    endtask

    // --- 读并校验任务 (Monitor + Checker) ---
    task verify_read(
        input int slot,
        input logic [4:0] mask,
        input logic [8:0] addr
    );
        // 1. 驱动读请求
        @(negedge clk);
        v_cmd_if[slot].valid = 1;
        v_cmd_if[slot].rw    = 0; // Read
        v_cmd_if[slot].mask  = mask;
        v_cmd_if[slot].addr  = addr;

        do @(posedge clk); while(v_cmd_if[slot].ready == 0);
        @(negedge clk); v_cmd_if[slot].valid = 0;

        // 2. 等待数据并校验
        fork : wait_read_check
            // 线程A: 数据接收与比对
            begin
                row_t exp_data;
                // 从 Scoreboard 获取期望值
                if (ref_mem.exists(addr)) exp_data = ref_mem[addr];
                else exp_data = '0;

                // 轮询 rvalid (比 wait 更稳定)
                while(v_data_if[slot].rvalid !== 1'b1) begin
                    @(posedge clk);
                end
                
                // 下降沿采样对比，避开跳变沿
                @(negedge clk);
                
                for(int b=0; b<NUM_BANKS; b++) begin
                    if (mask[b]) begin
                        if (v_data_if[slot].rdata[b] !== exp_data[b]) begin
                            $error("[ERROR] Iteration Mismatch! Addr:0x%x Bank:%0d | Exp:0x%h Got:0x%h", 
                                   addr, b, exp_data[b], v_data_if[slot].rdata[b]);
                            error_count++;
                        end else begin
                            success_count++;
                        end
                    end
                end
            end

            // 线程B: 看门狗 (防止读挂死)
            begin
                repeat(100) @(posedge clk);
                $error("[TIMEOUT] Slot %0d Read Timeout at Addr 0x%x", slot, addr);
                error_count++;
                // 强制结束 wait_read_check 里的所有线程
                disable wait_read_check;
            end
        join_any
        
        // 如果线程A正常完成，也要 disable 掉线程B
        disable wait_read_check;
    endtask

    // =======================================================
    // 7. 批量测试主流程
    // =======================================================
    initial begin
        // --- 关键：防止 Time 0 空指针竞争 ---
        // 必须等 generate 里的 initial 块把 v_cmd_if 赋值好
        #10;
        
        sys_reset();

        $display("\n=======================================================");
        $display("STARTING BATCH RANDOM TEST (%0d Iterations)", TEST_ITERATIONS);
        $display("=======================================================\n");

        for (int i = 0; i < TEST_ITERATIONS; i++) begin
            // --- 随机变量 ---
            int          op_type; // 0:Write, 1:Read
            int          slot;
            logic [4:0]  mask;
            logic [8:0]  addr;
            row_t        wdata;

            // --- 随机化约束 ---
            void'(std::randomize(op_type, slot, mask, addr, wdata) with {
                op_type dist {0:=60, 1:=40}; // 60% 写，40% 读
                slot    inside {[0:NUM_SLOTS-1]};
                mask    != 0; // 至少操作一个 Bank
            });

            // --- 执行 ---
            if (op_type == 0) begin
                drive_write(slot, mask, addr, wdata);
            end else begin
                verify_read(slot, mask, addr);
            end

            // --- 进度打印 ---
            if (i > 0 && i % 1000 == 0) 
                $display("[%0t] Progress: %0d / %0d done. Errors: %0d", $time, i, TEST_ITERATIONS, error_count);
            
            // 错误过多提前终止 (Fail-Fast)
            if (error_count > 10) begin
                $display("\n[ABORT] Too many errors (%0d). Stopping test.", error_count);
                break;
            end
        end

        // =======================================================
        // 8. 最终报告
        // =======================================================
        $display("\n=======================================================");
        $display("TEST FINISHED");
        $display("Total Iterations: %0d", TEST_ITERATIONS);
        $display("Total Data Checks: %0d", success_count + error_count);
        $display("SUCCESS: %0d", success_count);
        $display("ERRORS : %0d", error_count);
        
        if (error_count == 0) 
            $display("\nRESULT: [PASSED] - System is Robust!");
        else 
            $display("\nRESULT: [FAILED] - Check errors above.");
        $display("=======================================================");
        
        $finish;
    end

endmodule