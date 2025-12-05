`timescale 1ns / 1ps

module tb_accum_subsystem;

    // =======================================================
    // 1. 参数定义
    // =======================================================
    parameter NUM_ROUTED_MASTERS = 1; // 例如: DMA
    parameter NUM_DIRECT_PORTS   = 4; // 固定为 4 (对应 Zone 0-3)
    parameter FIFO_DEPTH         = 4;
    parameter NUM_BANKS          = 4;
    parameter ADDR_WIDTH         = 9;
    parameter DATA_WIDTH         = 64; 
    parameter ZONE_WIDTH         = 2;
    
    // =======================================================
    // 2. 物理信号与接口实例化
    // =======================================================
    logic clk, rstn;

    // A. 路由接口
    Accum_Cmd_If #(
        .NUM_BANKS(NUM_BANKS), .ADDR_WIDTH(ADDR_WIDTH), .ZONE_WIDTH(ZONE_WIDTH)
    ) routed_cmd_if[NUM_ROUTED_MASTERS] (clk, rstn);
    
    Accum_Data_If #(
        .NUM_BANKS(NUM_BANKS), .DATA_WIDTH(DATA_WIDTH)
    ) routed_data_if[NUM_ROUTED_MASTERS] (clk, rstn);

    // B. 直连接口
    Accum_Cmd_If #(
        .NUM_BANKS(NUM_BANKS), .ADDR_WIDTH(ADDR_WIDTH), .ZONE_WIDTH(ZONE_WIDTH)
    ) direct_cmd_if[NUM_DIRECT_PORTS] (clk, rstn);

    Accum_Data_If #(
        .NUM_BANKS(NUM_BANKS), .DATA_WIDTH(DATA_WIDTH)
    ) direct_data_if[NUM_DIRECT_PORTS] (clk, rstn);

    // =======================================================
    // 3. 虚接口定义
    // =======================================================
    virtual Accum_Cmd_If  v_routed_cmd [NUM_ROUTED_MASTERS];
    virtual Accum_Data_If v_routed_data[NUM_ROUTED_MASTERS];
    
    virtual Accum_Cmd_If  v_direct_cmd [NUM_DIRECT_PORTS];
    virtual Accum_Data_If v_direct_data[NUM_DIRECT_PORTS];

    // =======================================================
    // 4. [关键修复] 信号保活锚点 (Keep-Alive Anchors)
    // =======================================================
    // 显式定义 wire 数组并连接，防止仿真器优化掉虚接口的回读路径
    // 这解决了 "波形有值但 TB 读到 0" 的问题
    logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] debug_routed_rdata [NUM_ROUTED_MASTERS];
    
    genvar k;
    generate
        for(k=0; k<NUM_ROUTED_MASTERS; k++) begin : keep_alive
            assign debug_routed_rdata[k] = routed_data_if[k].rdata;
        end
    endgenerate

    // =======================================================
    // 5. DUT 实例化
    // =======================================================
    Accum_Subsystem #(
        .FIFO_DEPTH         (FIFO_DEPTH),
        .NUM_BANKS          (NUM_BANKS),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .DATA_WIDTH         (DATA_WIDTH),
        .ZONE_WIDTH         (ZONE_WIDTH),
        .NUM_ROUTED_MASTERS (NUM_ROUTED_MASTERS)
    ) u_dut (
        .clk              (clk),
        .rstn             (rstn),
        .routed_cmd_ports (routed_cmd_if),
        .routed_data_ports(routed_data_if),
        .direct_cmd_ports (direct_cmd_if),
        .direct_data_ports(direct_data_if)
    );

    // =======================================================
    // 6. 时钟与连接
    // =======================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    genvar r;
    generate
        for (r = 0; r < NUM_ROUTED_MASTERS; r++) begin : bind_routed
            initial begin
                v_routed_cmd[r]  = routed_cmd_if[r];
                v_routed_data[r] = routed_data_if[r];
            end
        end
    endgenerate

    genvar d;
    generate
        for (d = 0; d < NUM_DIRECT_PORTS; d++) begin : bind_direct
            initial begin
                v_direct_cmd[d]  = direct_cmd_if[d];
                v_direct_data[d] = direct_data_if[d];
            end
        end
    endgenerate

    // =======================================================
    // 7. 辅助任务 (Tasks)
    // =======================================================

    // --- Task: 全局复位 ---
    task sys_reset();
        $display("[%0t] System Reset...", $time);
        rstn = 0;
        for(int i=0; i<NUM_ROUTED_MASTERS; i++) begin
            v_routed_cmd[i].wr_valid = 0; v_routed_cmd[i].rd_valid = 0;
            v_routed_cmd[i].wr_addr = 0;  v_routed_cmd[i].rd_addr = 0;
            v_routed_cmd[i].wr_mask = 0;  v_routed_cmd[i].rd_mask = 0;
            v_routed_cmd[i].accum_en = 0; v_routed_cmd[i].wr_zone_id = 0;
            v_routed_data[i].wvalid = 0;  v_routed_data[i].wdata = '0;
        end
        for(int i=0; i<NUM_DIRECT_PORTS; i++) begin
            v_direct_cmd[i].wr_valid = 0; v_direct_cmd[i].rd_valid = 0;
            v_direct_cmd[i].wr_addr = 0;  v_direct_cmd[i].rd_addr = 0;
            v_direct_cmd[i].wr_mask = 0;  v_direct_cmd[i].rd_mask = 0;
            v_direct_cmd[i].accum_en = 0; v_direct_cmd[i].wr_zone_id = 0;
            v_direct_data[i].wvalid = 0;  v_direct_data[i].wdata = '0;
        end
        #50;
        rstn = 1;
        repeat(5) @(posedge clk);
        $display("[%0t] Reset Done.", $time);
    endtask

    // --- 通用写任务 (增加了 inc_data 参数，默认为 1) ---
    task automatic master_write(
        input bit   is_routed,
        input int   port_idx,
        input int   dest_zone, 
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [NUM_BANKS-1:0]  mask,
        input logic [63:0]           base_data,
        input logic                  accum_en,
        input bit                    inc_data = 1 // 【新增】控制数据是否随 Bank ID 递增
    );
        virtual Accum_Cmd_If  cmd_if;
        virtual Accum_Data_If data_if;
        logic [ZONE_WIDTH-1:0] target_id;

        if (is_routed) begin
            cmd_if    = v_routed_cmd[port_idx];
            data_if   = v_routed_data[port_idx];
            target_id = dest_zone[ZONE_WIDTH-1:0];
        end else begin
            cmd_if    = v_direct_cmd[port_idx];
            data_if   = v_direct_data[port_idx];
            target_id = port_idx[ZONE_WIDTH-1:0]; 
        end

        @(negedge clk);
        cmd_if.wr_valid   = 1;
        cmd_if.accum_en   = accum_en; 
        cmd_if.wr_mask    = mask;
        cmd_if.wr_addr    = addr;
        cmd_if.wr_zone_id = target_id; 

        data_if.wvalid    = 1;
        for(int b=0; b<NUM_BANKS; b++) begin
            // 【修改】根据参数决定是否加 b
            data_if.wdata[b] = base_data + (inc_data ? b : 0);
        end

        fork : wr_handshake
            begin
                while (cmd_if.wr_ready !== 1'b1) @(posedge clk);
                @(negedge clk);
                cmd_if.wr_valid = 0;
            end
            begin
                while (data_if.wready !== 1'b1) @(posedge clk);
                @(negedge clk);
                data_if.wvalid = 0;
            end
        join

        if(is_routed) 
            $display("[%0t] Routed Port %0d -> Zone %0d Write Done (Acc=%b). Addr=0x%x", $time, port_idx, target_id, accum_en, addr);
        else 
            $display("[%0t] Direct Port %0d (Zone %0d) Write Done (Acc=%b). Addr=0x%x", $time, port_idx, target_id, accum_en, addr);
    endtask

    // --- 通用读检查任务 (修正版) ---
    task automatic master_read_check(
        input bit   is_routed,
        input int   port_idx,
        input int   dest_zone,
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [NUM_BANKS-1:0]  mask,
        input logic [63:0]           exp_base_data
    );
        virtual Accum_Cmd_If  cmd_if;
        virtual Accum_Data_If data_if;
        logic [ZONE_WIDTH-1:0] target_id;
        logic [63:0]           captured_data; // 本地变量存数据

        if (is_routed) begin
            cmd_if    = v_routed_cmd[port_idx];
            data_if   = v_routed_data[port_idx];
            target_id = dest_zone[ZONE_WIDTH-1:0];
        end else begin
            cmd_if    = v_direct_cmd[port_idx];
            data_if   = v_direct_data[port_idx];
            target_id = port_idx[ZONE_WIDTH-1:0];
        end

        // 1. 发起读请求
        @(negedge clk);
        cmd_if.rd_valid   = 1;
        cmd_if.rd_mask    = mask;
        cmd_if.rd_addr    = addr;
        cmd_if.rd_zone_id = target_id;

        // 2. 等待 rd_ready
        while (cmd_if.rd_ready !== 1'b1) @(posedge clk);
        @(negedge clk);
        cmd_if.rd_valid = 0;

        // 3. 等待数据并检查
        fork : rd_wait
            begin
                // 等待 Valid 变高
                while (data_if.rvalid !== 1'b1) @(posedge clk);
                
                // 【核心修改】在上升沿后稍微延时，避开 Delta Cycle 竞争
                // 此时对于 Router 的组合逻辑输出，数据绝对有效
            //#1; 

                for(int b=0; b<NUM_BANKS; b++) begin
                    if (mask[b]) begin
                        // 【核心修改】
                        // 如果是 Routed 模式，读取模块级的 wire 数组，而不是虚接口
                        if (is_routed) begin
                            captured_data = debug_routed_rdata[port_idx][b];
                        end else begin
                            captured_data = data_if.rdata[b];
                        end

                        if (captured_data !== (exp_base_data + b)) begin
                            $error("[FAIL] %s Port %0d Zone %0d Bank %0d: Exp %h Got %h", 
                                (is_routed ? "Routed":"Direct"), port_idx, target_id, b, exp_base_data+b, captured_data);
                        end
                    end
                end
                $display("[%0t] Read Check Passed. Zone %0d Addr 0x%x", $time, target_id, addr);
            end
            begin
                repeat(100) @(posedge clk);
                $error("[TIMEOUT] Read valid not received!");
                disable rd_wait;
            end
        join_any
        disable rd_wait;
    endtask

    // =======================================================
    // 8. 主测试流程
    // =======================================================
    initial begin
        #10;
        sys_reset();

        // ------------------------------------------------------------
        // Case 1: 直连端口基础测试
        // ------------------------------------------------------------
        $display("\n=== Test 1: Direct Port 0 Basic RW ===");
        master_write(0, 0, 0, 9'h010, 4'b1111, 64'hA000_0000_0000_0000, 0);
        repeat(5) @(posedge clk);
        master_read_check(0, 0, 0, 9'h010, 4'b1111, 64'hA000_0000_0000_0000);


        // ------------------------------------------------------------
        // Case 2: 路由端口基础测试
        // ------------------------------------------------------------
        $display("\n=== Test 2: Routed Port Access (Zone 1) ===");
        master_write(1, 0, 1, 9'h020, 4'b1111, 64'hB000_0000_0000_0000, 0);
        repeat(5) @(posedge clk);
        master_read_check(1, 0, 1, 9'h020, 4'b1111, 64'hB000_0000_0000_0000);


        // ------------------------------------------------------------
        // Case 3: 累加功能测试 (已修复数学逻辑)
        // ------------------------------------------------------------
        $display("\n=== Test 3: Accumulate Operation (Zone 2) ===");
        
        // 1. 初始化: 写入 10+b (Bank0=10, Bank1=11...)
        // inc_data 使用默认值 1
        master_write(0, 2, 2, 9'h030, 4'b1111, 64'd10, 0); 
        
        // 2. 累加: 所有 Bank 统一加 20
        // 【关键】将 inc_data 设为 0
        // 结果: (10+b) + 20 = 30+b。这完美符合 master_read_check 的预期。
        master_write(0, 2, 2, 9'h030, 4'b1111, 64'd20, 1, 0); 
        
        repeat(5) @(posedge clk);
        // 3. 检查结果: 期望 30+b
        master_read_check(0, 2, 2, 9'h030, 4'b1111, 64'd30);


        // ------------------------------------------------------------
        // Case 4: 跨端口冲突仲裁
        // ------------------------------------------------------------
        $display("\n=== Test 4: Arbitration (Direct 3 vs Routed -> Zone 3) ===");
        
        @(negedge clk);
        // Direct Port 3 Request
        v_direct_cmd[3].wr_valid = 1; v_direct_cmd[3].accum_en = 0; 
        v_direct_cmd[3].wr_zone_id = 3; 
        v_direct_cmd[3].wr_addr = 9'h100; v_direct_cmd[3].wr_mask = 4'hF;
        v_direct_data[3].wvalid = 1;  
        v_direct_data[3].wdata[0] = 64'hDDDD_DDDD_DDDD_DDDD; 

        // Routed Port Request (Target Zone 3)
        v_routed_cmd[0].wr_valid = 1; v_routed_cmd[0].accum_en = 0; 
        v_routed_cmd[0].wr_zone_id = 3; 
        v_routed_cmd[0].wr_addr = 9'h200; v_routed_cmd[0].wr_mask = 4'hF;
        v_routed_data[0].wvalid = 1;  
        v_routed_data[0].wdata[0] = 64'hAAAA_AAAA_AAAA_AAAA;

        @(posedge clk); #1; 
        
        if (v_direct_cmd[3].wr_ready && !v_routed_cmd[0].wr_ready)
            $display("INFO: Direct Port won arbitration.");
        else if (!v_direct_cmd[3].wr_ready && v_routed_cmd[0].wr_ready)
            $display("INFO: Routed Port won arbitration.");
        else
            $display("INFO: Arbitration Check. ReadyD=%b ReadyR=%b", v_direct_cmd[3].wr_ready, v_routed_cmd[0].wr_ready);

        // Clear
        repeat(2) @(negedge clk);
        v_direct_cmd[3].wr_valid = 0; v_direct_data[3].wvalid = 0;
        v_routed_cmd[0].wr_valid = 0; v_routed_data[0].wvalid = 0;


        // ------------------------------------------------------------
        // Case 5: 验证旁路(Bypass) 0延迟特性
        // ------------------------------------------------------------
        $display("\n=== Test 5: Zero-Latency Bypass Check (Zone 0) ===");
        
        // 确保总线空闲
        repeat(5) @(posedge clk);

        // 1. 发起写请求 (Cmd + Data 同时)
        @(negedge clk);
        v_direct_cmd[0].wr_valid   = 1;
        v_direct_cmd[0].wr_addr    = 9'h099;
        v_direct_cmd[0].wr_mask    = 4'hF; 
        v_direct_cmd[0].accum_en   = 0;
        v_direct_cmd[0].wr_zone_id = 0;

        v_direct_data[0].wvalid    = 1;
        v_direct_data[0].wdata[0]  = 64'hBEEF_CAFE;

        // 2. 检查同一拍是否 Ready (即是否走了旁路)
        // 在 posedge 后的 #1 时刻检查，此时组合逻辑输出应已稳定
        @(posedge clk); #1; 
        
        // 只有 Bypass 成功，cmd_ready 和 data_ready 才会同时在 T0 变高
        if (v_direct_cmd[0].wr_ready == 1'b1 && v_direct_data[0].wready == 1'b1) begin
            $display("[PASS] Zero Latency Achieved! Ready was high immediately.");
        end else begin
            $error("[FAIL] Latency Detected. Ready was LOW (Bypass logic failed). CmdReady=%b DataReady=%b", 
                   v_direct_cmd[0].wr_ready, v_direct_data[0].wready);
        end

        // 3. 撤销
        @(negedge clk);
        v_direct_cmd[0].wr_valid = 0;
        v_direct_data[0].wvalid  = 0;

        #100;
        $display("\n=== All Tests Finished ===");
        $finish;
    end

endmodule