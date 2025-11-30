module single_port_ram (
    ram_if.slave port
);

    // 获取地址宽度和数据宽度 (使用接口中的参数)
    localparam AW = port.ADDR_WIDTH;
    localparam DW = port.DATA_WIDTH;
    localparam DEPTH = 1 << AW;

    // 定义存储阵列
    logic [DW-1:0] mem [0:DEPTH-1];

    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = '0; // '0 会自动根据位宽填满0
        end
    end

    // ---------------------------
    // 读写逻辑 (单端口)
    // ---------------------------
    always_ff @(posedge port.clk) begin
        //$display("[RAM_TICK] Time=%0t Inst=%m | EN=%b | WE=%b | Addr=%h | WData=%h", $time, port.en, port.we, port.addr, port.wdata);
        if (port.en) begin
            if (port.we) begin
                // 写操作
                mem[port.addr] <= port.wdata;
                //$display("[RAM DEBUG] Time=%0t Instance=%m Writing Addr=%0d Data=%h", $time, port.addr, port.wdata);
            end 
            else begin
                // 读操作
                port.rdata <= mem[port.addr];
            end
        end
    end


    `ifdef PRINT_RAM
        initial begin
            int fd;
            string filename;
            forever begin
                // 1. 等待全局触发信号变为特定值 (比如 1)
                // $root 允许你访问仿真顶层
                wait($root.tb_bank_ram_subsystem.dump_trigger == 1); 
    
                // 2. 生成唯一的文件名
                // 使用 %m 可以获取当前模块的层级名，避免多个 Bank 覆盖同一个文件
                // 例如: "ram_dump_u_dut_u_bank_ram_gen_rams_0_u_ram.txt"
                $sformat(filename, "../../../../../../temp/ram_data/%m.txt");
                // $display("filename: %s", filename);
    
                // 3. 打开文件
                fd = $fopen(filename, "w");
                if (fd) begin
                    $display("[%0t] Dumping memory content to %s ...", $time, filename);
                    
                    // 4. 遍历并写入
                    // for (int i = 0; i < DEPTH; i++) begin
                    //     // 格式: Address : Data (Hex)
                    //     $fdisplay(fd, "%05x : %08x", i, mem[i]);
                    // end
                    
                    // 或者使用更简单的二进制导出:
                    $writememh(filename, mem);
                    
                    $fclose(fd);
                end else begin
                    $error("Failed to open file %s", filename);
                end
    
                // 5. 等待触发信号消失，防止重复打印
                wait($root.tb_bank_ram_subsystem.dump_trigger == 0);
            end
        end
    `endif
endmodule

