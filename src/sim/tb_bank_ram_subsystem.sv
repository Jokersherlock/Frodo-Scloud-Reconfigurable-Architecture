`timescale 1ns / 1ps

module tb_bank_ram_subsystem;

    // =======================================================
    // 1. 参数定义
    // =======================================================
    parameter NUM_SLOTS   = 2;
    parameter FIFO_DEPTH  = 4;
    parameter NUM_BANKS   = 5;
    parameter ADDR_WIDTH  = 9;
    parameter DATA_WIDTH  = 32;
    parameter RAM_LATENCY = 2;

    // =======================================================
    // 2. 物理信号与接口实例化
    // =======================================================
    logic clk;
    logic rstn;

    // 物理接口 (静态硬件)
    Bank_Cmd_If  cmd_if[NUM_SLOTS]  (clk, rstn);
    Bank_Data_If data_if[NUM_SLOTS] (clk, rstn);

    // =======================================================
    // 3. 虚接口定义 (动态句柄)
    // =======================================================
    virtual Bank_Cmd_If  v_cmd_if[NUM_SLOTS];
    virtual Bank_Data_If v_data_if[NUM_SLOTS];

    // =======================================================
    // 4. DUT 实例化
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
    // 5. 时钟生成与虚接口连接 (关键修复)
    // =======================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 使用 generate 块进行静态展开连接
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
    // 6. 辅助任务 (Tasks)
    // =======================================================

    // --- Task: 复位 ---
    task sys_reset();
        $display("[%0t] System Reset...", $time);
        rstn = 0;
        // 这里可以使用运行时变量 i，因为 v_cmd_if 已经是软件对象了
        for(int i=0; i<NUM_SLOTS; i++) begin
            v_cmd_if[i].valid = 0; 
            v_cmd_if[i].rw = 0; 
            v_cmd_if[i].mask = 0; 
            v_cmd_if[i].addr = 0;
            v_data_if[i].wvalid = 0;
            v_data_if[i].wdata = 0;
        end
        #50;
        rstn = 1;
        @(posedge clk);
        $display("[%0t] Reset Done.", $time);
    endtask

// --- Task: 单次写入 (时序安全版) ---
    task master_write(
        input int slot_id,
        input logic [4:0] mask,
        input logic [8:0] addr,
        input logic [31:0] base_data
    );
        // 1. 启动阶段：在下降沿驱动信号 (Setup Time充足)
        @(negedge clk);
        v_cmd_if[slot_id].valid = 1;
        v_cmd_if[slot_id].rw    = 1; 
        v_cmd_if[slot_id].mask  = mask;
        v_cmd_if[slot_id].addr  = addr;

        v_data_if[slot_id].wvalid = 1;
        for(int k=0; k<5; k++) begin
            v_data_if[slot_id].wdata[k] = base_data + k;
        end

        // 2. 握手阶段：独立等待 Cmd 和 Data 的 Ready
        fork
            // 线程 A: 处理命令通道
            begin
                // 等待直到在上升沿检测到 Ready
                do begin
                    @(posedge clk);
                end while (v_cmd_if[slot_id].ready == 0);
                
                // 关键点：握手成功后，坚持到下降沿再撤销
                // 这样保证了 valid 在刚才那个上升沿是稳稳的高电平
                @(negedge clk); 
                v_cmd_if[slot_id].valid = 0;
            end

            // 线程 B: 处理数据通道
            begin
                do begin
                    @(posedge clk);
                end while (v_data_if[slot_id].wready == 0);
                
                // 关键点：同样坚持到下降沿
                @(negedge clk); 
                v_data_if[slot_id].wvalid = 0;
            end
        join

        $display("[%0t] Slot %0d Write Handshake Done. Addr=0x%x", $time, slot_id, addr);
    endtask

// --- Task: 单次读取并检查 (时序安全版) ---
    task master_read_check(
        input int slot_id,
        input logic [4:0] mask,
        input logic [8:0] addr,
        input logic [31:0] expect_base_data
    );
        // 1. 发起读请求 (下降沿驱动)
        @(negedge clk);
        v_cmd_if[slot_id].valid = 1;
        v_cmd_if[slot_id].rw    = 0; // Read
        v_cmd_if[slot_id].mask  = mask;
        v_cmd_if[slot_id].addr  = addr;

        // 2. 等待命令被接受
        do begin
            @(posedge clk);
        end while (v_cmd_if[slot_id].ready == 0);

        // 3. 撤销读请求 (下降沿撤销)
        @(negedge clk);
        v_cmd_if[slot_id].valid = 0;

        // 4. 等待数据返回 (带超时保护)
        fork : wait_read_logic
            // 线程 A: 快乐路径 - 等数据并检查
            begin
                // 等待 rvalid 变高
                // 注意：这里用 wait 是电平触发，一旦变为1立即执行
                // OLD: wait(v_data_if[slot_id].rvalid == 1); 
                // 这种写法容易受 Delta Cycle 影响错过信号

                // NEW: 在每个时钟上升沿检查 rvalid
                // 只要 rvalid 不是 1，就一直等下一个时钟
                while (v_data_if[slot_id].rvalid !== 1'b1) begin
                    @(posedge clk);
                end
                
                // 为了看清数据，我们最好在时钟边沿采样
                @(negedge clk); 
                
                $display("[%0t] Slot %0d Read Return Received.", $time, slot_id);
                // 循环检查 5 个 Bank 的数据
                for(int k=0; k<5; k++) begin
                    if (mask[k]) begin
                        if (v_data_if[slot_id].rdata[k] !== (expect_base_data + k)) begin
                            $error("ERROR! Bank %0d Mismatch. Addr: %x, Exp: %x, Got: %x", 
                                k, addr, expect_base_data+k, v_data_if[slot_id].rdata[k]);
                        end else begin
                            $display("      Bank %0d Match: %x", k, v_data_if[slot_id].rdata[k]);
                        end
                    end
                end
            end

            // 线程 B: 悲观路径 - 超时看门狗
            begin
                repeat(50) @(posedge clk); // 等待 50 个周期
                $error("ERROR! Slot %0d Read Timeout at Addr 0x%x", slot_id, addr);
                // 这里的 disable 会强制结束整个 fork 块，停止线程 A
            end
        join_any
        
        disable wait_read_logic; // 确保杀掉另一个没跑完的线程
    endtask

    logic dump_trigger = 0;//触发ram dump的信号
    // =======================================================
    // 7. 主测试流程
    // =======================================================
    initial begin
        // 稍微等待，确保 generate 中的 initial 块执行完毕
        #1; 

        // --- Step 1: 复位 ---
        sys_reset();

        // --- Step 2: Slot 0 基本读写测试 ---
        $display("\n=== Test 1: Slot 0 Basic RW ===");
        master_write(1, 5'b11111, 9'd10, 32'hAAAA_0000);
        #100
        dump_trigger = 1;
        master_read_check(1, 5'b11111, 9'd10, 32'hAAAA_0000);

        // // --- Step 3: Slot 1 测试 (优先级低) ---
        // $display("\n=== Test 2: Slot 1 Basic RW ===");
        // master_write(1, 5'b00001, 9'd50, 32'hCCCC_0000);
        // master_read_check(1, 5'b00001, 9'd50, 32'hCCCC_0000);

        // // --- Step 4: 并发仲裁测试 ---
        // $display("\n=== Test 3: Arbitration ===");
        
        // @(negedge clk);
        // // Slot 0 请求
        // v_cmd_if[0].valid = 1; v_cmd_if[0].rw = 1; v_cmd_if[0].addr = 100; v_cmd_if[0].mask = 5'h1F;
        // v_data_if[0].wvalid = 1; v_data_if[0].wdata = {5{32'h1111_1111}};

        // // Slot 1 请求
        // v_cmd_if[1].valid = 1; v_cmd_if[1].rw = 1; v_cmd_if[1].addr = 200; v_cmd_if[1].mask = 5'h1F;
        // v_data_if[1].wvalid = 1; v_data_if[1].wdata = {5{32'h2222_2222}};

        // // 检查仲裁结果 (下一拍 Ready 应该只给 Slot 0)
        // @(posedge clk); #1;
        // if (v_cmd_if[0].ready && !v_cmd_if[1].ready) 
        //     $display("SUCCESS: Slot 0 won arbitration.");
        // else 
        //     $error("FAIL: Arbitration error. Ready0=%b, Ready1=%b", v_cmd_if[0].ready, v_cmd_if[1].ready);

        // // 撤销 Slot 0
        // @(negedge clk);
        // v_cmd_if[0].valid = 0; v_data_if[0].wvalid = 0;

        // // 检查 Slot 1 是否接管
        // @(posedge clk); #1;
        // if (v_cmd_if[1].ready) 
        //     $display("SUCCESS: Slot 1 granted access.");
        // else 
        //     $error("FAIL: Slot 1 not granted access.");

        // // 撤销 Slot 1
        // @(negedge clk);
        // v_cmd_if[1].valid = 0; v_data_if[1].wvalid = 0;

        #100;
        $display("\n=== All Tests Finished ===");
        dump_trigger = 0;
        $finish;
    end

endmodule