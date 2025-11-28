interface Bank_Cmd_If (input logic clk, input logic rstn);
    localparam NUM_BANKS = 5;
    localparam ADDR_WIDTH = 9;

    // --- 信号定义 ---
    logic                   valid;    // 请求有效
    logic                   ready;    // (可选) 总线/从机准备好接收了吗？
    logic                   rw;       // 0: Read, 1: Write
    logic [NUM_BANKS-1:0]   mask;     // 涉及哪些 Bank
    logic [ADDR_WIDTH-1:0] addr; // 5路地址

    // --- Modport ---
    modport Master (
        input  clk, rstn, ready,
        output valid, rw, mask, addr
    );

    modport Slave (
        input  clk, rstn, valid, rw, mask, addr,
        output ready
    );
endinterface


interface Bank_Data_If (input logic clk, input logic rstn);
    localparam NUM_BANKS = 5;
    localparam DATA_WIDTH = 32;

    // --- 写数据通道 (Master -> Slave) ---
    logic                   wvalid;   // 写数据有效
    logic                   wready;   // Slave是否准备好接收写数据
    logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] wdata;

    // --- 读数据通道 (Slave -> Master) ---
    logic                   rvalid;   // 读数据有效
    logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] rdata;

    // --- Modport ---
    modport Master (
        input  clk, rstn, wready, rvalid, rdata,
        output wvalid, wdata
    );

    modport Slave (
        input  clk, rstn, wvalid, wdata,
        output wready, rvalid, rdata
    );
endinterface