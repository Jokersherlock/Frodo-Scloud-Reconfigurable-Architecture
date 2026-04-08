package mem.port

import spinal.core._
import common.AccCmdMode
import common.AccumulatorConfig


case class AccCmd(cfg: AccumulatorConfig) extends Bundle {
    val groupID = UInt(cfg.groupWidth bits)
    val mode = Bits(2 bits)
    val addr = UInt(cfg.addrWidth bits)
    val sliceSel = Bits(cfg.numSlices bits)
    val wdata = Vec(UInt(cfg.sliceCfg.dataWidth bits), cfg.numSlices)
}

case class AccRsp(cfg: AccumulatorConfig) extends Bundle {
    val rdata = Vec(UInt(cfg.sliceCfg.dataWidth bits), cfg.numSlices)
}

case class AccPort(cfg: AccumulatorConfig) extends Bundle with IMasterSlave {
    val cmd = Stream(AccCmd(cfg))
    val rsp = Stream(AccRsp(cfg))

    override def asMaster(): Unit = {
        master(cmd)
        slave(rsp)
    }
}