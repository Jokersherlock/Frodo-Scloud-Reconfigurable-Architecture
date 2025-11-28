interface Accum_Cmd_If (input logic clk, input logic rstn);
    // ================= 配置参数 =================
    localparam NUM_BANKS  = 4;  // 16路并行
    localparam ADDR_WIDTH = 9;   // 深度 512

    // ================= 信号定义 =================
    logic                   valid;      // 命令有效
    logic                   ready;      // Slave 是否准备好接收命令
    
    // --- 核心控制信号 ---
    logic                   rw;         // 0: Read, 1: Write
    logic                   accum_en;   // **关键**: 0=Overwrite, 1=Accumulate (仅在 rw=1 时有效)
    
    // --- 寻址与掩码 ---
    logic [NUM_BANKS-1:0]   mask;       // 16位掩码，决定操作哪些 Bank
    logic [ADDR_WIDTH-1:0] addr; // 16路地址

    // ================= Modport =================
    modport Master (
        input  clk, rstn, ready,
        output valid, rw, accum_en, mask, addr
    );

    modport Slave (
        input  clk, rstn, valid, rw, accum_en, mask, addr,
        output ready
    );
endinterface

interface Accum_Data_If (input logic clk, input logic rstn);
    // ================= 配置参数 =================
    localparam NUM_BANKS  = 4;
    localparam DATA_WIDTH = 64;  // **关键**: 64-bit 宽数据

    // ================= 写通道 (Master -> Slave) =================
    logic                   wvalid;
    logic                   wready;
    logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] wdata; // 这里的 wdata 是“增量”或者“新值”

    // ================= 读通道 (Slave -> Master) =================
    // 注意：即使是 Accumulate 操作，通常也不需要立刻读回结果。
    // 读通道主要用于计算完成后，将最终结果搬运回 CPU 或后处理模块。
    logic                   rvalid;
    logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] rdata;

    // ================= Modport =================
    modport Master (
        input  clk, rstn, wready, rvalid, rdata,
        output wvalid, wdata
    );

    modport Slave (
        input  clk, rstn, wvalid, wdata,
        output wready, rvalid, rdata
    );
endinterface
