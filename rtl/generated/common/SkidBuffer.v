// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : SkidBuffer

`timescale 1ns/1ps

module SkidBuffer (
  input  wire          io_in_valid,
  output wire          io_in_ready,
  input  wire [7:0]    io_in_payload,
  output wire          io_out_valid,
  input  wire          io_out_ready,
  output wire [7:0]    io_out_payload,
  input  wire          clk,
  input  wire          reset
);

  reg                 mainValid;
  reg        [7:0]    mainPayload;
  reg                 skidValid;
  reg        [7:0]    skidPayload;
  wire                inFire;
  wire                outFire;
  wire                when_SkidBuffer_l44;
  wire                when_SkidBuffer_l46;
  wire                when_SkidBuffer_l55;
  wire                when_SkidBuffer_l66;

  assign io_out_valid = mainValid;
  assign io_out_payload = mainPayload;
  assign io_in_ready = (! (mainValid && skidValid));
  assign inFire = (io_in_valid && io_in_ready);
  assign outFire = (io_out_valid && io_out_ready);
  assign when_SkidBuffer_l44 = (inFire && (! outFire));
  assign when_SkidBuffer_l46 = (! mainValid);
  assign when_SkidBuffer_l55 = ((! inFire) && outFire);
  assign when_SkidBuffer_l66 = (inFire && outFire);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      mainValid <= 1'b0;
      skidValid <= 1'b0;
    end else begin
      if(when_SkidBuffer_l44) begin
        if(when_SkidBuffer_l46) begin
          mainValid <= 1'b1;
        end else begin
          skidValid <= 1'b1;
        end
      end else begin
        if(when_SkidBuffer_l55) begin
          if(skidValid) begin
            mainValid <= 1'b1;
            skidValid <= 1'b0;
          end else begin
            mainValid <= 1'b0;
          end
        end else begin
          if(when_SkidBuffer_l66) begin
            if(skidValid) begin
              mainValid <= 1'b1;
              skidValid <= 1'b1;
            end else begin
              mainValid <= 1'b1;
            end
          end
        end
      end
      `ifndef SYNTHESIS
        `ifdef FORMAL
          assert((! ((! mainValid) && skidValid))); // SkidBuffer.scala:L89
        `else
          if(!(! ((! mainValid) && skidValid))) begin
            $display("FAILURE "); // SkidBuffer.scala:L89
            $finish;
          end
        `endif
      `endif
    end
  end

  always @(posedge clk) begin
    if(when_SkidBuffer_l44) begin
      if(when_SkidBuffer_l46) begin
        mainPayload <= io_in_payload;
      end else begin
        skidPayload <= io_in_payload;
      end
    end else begin
      if(when_SkidBuffer_l55) begin
        if(skidValid) begin
          mainPayload <= skidPayload;
        end
      end else begin
        if(when_SkidBuffer_l66) begin
          if(skidValid) begin
            mainPayload <= skidPayload;
            skidPayload <= io_in_payload;
          end else begin
            mainPayload <= io_in_payload;
          end
        end
      end
    end
  end


endmodule
