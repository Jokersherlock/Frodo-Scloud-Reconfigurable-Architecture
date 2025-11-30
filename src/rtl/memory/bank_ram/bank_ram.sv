module bank_ram (
    input logic clk,
    ram_if.slave ports [4:0]
);

    localparam NUM_BANKS = 5;
    // 从接口中获取参数（假设所有端口参数相同）
    localparam ADDR_WIDTH = ports[0].ADDR_WIDTH;
    localparam DATA_WIDTH = ports[0].DATA_WIDTH;

    `ifndef USE_IP
        // RTL实现时，需要内部接口数组用于连接single_port_ram
        ram_if #(ADDR_WIDTH, DATA_WIDTH) int_ram_if [NUM_BANKS-1:0] (clk);
    `endif

    // 为每个bank实例化一个单端口RAM
    genvar i;
    generate
        for (i = 0; i < NUM_BANKS; i++) begin : gen_bank
            `ifdef USE_IP
                // 使用IP核
                bank_ram_ip u_bank_ram (
                    .clka(clk),
                    .ena(ports[i].en),
                    .wea(ports[i].we),
                    .addra(ports[i].addr),
                    .dina(ports[i].wdata),
                    .douta(ports[i].rdata)
                );
            `else
                // 使用RTL实现
                // 连接控制信号
                assign int_ram_if[i].en = ports[i].en;
                // assign int_ram_if[i].en = 1'b1;
                assign int_ram_if[i].we = ports[i].we;
                assign int_ram_if[i].addr = ports[i].addr;
                assign int_ram_if[i].wdata = ports[i].wdata;
                
                // 实例化单端口RAM
                single_port_ram u_bank_ram (
                    .port(int_ram_if[i].slave)
                );
                
                // 输出数据加一级寄存器，模拟Core Output Register
                always_ff @(posedge clk) begin
                    ports[i].rdata <= int_ram_if[i].rdata;
                end
            `endif
        end
    endgenerate

endmodule

