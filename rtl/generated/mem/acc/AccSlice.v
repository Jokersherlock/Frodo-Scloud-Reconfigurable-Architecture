// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : AccSlice

`timescale 1ns/1ps

module AccSlice (
  input  wire          rd_en,
  input  wire [8:0]    rd_addr,
  output reg  [63:0]   rd_data,
  input  wire          wr_en,
  input  wire [8:0]    wr_addr,
  input  wire [63:0]   wr_data,
  input  wire          acc_en,
  input  wire          clk,
  input  wire          reset
);

  reg                 ram_io_wr_en;
  reg        [8:0]    ram_io_wr_addr;
  reg        [63:0]   ram_io_wr_data;
  reg                 ram_io_rd_en;
  reg        [8:0]    ram_io_rd_addr;
  wire       [63:0]   ram_io_rd_data;
  reg                 accValid_d1;
  reg        [8:0]    accAddr_d1;
  reg        [63:0]   accInc_d1;
  reg                 accUseBase_d1;
  reg        [63:0]   accBase_d1;
  reg                 latestValid;
  reg        [8:0]    latestAddr;
  reg        [63:0]   latestValue;
  reg                 rdBypassValid_d1;
  reg        [63:0]   rdBypassData_d1;
  reg        [63:0]   retBase;
  wire       [63:0]   retValue;
  wire                accReq;
  wire                wrReq;
  wire                accHitRet;
  wire                accHitLatest;
  wire                rdHitRet;
  wire                rdHitLatest;
  wire                when_AccSlice_l193;

  PseudoDpram ram (
    .io_wr_en   (ram_io_wr_en        ), //i
    .io_wr_addr (ram_io_wr_addr[8:0] ), //i
    .io_wr_data (ram_io_wr_data[63:0]), //i
    .io_rd_en   (ram_io_rd_en        ), //i
    .io_rd_addr (ram_io_rd_addr[8:0] ), //i
    .io_rd_data (ram_io_rd_data[63:0]), //o
    .clk        (clk                 ), //i
    .reset      (reset               )  //i
  );
  always @(*) begin
    if(accUseBase_d1) begin
      retBase = accBase_d1;
    end else begin
      retBase = ram_io_rd_data;
    end
  end

  assign retValue = (retBase + accInc_d1);
  assign accReq = (wr_en && acc_en);
  assign wrReq = (wr_en && (! acc_en));
  assign accHitRet = ((accReq && accValid_d1) && (wr_addr == accAddr_d1));
  assign accHitLatest = (((accReq && latestValid) && (wr_addr == latestAddr)) && (! accHitRet));
  assign rdHitRet = ((rd_en && accValid_d1) && (rd_addr == accAddr_d1));
  assign rdHitLatest = (((rd_en && latestValid) && (rd_addr == latestAddr)) && (! rdHitRet));
  always @(*) begin
    rd_data = ram_io_rd_data;
    if(rdBypassValid_d1) begin
      rd_data = rdBypassData_d1;
    end
  end

  always @(*) begin
    ram_io_rd_en = 1'b0;
    if(accReq) begin
      if(!accHitRet) begin
        if(!accHitLatest) begin
          ram_io_rd_en = 1'b1;
        end
      end
    end else begin
      if(rd_en) begin
        if(!rdHitRet) begin
          if(!rdHitLatest) begin
            ram_io_rd_en = 1'b1;
          end
        end
      end
    end
  end

  always @(*) begin
    ram_io_rd_addr = 9'h0;
    if(accReq) begin
      if(!accHitRet) begin
        if(!accHitLatest) begin
          ram_io_rd_addr = wr_addr;
        end
      end
    end else begin
      if(rd_en) begin
        if(!rdHitRet) begin
          if(!rdHitLatest) begin
            ram_io_rd_addr = rd_addr;
          end
        end
      end
    end
  end

  always @(*) begin
    ram_io_wr_en = 1'b0;
    if(accValid_d1) begin
      ram_io_wr_en = 1'b1;
    end
    if(!accReq) begin
      if(when_AccSlice_l193) begin
        ram_io_wr_en = 1'b1;
      end
    end
  end

  always @(*) begin
    ram_io_wr_addr = 9'h0;
    if(accValid_d1) begin
      ram_io_wr_addr = accAddr_d1;
    end
    if(!accReq) begin
      if(when_AccSlice_l193) begin
        ram_io_wr_addr = wr_addr;
      end
    end
  end

  always @(*) begin
    ram_io_wr_data = 64'h0;
    if(accValid_d1) begin
      ram_io_wr_data = retValue;
    end
    if(!accReq) begin
      if(when_AccSlice_l193) begin
        ram_io_wr_data = wr_data;
      end
    end
  end

  assign when_AccSlice_l193 = (wrReq && (! accValid_d1));
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      accValid_d1 <= 1'b0;
      accAddr_d1 <= 9'h0;
      accInc_d1 <= 64'h0;
      accUseBase_d1 <= 1'b0;
      accBase_d1 <= 64'h0;
      latestValid <= 1'b0;
      latestAddr <= 9'h0;
      latestValue <= 64'h0;
      rdBypassValid_d1 <= 1'b0;
      rdBypassData_d1 <= 64'h0;
    end else begin
      rdBypassValid_d1 <= 1'b0;
      accValid_d1 <= 1'b0;
      accAddr_d1 <= 9'h0;
      accInc_d1 <= 64'h0;
      accUseBase_d1 <= 1'b0;
      accBase_d1 <= 64'h0;
      if(accValid_d1) begin
        latestValid <= 1'b1;
        latestAddr <= accAddr_d1;
        latestValue <= retValue;
      end
      if(accReq) begin
        accValid_d1 <= 1'b1;
        accAddr_d1 <= wr_addr;
        accInc_d1 <= wr_data;
        if(accHitRet) begin
          accUseBase_d1 <= 1'b1;
          accBase_d1 <= retValue;
        end else begin
          if(accHitLatest) begin
            accUseBase_d1 <= 1'b1;
            accBase_d1 <= latestValue;
          end else begin
            accUseBase_d1 <= 1'b0;
          end
        end
      end else begin
        if(when_AccSlice_l193) begin
          latestValid <= 1'b1;
          latestAddr <= wr_addr;
          latestValue <= wr_data;
        end
        if(rd_en) begin
          if(rdHitRet) begin
            rdBypassValid_d1 <= 1'b1;
            rdBypassData_d1 <= retValue;
          end else begin
            if(rdHitLatest) begin
              rdBypassValid_d1 <= 1'b1;
              rdBypassData_d1 <= latestValue;
            end
          end
        end
      end
    end
  end


endmodule

module PseudoDpram (
  input  wire          io_wr_en,
  input  wire [8:0]    io_wr_addr,
  input  wire [63:0]   io_wr_data,
  input  wire          io_rd_en,
  input  wire [8:0]    io_rd_addr,
  output wire [63:0]   io_rd_data,
  input  wire          clk,
  input  wire          reset
);

  wire       [63:0]   pseudoDpramSimple_1_io_rd_data;

  PseudoDpramSimple pseudoDpramSimple_1 (
    .io_wr_en   (io_wr_en                            ), //i
    .io_wr_addr (io_wr_addr[8:0]                     ), //i
    .io_wr_data (io_wr_data[63:0]                    ), //i
    .io_rd_en   (io_rd_en                            ), //i
    .io_rd_addr (io_rd_addr[8:0]                     ), //i
    .io_rd_data (pseudoDpramSimple_1_io_rd_data[63:0]), //o
    .clk        (clk                                 ), //i
    .reset      (reset                               )  //i
  );
  assign io_rd_data = pseudoDpramSimple_1_io_rd_data;

endmodule

module PseudoDpramSimple (
  input  wire          io_wr_en,
  input  wire [8:0]    io_wr_addr,
  input  wire [63:0]   io_wr_data,
  input  wire          io_rd_en,
  input  wire [8:0]    io_rd_addr,
  output wire [63:0]   io_rd_data,
  input  wire          clk,
  input  wire          reset
);

  reg        [63:0]   mem_spinal_port1;
  wire       [63:0]   _zz_mem_port;
  reg                 _zz_1;
  wire       [63:0]   rd_data_mem;
  reg                 same_addr_hit_d1;
  reg        [63:0]   bypass_d1;
  reg [63:0] mem [0:511];

  assign _zz_mem_port = io_wr_data;
  always @(posedge clk) begin
    if(_zz_1) begin
      mem[io_wr_addr] <= _zz_mem_port;
    end
  end

  always @(posedge clk) begin
    if(io_rd_en) begin
      mem_spinal_port1 <= mem[io_rd_addr];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(io_wr_en) begin
      _zz_1 = 1'b1;
    end
  end

  assign rd_data_mem = mem_spinal_port1;
  assign io_rd_data = (same_addr_hit_d1 ? bypass_d1 : rd_data_mem);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      same_addr_hit_d1 <= 1'b0;
      bypass_d1 <= 64'h0;
    end else begin
      same_addr_hit_d1 <= ((io_wr_en && io_rd_en) && (io_wr_addr == io_rd_addr));
      bypass_d1 <= io_wr_data;
    end
  end


endmodule
