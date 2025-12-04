`timescale 1ns/1ps

module tb_accum_zone;

    // ============================================================
    // 1. 参数定义
    // ============================================================
    parameter NUM_SLOTS  = 4;   // 模拟 DMA(0) 和 Frodo(1)
    parameter FIFO_DEPTH = 4;
    parameter NUM_BANKS  = 4;   // 4个Bank，对应SIMD宽度
    parameter ADDR_WIDTH = 9;
    parameter DATA_WIDTH = 64;
    parameter ZONE_WIDTH = 2;   // Zone ID Width
    
    parameter BATCH_COUNT = 2000; // 批量测试次数

    // ============================================================
    // 2. 信号与接口
    // ============================================================
    logic clk, rstn;

    // 实例化 2 套接口 (Slot 0, Slot 1)
    Accum_Cmd_If #(
        .NUM_BANKS(NUM_BANKS), .ADDR_WIDTH(ADDR_WIDTH), .ZONE_WIDTH(ZONE_WIDTH)
    ) cmd_if[NUM_SLOTS] (clk, rstn);

    Accum_Data_If #(
        .NUM_BANKS(NUM_BANKS), .DATA_WIDTH(DATA_WIDTH)
    ) data_if[NUM_SLOTS] (clk, rstn);

    // 虚接口数组 (用于 Task 中动态索引)
    virtual Accum_Cmd_If  v_cmd_if[NUM_SLOTS];
    virtual Accum_Data_If v_data_if[NUM_SLOTS];

    // ============================================================
    // 3. DUT 实例化
    // ============================================================
    Accum_Zone #(
        .NUM_SLOTS(NUM_SLOTS),
        .FIFO_DEPTH(FIFO_DEPTH),
        .NUM_BANKS(NUM_BANKS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ZONE_WIDTH(ZONE_WIDTH)
    ) u_dut (
        .clk        (clk),
        .rstn       (rstn),
        .slave_cmd_ports  (cmd_if),
        .slave_data_ports (data_if)
    );

    // ============================================================
    // 4. 初始化与时钟
    // ============================================================
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz

    // 连接虚接口
    genvar k;
    generate
        for (k = 0; k < NUM_SLOTS; k++) begin : vif
            initial begin
                v_cmd_if[k]  = cmd_if[k];
                v_data_if[k] = data_if[k];
            end
        end
    endgenerate

    // ============================================================
    // 5. 辅助任务 (Driver Tasks)
    // ============================================================

    // 复位任务
    task automatic sys_reset();
        $display("[%0t] Resetting System...", $time);
        rstn = 0;
        for(int i=0; i<NUM_SLOTS; i++) begin
            v_cmd_if[i].wr_valid = 0; v_cmd_if[i].rd_valid = 0;
            v_cmd_if[i].accum_en = 0; v_cmd_if[i].wr_mask = 0; v_cmd_if[i].rd_mask = 0;
            v_cmd_if[i].wr_addr = 0;  v_cmd_if[i].rd_addr = 0;
            v_cmd_if[i].wr_zone_id = 0; v_cmd_if[i].rd_zone_id = 0;
            v_data_if[i].wvalid = 0; v_data_if[i].wdata = '0;
        end
        repeat(10) @(posedge clk);
        rstn = 1;
        repeat(5) @(posedge clk);
        $display("[%0t] Reset Done.", $time);
    endtask

    // 写任务 (带超时保护 - SIMD Data)
    task automatic master_write(
        input int slot, 
        input logic [ADDR_WIDTH-1:0] addr, 
        input logic [NUM_BANKS-1:0] mask, 
        input logic [63:0] base_data, 
        input logic is_acc
    );
        @(negedge clk);
        v_cmd_if[slot].wr_valid   = 1;
        v_cmd_if[slot].accum_en   = is_acc;
        v_cmd_if[slot].wr_mask    = mask;
        v_cmd_if[slot].wr_addr    = addr;
        
        v_data_if[slot].wvalid    = 1;
        for(int b=0; b<NUM_BANKS; b++) begin
            v_data_if[slot].wdata[b] = base_data + b; 
        end

        // 使用 fork-join 分别等待 Cmd 和 Data 的 Ready
        fork : write_handshake
            begin
                int timeout = 0;
                while (v_cmd_if[slot].wr_ready !== 1'b1) begin
                    @(posedge clk); timeout++;
                    if (timeout > 50) begin $error("[%0t] [TIMEOUT] Slot %0d waiting for WR_READY!", $time, slot); disable write_handshake; end
                end
                @(negedge clk); v_cmd_if[slot].wr_valid = 0;
            end
            begin
                int timeout = 0;
                while (v_data_if[slot].wready !== 1'b1) begin
                    @(posedge clk); timeout++;
                    if (timeout > 50) begin $error("[%0t] [TIMEOUT] Slot %0d waiting for W_READY!", $time, slot); disable write_handshake; end
                end
                @(negedge clk); v_data_if[slot].wvalid = 0;
            end
        join
    endtask

    // 读请求任务 (带超时保护)
    task automatic master_read_req(input int slot, input logic [ADDR_WIDTH-1:0] addr, input logic [NUM_BANKS-1:0] mask);
        @(negedge clk);
        v_cmd_if[slot].rd_valid = 1;
        v_cmd_if[slot].rd_mask  = mask;
        v_cmd_if[slot].rd_addr  = addr;

        fork : read_handshake
            begin
                int timeout = 0;
                while (v_cmd_if[slot].rd_ready !== 1'b1) begin
                    @(posedge clk); timeout++;
                    if (timeout > 50) begin $error("[%0t] [TIMEOUT] Slot %0d waiting for RD_READY!", $time, slot); disable read_handshake; end
                end
                @(negedge clk); 
                v_cmd_if[slot].rd_valid = 0;
            end
        join
    endtask

    // 检查读数据 (Latency = 2 修正)
    task automatic check_read_data(input int slot, input logic [63:0] exp_base, input logic [NUM_BANKS-1:0] mask);
        fork : wait_data
            begin
                // 等待 rvalid
                while(v_data_if[slot].rvalid !== 1'b1) @(posedge clk);
                
                @(negedge clk); // 采样
                
                for(int b=0; b<NUM_BANKS; b++) begin
                    if (mask[b]) begin
                        if (v_data_if[slot].rdata[b] !== (exp_base + b)) begin
                            $error("[FAIL] Slot %0d Bank %0d: Exp %h Got %h", slot, b, exp_base+b, v_data_if[slot].rdata[b]);
                        end else begin
                            // $display("[PASS] Slot %0d Bank %0d: Got %h", slot, b, v_data_if[slot].rdata[b]);
                        end
                    end
                end
            end
            begin
                repeat(100) @(posedge clk);
                $error("[TIMEOUT] Slot %0d waiting for RVALID!", slot);
                disable wait_data;
            end
        join_any
        disable wait_data;
    endtask

    // ============================================================
    // 6. 批量随机测试基础设施 (Batch Infrastructure)
    // ============================================================
    
    // 定义一行数据 (Packed Array)
    typedef logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] row_t;
    
    // 关联数组作为参考模型 (Key=Addr)
    row_t ref_mem [int]; 

    int batch_err_count = 0;

    task automatic run_batch_test(input int iterations);
        $display("\n========================================");
        $display("STARTING BATCH TEST (%0d iterations)", iterations);
        $display("========================================");

        sys_reset();

        // 2. 硬件内存清洗 (Scrubbing)
        $display("[%0t] Scrubbing Memory (Init to 0+b)...", $time);
        ref_mem.delete();
        for (int i = 0; i < (1<<ADDR_WIDTH); i++) begin
            // 硬件写：master_write 内部会自动将数据设为 base_data + b
            master_write(0, i[ADDR_WIDTH-1:0], 4'b1111, 64'd0, 0);
            
            // 【修正点】：Scoreboard 初始化必须与硬件写入值一致 (0+b)
            for (int b=0; b<NUM_BANKS; b++) begin
                ref_mem[i][b] = 64'd0 + b; 
            end
        end
        // 等待写操作完成
        repeat(10) @(posedge clk);
        $display("[%0t] Scrubbing Done.", $time);
        
        // 3. 随机循环
        for (int i = 0; i < iterations; i++) begin
            int          slot;
            int          op_type; 
            logic [4:0]  mask;    
            logic [8:0]  addr;
            logic [63:0] base_data;
            logic        is_acc;
            
            void'(std::randomize(slot, op_type, mask, addr, base_data, is_acc) with {
                slot    inside {[0:NUM_SLOTS-1]};
                op_type dist {0:=60, 1:=40}; 
                mask    inside {[1:15]};     // 不允许全0
                is_acc  dist {0:=50, 1:=50};
            });

            if (op_type == 0) begin
                // >>> WRITE / ACCUMULATE <<<
                
                if (!ref_mem.exists(addr)) begin
                    // 初始化不存在的地址
                    for (int b=0; b<NUM_BANKS; b++) ref_mem[addr][b] = 64'd0 + b;
                end
                
                for (int b=0; b<NUM_BANKS; b++) begin
                    if (mask[b]) begin
                        logic [63:0] wr_val = base_data + b;
                        
                        if (is_acc) begin
                            // Scoreboard SIMD 16-bit 加法
                            logic [DATA_WIDTH-1:0] current_val = ref_mem[addr][b];
                            logic [DATA_WIDTH-1:0] next_val;
                            
                            for (int l = 0; l < DATA_WIDTH/16; l++) begin
                                next_val[l*16 +: 16] = current_val[l*16 +: 16] + wr_val[l*16 +: 16];
                            end
                            ref_mem[addr][b] = next_val;
                        end else begin
                            ref_mem[addr][b] = wr_val;
                        end
                    end
                end

                master_write(slot, addr, mask[3:0], base_data, is_acc);

            end else begin
                // >>> READ & CHECK <<<
                
                row_t exp_row;
                if (ref_mem.exists(addr)) exp_row = ref_mem[addr];
                else begin
                    // 默认值 (Scrubbing 后是 0+b)
                    for(int b=0; b<NUM_BANKS; b++) exp_row[b] = 64'd0 + b;
                end

                master_read_req(slot, addr, mask[3:0]);

                fork : batch_read_check
                    begin
                        while(v_data_if[slot].rvalid !== 1'b1) @(posedge clk);
                        @(negedge clk); 
                        
                        for (int b=0; b<NUM_BANKS; b++) begin
                            if (mask[b]) begin
                                if (v_data_if[slot].rdata[b] !== exp_row[b]) begin
                                    $error("[BATCH FAIL] Iter:%0d Slot:%0d Addr:0x%x Bank:%0d | Exp:0x%h Got:0x%h", 
                                           i, slot, addr, b, exp_row[b], v_data_if[slot].rdata[b]);
                                    batch_err_count++;
                                end
                            end
                        end
                    end
                    begin
                        repeat(100) @(posedge clk);
                        $error("[BATCH TIMEOUT] Slot %0d Read Addr 0x%x", slot, addr);
                        batch_err_count++;
                        disable batch_read_check;
                    end
                join_any
                disable batch_read_check;
            end

            repeat(5) @(posedge clk);

            if (i > 0 && i % 500 == 0) 
                $display("[%0t] Batch Progress: %0d/%0d | Errors: %0d", $time, i, iterations, batch_err_count);
        end

        if (batch_err_count == 0)
            $display("\n>>> BATCH TEST PASSED! <<<");
        else
            $display("\n>>> BATCH TEST FAILED! Errors: %0d <<<", batch_err_count);
    endtask

    // ============================================================
    // 7. 主流程执行
    // ============================================================
    initial begin
        #10; 
        sys_reset();

        // --------------------------------------------------------
        // PHASE 1: 定向测试 (Directed Tests)
        // --------------------------------------------------------
        $display("\n--- PHASE 1: Directed Tests ---");
        
        // Test 1: Basic RW
        master_write(0, 9'h10, 4'b1111, 64'hA000, 0); 
        repeat(5) @(posedge clk);
        master_read_req(0, 9'h10, 4'b1111);
        check_read_data(0, 64'hA000, 4'b1111);

        // Test 2: Masked Write
        master_write(0, 9'h20, 4'b0101, 64'hB000, 0);
        repeat(5) @(posedge clk);
        master_read_req(0, 9'h20, 4'b0101);
        check_read_data(0, 64'hB000, 4'b0101);

        // Test 3: Arbitration (Write Conflict)
        @(negedge clk);
        v_cmd_if[0].wr_valid = 1; v_cmd_if[0].accum_en = 0; v_cmd_if[0].wr_mask = 4'hf; v_cmd_if[0].wr_addr = 9'h30;
        v_data_if[0].wvalid = 1;  v_data_if[0].wdata[0] = 64'hC000; 
        v_cmd_if[1].wr_valid = 1; v_cmd_if[1].accum_en = 0; v_cmd_if[1].wr_mask = 4'hf; v_cmd_if[1].wr_addr = 9'h40;
        v_data_if[1].wvalid = 1;  v_data_if[1].wdata[0] = 64'hD000;

        @(posedge clk); #1;
        if (v_cmd_if[0].wr_ready && !v_cmd_if[1].wr_ready) 
            $display("[PASS] Arbiter chose Slot 0");
        else 
            $error("[FAIL] Arbiter Error");

        @(negedge clk);
        v_cmd_if[0].wr_valid = 0; v_data_if[0].wvalid = 0; // Slot 0 撤销
        
        @(posedge clk); #1;
        if (v_cmd_if[1].wr_ready) $display("[PASS] Slot 1 granted");
        
        @(negedge clk);
        v_cmd_if[1].wr_valid = 0; v_data_if[1].wvalid = 0; // Slot 1 撤销

        // 【关键】：复位以清除 Test 3 残留
        sys_reset();

        // Test 4: Read Return Routing
        master_write(1, 9'h50, 4'b1111, 64'hE000, 0);
        repeat(5) @(posedge clk);
        master_read_req(1, 9'h50, 4'b1111);

        fork
            check_read_data(1, 64'hE000, 4'b1111); // Slot 1 应该收到
            begin
                repeat(2) @(posedge clk); 
                while(v_data_if[1].rvalid !== 1'b1) @(posedge clk); 
                if (v_data_if[0].rvalid == 1) $error("[FAIL] Slot 0 leaked data!");
                else $display("[PASS] Slot 0 ignored data correctly.");
            end
        join

        // --------------------------------------------------------
        // PHASE 2: 批量测试 (Batch Test)
        // --------------------------------------------------------
        $display("\n--- PHASE 2: Batch Random Tests ---");
        run_batch_test(BATCH_COUNT);

        $display("\n=== All Tests Finished ===");
        $finish;
    end

endmodule