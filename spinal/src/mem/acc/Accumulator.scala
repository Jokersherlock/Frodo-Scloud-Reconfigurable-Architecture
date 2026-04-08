package mem.acc

import spinal.core._
import common.GenConfig
import common.AccumulatorConfig

case class AccGroupReadPort(cfg: AccumulatorConfig) extends Bundle {
    val addr = in UInt(cfg.sliceCfg.addrWidth bits)
    val data = out Vec(UInt(cfg.sliceCfg.dataWidth bits), cfg.numSlices)
}

case class AccGroupWritePort(cfg: AccumulatorConfig) extends Bundle {
    val addr = in UInt(cfg.sliceCfg.addrWidth bits)
    val data = in Vec(UInt(cfg.sliceCfg.dataWidth bits), cfg.numSlices)
}


case class AccGroupIO(cfg: AccumulatorConfig) extends Bundle {
    val cs = in Bits(cfg.numSlices bits)
    val acc_en = in Bool()
    val wr_en = in Bool()
    val rd = AccGroupReadPort(cfg)
    val wr = AccGroupWritePort(cfg)
}

class AccGroup(cfg:AccumulatorConfig) extends Component {
    val io = new AccGroupIO(cfg)
    noIoPrefix()

    val slices = Array.fill(cfg.numSlices)(new AccSlice(cfg.sliceCfg))

    for (i <- 0 until cfg.numSlices) {
        // 片选：每个 slice 单独使能
        val sel = io.cs(i)

        // 读：所有 slice 共用地址，按片选决定是否发起读请求
        slices(i).io.rd.en   := sel
        slices(i).io.rd.addr := io.rd.addr
        io.rd.data(i)        := slices(i).io.rd.data

        // 写：顶层 wr_en + 片选 决定写/累加请求是否进入该 slice
        slices(i).io.wr.en   := io.wr_en && sel
        slices(i).io.wr.addr := io.wr.addr
        slices(i).io.wr.data := io.wr.data(i)

        // 顶层 acc_en 广播到内部；与片选相与避免未选中 slice 参与累加
        slices(i).io.acc_en := io.acc_en && sel
    }
}

case class AccumulatorIO(cfg: AccumulatorConfig) extends Bundle {
    val groups = Vec(AccGroupIO(cfg), cfg.numGroups)
}

class Accumulator(cfg: AccumulatorConfig) extends Component {
    val io = new AccumulatorIO(cfg)
    noIoPrefix()

    val groups = Array.fill(cfg.numGroups)(new AccGroup(cfg))

    for (i <- 0 until cfg.numGroups) {
        groups(i).io <> io.groups(i)
    }
}

object GenAccumulator {
    val cfg = AccumulatorConfig()
    def main(args: Array[String]): Unit = {
        GenConfig.rtl("mem/acc").generateVerilog(new Accumulator(cfg))
    }
}