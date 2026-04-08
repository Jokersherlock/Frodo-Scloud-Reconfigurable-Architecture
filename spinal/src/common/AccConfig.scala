package common
import spinal.core._

case class AccSliceConfig(
    dataWidth: Int=64,
    depth: Int=512
){
    val addrWidth: Int = log2Up(depth)
}

case class AccumulatorConfig(
    numSlices: Int = 4,
    numGroups: Int = 4,
    sliceCfg: AccSliceConfig = AccSliceConfig(),
    numSlots: Int = SlotsConfig.AccSlotsNum
){
    def groupWidth: Int = log2Up(numGroups)
}

object AccCmdMode{
    def READ :  Bits = B"2'b00"
    def WRITE : Bits = B"2'b01"
    def ACC :   Bits = B"2'b11"
    def NONE :  Bits = B"2'b10"
}