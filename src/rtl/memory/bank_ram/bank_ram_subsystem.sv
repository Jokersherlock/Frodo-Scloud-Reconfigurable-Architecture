module bank_ram_subsystem #(
    parameter NUM_SLOTS  = 4,
    parameter FIFO_DEPTH = 4,
    parameter NUM_BANKS  = 5,
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 32,
    parameter RAM_LATENCY = 2
)(
    input logic clk,
    input logic rstn,

    // 上行接口：连接多个Master
    Bank_Cmd_If.Slave   cmd_slots [NUM_SLOTS],
    Bank_Data_If.Slave  data_slots [NUM_SLOTS]
);

    // =======================================================
    // 内部接口实例化
    // =======================================================
    Bank_Cmd_If   phy_cmd_if (clk, rstn);
    Bank_Data_If  phy_data_if (clk, rstn);
    
    // 使用命名映射实例化接口数组
    ram_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) ram_ports [NUM_BANKS-1:0] (clk);

    // =======================================================
    // 模块实例化
    // =======================================================
    
    // 1. 总线控制器 (之前修复过 index error 的版本)
    bank_ram_bus #(
        .NUM_SLOTS(NUM_SLOTS),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_bank_ram_bus (
        .clk(clk),
        .rstn(rstn),
        .cmd_slots(cmd_slots),
        .data_slots(data_slots),
        .phy_cmd_if(phy_cmd_if.Master),
        .phy_data_if(phy_data_if.Master)
    );

    // 2. RAM包装器
    Bank_Ram_Wrapper #(
        .NUM_BANKS(NUM_BANKS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .RAM_LATENCY(RAM_LATENCY)
    ) u_bank_ram_wrapper (
        .clk(clk),
        .rstn(rstn),
        .bus_cmd_if(phy_cmd_if.Slave),
        .bus_data_if(phy_data_if.Slave),
        .ram_ports(ram_ports)
    );

    // 3. 物理RAM
    bank_ram u_bank_ram (
        .clk(clk),
        .ports(ram_ports)
    );

endmodule