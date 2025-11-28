interface ram_if #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32
) (
    input logic clk 
);
    // 内部信号
    logic                    en;    // 使能
    logic                    we;    // 写使能
    logic [ADDR_WIDTH-1:0]   addr;
    logic [DATA_WIDTH-1:0]   wdata; // 写数据
    logic [DATA_WIDTH-1:0]   rdata; // 读数据

    // --------------------------------------------------
    // 视角 1: 写端口 (Write Port) - 站在 RAM 的角度
    // --------------------------------------------------
    // 这个 modport 只允许输入数据，不允许输出 rdata
    modport write_slave (
        input  en, we, addr, wdata, clk
    );

    // --------------------------------------------------
    // 视角 2: 读端口 (Read Port) - 站在 RAM 的角度
    // --------------------------------------------------
    // 这个 modport 只允许输出 rdata，不允许输入 wdata 和 we
    modport read_slave (
        input  en, addr, clk,
        output rdata
    );

    modport slave(
        input en, we, addr, wdata, clk,
        output rdata
    );

    // --------------------------------------------------
    // 视角 3: 验证环境/主控端 (Master)
    // --------------------------------------------------
    modport master (
        output en, we, addr, wdata,
        input  rdata,
        input  clk
    );


endinterface