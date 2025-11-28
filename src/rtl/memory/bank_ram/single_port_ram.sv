module single_port_ram (
    ram_if.slave port
);

    // 获取地址宽度和数据宽度 (使用接口中的参数)
    localparam AW = port.ADDR_WIDTH;
    localparam DW = port.DATA_WIDTH;
    localparam DEPTH = 1 << AW;

    // 定义存储阵列
    logic [DW-1:0] mem [0:DEPTH-1];

    // ---------------------------
    // 读写逻辑 (单端口)
    // ---------------------------
    always_ff @(posedge port.clk) begin
        if (port.en) begin
            if (port.we) begin
                // 写操作
                mem[port.addr] <= port.wdata;
            end else begin
                // 读操作
                port.rdata <= mem[port.addr];
            end
        end
    end

endmodule

