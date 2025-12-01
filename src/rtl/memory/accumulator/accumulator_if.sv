interface Accum_Cmd_If #(
    parameter NUM_BANKS  = 4,
    parameter ADDR_WIDTH = 9,
    parameter ZONE_WIDTH = 2
) (
    input logic clk, 
    input logic rstn
);

    // =======================================================
    // 通道 1: 写命令通道 (Write Command Channel) -> 对应 RAM Port A
    // =======================================================
    logic                   wr_valid;
    logic                   wr_ready;
    logic [ZONE_WIDTH-1:0]  wr_zone_id; // 写路由 ID
    logic                   accum_en;   // 0:Overwrite, 1:Accumulate
    logic [NUM_BANKS-1:0]   wr_mask;    // 写掩码
    logic [ADDR_WIDTH-1:0]  wr_addr;    // 写地址

    // =======================================================
    // 通道 2: 读命令通道 (Read Command Channel) -> 对应 RAM Port B
    // =======================================================
    logic                   rd_valid;
    logic                   rd_ready;
    logic [ZONE_WIDTH-1:0]  rd_zone_id; // 读路由 ID
    logic [NUM_BANKS-1:0]   rd_mask;    // 读掩码 (决定读哪些 Bank)
    logic [ADDR_WIDTH-1:0]  rd_addr;    // 读地址

    // ================= Modports =================
    modport Master (
        input  clk, rstn, 
        input  wr_ready, rd_ready,
        output wr_valid, wr_zone_id, accum_en, wr_mask, wr_addr,
        output rd_valid, rd_zone_id, rd_mask, rd_addr
    );

    modport Slave (
        input  clk, rstn,
        input  wr_valid, wr_zone_id, accum_en, wr_mask, wr_addr,
        input  rd_valid, rd_zone_id, rd_mask, rd_addr,
        output wr_ready, rd_ready
    );

endinterface

interface Accum_Data_If #(
    parameter NUM_BANKS  = 4,
    parameter DATA_WIDTH = 64
) (
    input logic clk, 
    input logic rstn
);

    // ================= 写数据通道 (配合 Write Command) =================
    logic                                   wvalid;
    logic                                   wready;
    logic [NUM_BANKS-1:0][DATA_WIDTH-1:0]   wdata;

    // ================= 读数据通道 (配合 Read Command) =================
    logic                                   rvalid;
    // 读数据不需要 ready，Master 必须无条件接收
    logic [NUM_BANKS-1:0][DATA_WIDTH-1:0]   rdata;

    // ================= Modports =================
    modport Master (
        input  clk, rstn, wready, rvalid, rdata,
        output wvalid, wdata
    );

    modport Slave (
        input  clk, rstn, wvalid, wdata,
        output wready, rvalid, rdata
    );

endinterface