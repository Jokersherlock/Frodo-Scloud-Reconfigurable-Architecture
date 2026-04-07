package common
import spinal.core._
object BuildConfig {
    val useIP = false
}

case class AccSliceConfig(
    dataWidth: Int=64,
    depth: Int=512
){
    val addrWidth: Int = log2Up(depth)
}