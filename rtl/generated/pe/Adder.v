// Generator : SpinalHDL v1.12.3    git head : 591e64062329e5e2e2b81f4d52422948053edb97
// Component : Adder

`timescale 1ns/1ps

module Adder (
  input  wire [7:0]    a,
  input  wire [7:0]    b,
  output wire [7:0]    c
);


  assign c = (a + b);

endmodule
