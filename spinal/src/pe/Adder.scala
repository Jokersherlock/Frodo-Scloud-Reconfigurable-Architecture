package pe

import spinal.core._
import common.GenConfig


class Adder extends Component {
  val a = in UInt(8 bits)
  val b = in UInt(8 bits)
  val c = out UInt(8 bits)

  c := a + b
}

object GenAdder {
  def main(args: Array[String]): Unit = {
    GenConfig.rtl("pe").generateVerilog(new Adder)
  }
}