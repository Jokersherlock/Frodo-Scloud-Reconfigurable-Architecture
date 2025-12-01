module Accum_Group #(
    parameter NUM_UNITS  = 4,
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 64
)(
    input logic clk,
    input logic rstn,
    input logic mode, // 【新增】独立的模式信号 (Accumulate/Overwrite)

    // 4路独立的写/RMW端口 (来自 Wrapper 的驱动)
    ram_if.write_slave wr_ports [NUM_UNITS-1:0],
    
    // 4路独立的读端口 (来自 Wrapper 的驱动)
    ram_if.read_slave  rd_ports [NUM_UNITS-1:0]
);

    // ============================================================
    // 实例化 4 个 Accumulator 单元
    // ============================================================
    
    genvar i;
    generate
        for (i = 0; i < NUM_UNITS; i++) begin : gen_accum_units
            
            // 实例化单个 Accumulator Unit
            accumulator #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH)
            ) u_acc_unit (
                .clk     (clk),
                .rstn    (rstn),
                // 写入端口
                .wr_port (wr_ports[i]), 
                // 读取端口
                .rd_port (rd_ports[i]),
                // 模式信号 (共享，连接到新增的 mode 端口)
                .mode    (mode) 
            );
        end
    endgenerate

endmodule