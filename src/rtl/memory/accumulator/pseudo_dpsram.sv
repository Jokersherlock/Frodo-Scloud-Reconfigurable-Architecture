module pseudo_dpram (
    // 端口 A：专门用于写
    ram_if.write_slave wr_port,
    // 端口 B：专门用于读
    ram_if.read_slave rd_port
);

    // 获取地址宽度和数据宽度 (使用接口中的参数)
    // 这是一个很棒的技巧，不需要在 module 再定义一遍 parameter
    localparam AW = wr_port.ADDR_WIDTH;
    localparam DW = wr_port.DATA_WIDTH;
    localparam DEPTH = 1 << AW;

    // 定义存储阵列
    logic [DW-1:0] mem [0:DEPTH-1];

    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = '0; // '0 会自动根据位宽填满0
        end
    end

    // ---------------------------
    // 写逻辑 (Port A)
    // ---------------------------
    always_ff @(posedge wr_port.clk) begin
        if (wr_port.en) begin
            if (wr_port.we) begin
                mem[wr_port.addr] <= wr_port.wdata;
            end
        end
    end

    // ---------------------------
    // 读逻辑 (Port B)
    // ---------------------------
    always_ff @(posedge rd_port.clk) begin
        if (rd_port.en) begin
            // 注意：这里没有写操作，纯读
            rd_port.rdata <= mem[rd_port.addr]; 
        end
    end

    `ifdef PRINT_RAM
        initial begin
            int fd;
            string filename;
            forever begin
                wait($root.tb_accumulator.dump_trigger == 1);
            end
            $sformat(filename, "../../../../../../temp/accumulator_data/%m.txt");
            fd = $fopen(filename, "w");
            if (fd) begin
                $display("[%0t] Dumping memory content to %s ...", $time, filename);
                $writememh(filename, mem);
                $fclose(fd);
            end else begin
                $error("Failed to open file %s", filename);
            end
            wait($root.tb_accumulator.dump_trigger == 0);
        end
    `endif

endmodule