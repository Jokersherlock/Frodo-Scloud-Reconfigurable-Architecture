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

    // A. 路由接口 (Routed Ports) - 可以访问任意 Zone
    Accum_Cmd_If #(
        .NUM_BANKS(NUM_BANKS), .ADDR_WIDTH(ADDR_WIDTH), .ZONE_WIDTH(ZONE_WIDTH)
    ) routed_cmd_if[NUM_ROUTED_MASTERS] (clk, rstn);
    
    Accum_Data_If #(
        .NUM_BANKS(NUM_BANKS), .DATA_WIDTH(DATA_WIDTH)
    ) routed_data_if[NUM_ROUTED_MASTERS] (clk, rstn);

    // B. 直连接口 (Direct Ports) - 索引 [i] 对应 Zone [i]
    Accum_Cmd_If #(
        .NUM_BANKS(NUM_BANKS), .ADDR_WIDTH(ADDR_WIDTH), .ZONE_WIDTH(ZONE_WIDTH)
    ) direct_cmd_if[NUM_DIRECT_PORTS] (clk, rstn);

    Accum_Data_If #(
        .NUM_BANKS(NUM_BANKS), .DATA_WIDTH(DATA_WIDTH)
    ) direct_data_if[NUM_DIRECT_PORTS] (clk, rstn);

    // =======================================================
    // 3. 虚接口定义 (用于 Task)
    // =======================================================
    virtual Accum_Cmd_If  v_routed_cmd [NUM_ROUTED_MASTERS];
    virtual Accum_Data_If v_routed_data[NUM_ROUTED_MASTERS];
    
    virtual Accum_Cmd_If  v_direct_cmd [NUM_DIRECT_PORTS];
    virtual Accum_Data_If v_direct_data[NUM_DIRECT_PORTS];

    // =======================================================
    // 4. DUT 实例化
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
    // 5. 时钟与虚接口连接
    // =======================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 连接 Routed 接口
    genvar r;
    generate
        for (r = 0; r < NUM_ROUTED_MASTERS; r++) begin : bind_routed
            initial begin
                v_routed_cmd[r]  = routed_cmd_if[r];
                v_routed_data[r] = routed_data_if[r];
            end
        end
    endgenerate

    // 连接 Direct 接口
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
    // 6. 辅助任务 (Tasks)
    // =======================================================

    // --- Task: 全局复位 ---
    task sys_reset();
        $display("[%0t] System Reset...", $time);
        rstn = 0;
        // 复位 Routed 接口
        for(int i=0; i<NUM_ROUTED_MASTERS; i++) begin
            v_routed_cmd[i].wr_valid = 0; v_routed_cmd[i].rd_valid = 0;
            v_routed_cmd[i].wr_addr = 0;  v_routed_cmd[i].rd_addr = 0;
            v_routed_cmd[i].wr_mask = 0;  v_routed_cmd[i].rd_mask = 0;
            v_routed_cmd[i].accum_en = 0; v_routed_cmd[i].wr_zone_id = 0;
            v_routed_data[i].wvalid = 0;  v_routed_data[i].wdata = '0;
        end
        // 复位 Direct 接口
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

    // --- 通用写任务 ---
    // is_routed: 1=Routed Port, 0=Direct Port
    // port_idx: 端口索引
    // dest_zone: 目标 Zone (Routed模式必填；Direct模式下此参数被忽略，但用于日志)
    task automatic master_write(
        input bit   is_routed,
        input int   port_idx,
        input int   dest_zone, 
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [NUM_BANKS-1:0]  mask,
        input logic [63:0]           base_data,
        input logic                  accum_en
    );
        virtual Accum_Cmd_If  cmd_if;
        virtual Accum_Data_If data_if;
        logic [ZONE_WIDTH-1:0] target_id;

        // 1. 选择接口句柄并确定 Zone ID
        if (is_routed) begin
            cmd_if    = v_routed_cmd[port_idx];
            data_if   = v_routed_data[port_idx];
            target_id = dest_zone[ZONE_WIDTH-1:0];
        end else begin
            cmd_if    = v_direct_cmd[port_idx];
            data_if   = v_direct_data[port_idx];
            // 【Direct 端口 ID 始终等于端口索引】
            target_id = port_idx[ZONE_WIDTH-1:0]; 
        end

        // 2. 启动阶段 (下降沿驱动)
        @(negedge clk);
        cmd_if.wr_valid   = 1;
        cmd_if.accum_en   = accum_en; 
        cmd_if.wr_mask    = mask;
        cmd_if.wr_addr    = addr;
        cmd_if.wr_zone_id = target_id; 

        data_if.wvalid    = 1;
        for(int b=0; b<NUM_BANKS; b++) begin
            data_if.wdata[b] = base_data + b;
        end

        // 3. 握手阶段 (分离的 Ready)
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

    // --- 通用读检查任务 ---
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

        // 3. 等待 rvalid 并检查
        fork : rd_wait
            begin
                while (data_if.rvalid !== 1'b1) @(posedge clk);
                @(negedge clk); 

                for(int b=0; b<NUM_BANKS; b++) begin
                    if (mask[b]) begin
                        if (data_if.rdata[b] !== (exp_base_data + b)) begin
                            $error("[FAIL] %s Port %0d Zone %0d Bank %0d: Exp %h Got %h", 
                                (is_routed ? "Routed":"Direct"), port_idx, target_id, b, exp_base_data+b, data_if.rdata[b]);
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
    // 7. 主测试流程
    // =======================================================
    initial begin
        #10;
        sys_reset();

        // ------------------------------------------------------------
        // Case 1: 直连端口基础测试 (Direct Port 0 -> Zone 0)
        // ------------------------------------------------------------
        $display("\n=== Test 1: Direct Port 0 Basic RW ===");
        // Direct Port 0, Zone ID 自动设为 0
        master_write(0, 0, 0, 9'h010, 4'b1111, 64'hA000_0000_0000_0000, 0);
        repeat(5) @(posedge clk);
        master_read_check(0, 0, 0, 9'h010, 4'b1111, 64'hA000_0000_0000_0000);

        // master_write(0, 1, 1, 9'h010, 4'b1111, 64'hB000_0000_0000_0000, 0);
        // repeat(5) @(posedge clk);
        // master_read_check(0, 1, 1, 9'h010, 4'b1111, 64'hB000_0000_0000_0000);


        // ------------------------------------------------------------
        // Case 2: 路由端口基础测试 (Routed Port 0 -> Router -> Zone 1)
        // ------------------------------------------------------------
        $display("\n=== Test 2: Routed Port Access (Zone 1) ===");
        // Routed Port 0, Target Zone 1
        master_write(1, 0, 1, 9'h020, 4'b1111, 64'hB000_0000_0000_0000, 0);
        repeat(5) @(posedge clk);
        master_read_check(1, 0, 1, 9'h020, 4'b1111, 64'hB000_0000_0000_0000);


        // ------------------------------------------------------------
        // Case 3: 累加功能测试 (Direct Port 2 -> Zone 2)
        // ------------------------------------------------------------
        $display("\n=== Test 3: Accumulate Operation (Zone 2) ===");
        
        // 1. 初始化: Direct Port 2 (Zone 2), Addr 0x30, Val = 10
        master_write(0, 2, 2, 9'h030, 4'b1111, 64'd10, 0); // Accum=0
        
        // 2. 累加: Direct Port 2 (Zone 2), Addr 0x30, Val = 20 (Expected = 30)
        master_write(0, 2, 2, 9'h030, 4'b1111, 64'd20, 1); // Accum=1
        
        repeat(5) @(posedge clk);
        // 3. 检查结果
        master_read_check(0, 2, 2, 9'h030, 4'b1111, 64'd30);


        // ------------------------------------------------------------
        // Case 4: 跨端口冲突仲裁 (Direct 3 vs Routed -> Zone 3)
        // ------------------------------------------------------------
        $display("\n=== Test 4: Arbitration (Direct 3 vs Routed -> Zone 3) ===");
        
        // 准备冲突：同时发起 Direct Port 3 和 Routed Port (Target Zone 3)
        @(negedge clk);
        
        // Direct Port 3 Request (Zone ID 自动为 3)
        v_direct_cmd[3].wr_valid = 1; v_direct_cmd[3].accum_en = 0; 
        v_direct_cmd[3].wr_zone_id = 3; 
        v_direct_cmd[3].wr_addr = 9'h100; v_direct_cmd[3].wr_mask = 4'hF;
        
        // 【已修正】使用合法 HEX 值
        v_direct_data[3].wvalid = 1;  
        v_direct_data[3].wdata[0] = 64'hDDDD_DDDD_DDDD_DDDD; 

        // Routed Port Request (Target Zone 3)
        v_routed_cmd[0].wr_valid = 1; v_routed_cmd[0].accum_en = 0; 
        v_routed_cmd[0].wr_zone_id = 3; 
        v_routed_cmd[0].wr_addr = 9'h200; v_routed_cmd[0].wr_mask = 4'hF;
        
        // 【已修正】使用合法 HEX 值
        v_routed_data[0].wvalid = 1;  
        v_routed_data[0].wdata[0] = 64'hAAAA_AAAA_AAAA_AAAA;

        // 检查下一拍谁获得了 Ready
        @(posedge clk); #1;
        
        // Zone 内部的 Arbiter 可能会选择其中一个
        if (v_direct_cmd[3].wr_ready && !v_routed_cmd[0].wr_ready)
            $display("INFO: Direct Port won arbitration.");
        else if (!v_direct_cmd[3].wr_ready && v_routed_cmd[0].wr_ready)
            $display("INFO: Routed Port won arbitration.");
        else
            $display("INFO: Both ready or None ready (Check FIFO depth).");

        // 清理
        repeat(2) @(negedge clk);
        v_direct_cmd[3].wr_valid = 0; v_direct_data[3].wvalid = 0;
        v_routed_cmd[0].wr_valid = 0; v_routed_data[0].wvalid = 0;

        #100;
        $display("\n=== All Tests Finished ===");
        $finish;
    end

endmodule