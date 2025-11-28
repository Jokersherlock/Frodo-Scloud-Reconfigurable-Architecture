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

endmodule