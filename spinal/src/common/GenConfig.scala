package common

import spinal.core._

object GenConfig {
  def rtl(
      subdir: String,
      oneFilePerComponent: Boolean = true
  ) = SpinalConfig(
    targetDirectory = s"../rtl/generated/$subdir",
    // mode = Verilog,
    oneFilePerComponent = oneFilePerComponent
  )
}