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
    
    // 2. 输出接口：连接到 Accum_Group (Master view, Driving RAM IFs)
    //    这里输出的信号就是 Accum_Group 模块的输入 (wr_ports/rd_ports)
    output ram_if.master wr_ports [NUM_BANKS-1:0],
    output ram_if.master rd_ports [NUM_BANKS-1:0],
    
    // 3. 模式信号 (广播给 Group)
    output logic mode // 对应 Accum_Cmd_If.accum_en
);

    // ============================================================
    // 内部控制与时序
    // ============================================================
    
    // 读数据有效信号的延迟寄存器 (Latency = 1)
    logic rvalid_reg;
    
    // Accumulate Mode 信号广播
    assign mode = bus_cmd_if.accum_en;
    
    // 握手信号：假设流水线能全速吞吐
    assign bus_cmd_if.wr_ready = 1'b1;
    assign bus_cmd_if.rd_ready = 1'b1;
    assign bus_data_if.wready  = 1'b1;

    // RVALID 生成逻辑 (1 Cycle Latency)
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rvalid_reg <= 1'b0;
        end else begin
            // rvalid 应该在读请求的下一拍生效
            rvalid_reg <= bus_cmd_if.rd_valid;
        end
    end

    // Final rvalid output to the bus
    assign bus_data_if.rvalid = rvalid_reg;


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
                
                // 地址广播：所有 Unit 接收相同的写地址
                wr_ports[i].addr  = bus_cmd_if.wr_addr;
                
                // 数据切片：只把 wdata 的第 i 段送给第 i 个 Unit
                wr_ports[i].wdata = bus_data_if.wdata[i];
                
                // 触发逻辑：必须是 Write Valid AND Data Valid AND Mask 命中
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
                rd_ports[i].we    = 1'b0; // 读端口永远不写
                rd_ports[i].wdata = '0;
                rd_ports[i].addr  = bus_cmd_if.rd_addr; // 地址广播

                // 触发逻辑：Read Valid AND Mask 命中
                if (bus_cmd_if.rd_valid && bus_cmd_if.rd_mask[i]) begin
                    rd_ports[i].en = 1'b1;
                end
            end

            // ----------------------------------------------------
            // C. 读数据回收 (Collect RData)
            // ----------------------------------------------------
            // 从 Unit Read Port 接收数据，并合并回 Bus Data Interface
            assign bus_data_if.rdata[i] = rd_ports[i].rdata;

        end
    endgenerate
    
endmodule