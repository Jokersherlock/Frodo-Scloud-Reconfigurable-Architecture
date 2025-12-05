module Accum_Zone #(
    parameter NUM_SLOTS  = 2,   // 连接的主设备数量 (例如: DMA + Frodo)
    parameter FIFO_DEPTH = 4,   // 总线 FIFO 深度
    parameter NUM_BANKS  = 4,   // SIMD 宽度 (4 个 Bank)
    parameter ADDR_WIDTH = 9,   // 内存深度
    parameter DATA_WIDTH = 64,  // 数据位宽
    parameter ZONE_WIDTH = 2    // Zone ID 位宽
)(
    input logic clk,
    input logic rstn,

    // =======================================================
    // 对外接口：提供给外部 Master 连接的插槽
    // =======================================================
    Accum_Cmd_If.Slave   slave_cmd_ports  [NUM_SLOTS],
    Accum_Data_If.Slave  slave_data_ports [NUM_SLOTS]
);

    // =======================================================
    // 1. 内部连接接口 (Inter-Module Links)
    // =======================================================
    
    // Link A: Bus -> Wrapper (Full Duplex Accum Interfaces)
    Accum_Cmd_If #(
        .NUM_BANKS(NUM_BANKS), .ADDR_WIDTH(ADDR_WIDTH), .ZONE_WIDTH(ZONE_WIDTH)
    ) bus_to_wrapper_cmd (clk, rstn);

    Accum_Data_If #(
        .NUM_BANKS(NUM_BANKS), .DATA_WIDTH(DATA_WIDTH)
    ) bus_to_wrapper_data (clk, rstn);
    
    // Link B: Wrapper -> Group (4对 RAM 接口)
    ram_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) 
           wrapper_to_group_wr [NUM_BANKS-1:0] (clk), // Write Ports
           wrapper_to_group_rd [NUM_BANKS-1:0] (clk); // Read Ports

    logic shared_mode; // Accumulate Mode 信号线


    // =======================================================
    // 2. 模块实例化
    // =======================================================

    // A. Bus Controller (Arbitration & FIFO)
    Accum_Bus #(
        .NUM_SLOTS  (NUM_SLOTS),
        .FIFO_DEPTH (FIFO_DEPTH),
        .NUM_BANKS  (NUM_BANKS),
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ZONE_WIDTH (ZONE_WIDTH)
    ) u_bus_controller (
        .clk        (clk),
        .rstn       (rstn),
        // Upstream: 连接外部 Master
        .cmd_slots  (slave_cmd_ports),
        .data_slots (slave_data_ports),
        // Downstream: 连接 Wrapper
        .phy_cmd_if (bus_to_wrapper_cmd.Master),
        .phy_data_if(bus_to_wrapper_data.Master)
    );

    // B. Protocol Wrapper (Logic Fanout & Latency Management)
    Accum_Wrapper #(
        .NUM_BANKS  (NUM_BANKS),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_wrapper (
        .clk         (clk),
        .rstn        (rstn),
        // Input from Bus
        .bus_cmd_if  (bus_to_wrapper_cmd.Slave),
        .bus_data_if (bus_to_wrapper_data.Slave),
        // Output to Group
        .wr_ports    (wrapper_to_group_wr),
        .rd_ports    (wrapper_to_group_rd),
        .mode        (shared_mode) // Wrapper 驱动 Mode 信号
    );

    // C. 物理单元阵列 (Accumulator Group)
    Accum_Group #(
        .NUM_UNITS  (NUM_BANKS),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_group (
        .clk      (clk),
        .rstn     (rstn),
        .mode     (shared_mode), // 共享 Mode 信号
        // Input Links: 接收来自 Wrapper 的驱动
        .wr_ports (wrapper_to_group_wr),
        .rd_ports (wrapper_to_group_rd)
    );

endmodule