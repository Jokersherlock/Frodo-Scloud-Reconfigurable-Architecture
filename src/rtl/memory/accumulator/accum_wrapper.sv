module Accum_Wrapper #(
    parameter NUM_BANKS  = 4,
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 64
)(
    input logic clk,
    input logic rstn,

    // 1. 来自 Accum_Bus 的接口 (Slave)
    Accum_Cmd_If.Slave   bus_cmd_if,
    Accum_Data_If.Slave  bus_data_if,
    
    // 2. 输出接口：连接到 Accum_Group
    // 【语法修正】：去掉 'output' 关键字，直接声明 Interface 数组
    ram_if.master        wr_ports [NUM_BANKS-1:0],
    ram_if.master        rd_ports [NUM_BANKS-1:0],
    
    // 3. 模式信号 (广播给 Group)
    // 这个是普通信号，需要保留 output
    output logic         mode 
);

    // ============================================================
    // 内部控制与时序
    // ============================================================
    
    // Accumulate Mode 信号广播
    assign mode = bus_cmd_if.accum_en;
    
    // 握手信号：始终 Ready (流水线全速吞吐)
    assign bus_cmd_if.wr_ready = 1'b1;
    assign bus_cmd_if.rd_ready = 1'b1;
    assign bus_data_if.wready  = 1'b1;

    // ============================================================
    // RVALID 生成逻辑 (修正为 Latency = 2)
    // ============================================================
    // 既然 RAM Latency = 2，rvalid 必须延迟 2 拍才能与 rdata 对齐
    logic [1:0] rvalid_pipe;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rvalid_pipe <= 2'b00;
        end else begin
            // 移位寄存器：0 -> 1 -> out
            // bus_cmd_if.rd_valid (T0) -> pipe[0] (T1) -> pipe[1] (T2)
            rvalid_pipe <= {rvalid_pipe[0], bus_cmd_if.rd_valid};
        end
    end

    // 输出最高位 (T2 时刻有效)
    assign bus_data_if.rvalid = rvalid_pipe[1];


    // ============================================================
    // 逻辑转换与 SIMD 扇出
    // ============================================================
    
    genvar i;
    generate
        for (i = 0; i < NUM_BANKS; i++) begin : gen_unit_ctrl
            
            // ----------------------------------------------------
            // A. 写/累加通道控制 (Wr_Port / Port A)
            // ----------------------------------------------------
            always_comb begin
                // 默认值
                wr_ports[i].en    = 1'b0;
                wr_ports[i].we    = 1'b0;
                
                // 地址广播
                wr_ports[i].addr  = bus_cmd_if.wr_addr;
                
                // 数据切片：Bus 256-bit -> Unit 64-bit
                wr_ports[i].wdata = bus_data_if.wdata[i];
                
                // 触发逻辑：Write Valid + Data Valid + Mask Hit
                if (bus_cmd_if.wr_valid && bus_data_if.wvalid && bus_cmd_if.wr_mask[i]) begin
                    wr_ports[i].en = 1'b1;
                    wr_ports[i].we = 1'b1; 
                end
            end

            // ----------------------------------------------------
            // B. 读通道控制 (Rd_Port / Port B)
            // ----------------------------------------------------
            always_comb begin
                rd_ports[i].en    = 1'b0;
                rd_ports[i].we    = 1'b0; 
                rd_ports[i].wdata = '0;
                
                // 地址广播
                rd_ports[i].addr  = bus_cmd_if.rd_addr;

                // 触发逻辑：Read Valid + Mask Hit
                if (bus_cmd_if.rd_valid && bus_cmd_if.rd_mask[i]) begin
                    rd_ports[i].en = 1'b1;
                end
            end

            // ----------------------------------------------------
            // C. 读数据回收 (Collect RData)
            // ----------------------------------------------------
            // 从 Unit Read Port 接收数据，并合并回 Bus Data Interface
            // 此时 rdata 已经是经过 Accumulator 内部直连出来的 (Latency 2)
            assign bus_data_if.rdata[i] = rd_ports[i].rdata;

        end
    endgenerate
    
endmodule