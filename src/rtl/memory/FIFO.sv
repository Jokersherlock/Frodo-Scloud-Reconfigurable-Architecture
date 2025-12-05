module FIFO #(
    parameter WIDTH = 32,  // 数据位宽 (由外部 struct $bits 决定)
    parameter DEPTH = 4    // 深度
)(
    input  logic             clk,
    input  logic             rstn, // 低电平复位

    // 写端口
    input  logic             push,
    input  logic [WIDTH-1:0] din,

    // 读端口
    input  logic             pop,
    output logic [WIDTH-1:0] dout, // FWFT 模式输出

    // 状态信号
    output logic             full,
    output logic             empty
);

// `ifdef USE_IP
//     // =======================================================
//     // 分支 A: 实例化 FIFO IP 核 (以 Xilinx XPM 为例)
//     // =======================================================
    
//     // 必须配置为 "First Word Fall Through" (FWFT) 模式
    
//     xpm_fifo_sync #(
//         .FIFO_MEMORY_TYPE    ("auto"), 
//         .FIFO_WRITE_DEPTH    (DEPTH),
//         .WRITE_DATA_WIDTH    (WIDTH),
//         .READ_DATA_WIDTH     (WIDTH),
//         .READ_MODE           ("fwft"), // **关键**: 必须是 FWFT
//         .USE_ADV_FEATURES    ("0000") 
//     ) u_ip_fifo (
//         .wr_clk    (clk),
//         .rst       (~rstn), // XPM 通常是高电平复位，需要取反
//         .wr_en     (push),
//         .din       (din),
//         .rd_en     (pop),
//         .dout      (dout),
//         .full      (full),
//         .empty     (empty),
//         // 未使用的端口
//         .wr_rst_busy (),
//         .rd_rst_busy (),
//         .data_valid  (),
//         .underflow   (),
//         .overflow    ()
//     );

// `else
    // =======================================================
    // 分支 B: RTL 实现 (寄存器数组, FWFT)
    // =======================================================
    
    // 内部存储
    logic [WIDTH-1:0] mem [DEPTH];
    logic [$clog2(DEPTH)-1:0] wr_ptr;
    logic [$clog2(DEPTH)-1:0] rd_ptr;
    logic [$clog2(DEPTH):0]   cnt;

    // 输出逻辑 (FWFT: 直接输出当前读指针指向的数据)
    assign full  = (cnt == DEPTH);
    assign empty = (cnt == 0);
    assign dout  = mem[rd_ptr]; 

    // 状态机
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            cnt    <= 0;
        end else begin
            // Push
            if (push && (!full || pop)) begin
                mem[wr_ptr] <= din;
                if (wr_ptr == DEPTH-1) wr_ptr <= 0;
                else                   wr_ptr <= wr_ptr + 1;
            end

            // Pop
            if (pop && !empty) begin
                if (rd_ptr == DEPTH-1) rd_ptr <= 0;
                else                   rd_ptr <= rd_ptr + 1;
            end

            // Count Update
            case ({push && (!full || pop), pop && !empty})
                2'b10: cnt <= cnt + 1;
                2'b01: cnt <= cnt - 1;
                default: ;
            endcase
        end
    end
// `endif

endmodule