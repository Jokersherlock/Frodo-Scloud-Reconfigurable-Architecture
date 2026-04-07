package common

import spinal.core._

object GenConfig {
  def rtl(subdir: String) = SpinalConfig(
    targetDirectory = s"../rtl/generated/$subdir"
  )
}