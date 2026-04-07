package mem.acc

import spinal.core._
import common.GenConfig
import common.AccSliceConfig

case class AccReadPort(
    addrWidth: Int,
    dataWidth: Int
)extends Bundle {
    val en = in Bool()
    val addr = in UInt(addrWidth bits)
    val data = out UInt(dataWidth bits)
}

case class AccWritePort(
    addrWidth: Int,
    dataWidth: Int
)extends Bundle {
    val en = in Bool()
    val addr = in UInt(addrWidth bits)
    val data = in UInt(dataWidth bits)
}

case class AccSliceIO(cfg: AccSliceConfig) extends Bundle {
    val rd = AccReadPort(cfg.addrWidth, cfg.dataWidth)
    val wr = AccWritePort(cfg.addrWidth, cfg.dataWidth)
    val acc_en = in Bool()
}


class AccSlice(cfg: AccSliceConfig) extends Component {
    val io = new AccSliceIO(cfg)
    noIoPrefix()
    // =========================================================
    // 底层 RAM
    // =========================================================
    val ram = new PseudoDpram(
        dataWidth = cfg.dataWidth,
        depth     = cfg.depth
    )

    // 如果你当前的 PseudoDpram 还保留了显式 clk 口，就打开这一句
    // ram.io.clk := clockDomain.readClockWire

    // =========================================================
    // 一拍累加流水寄存器
    //
    // 表示“上一拍接收的一条 acc 请求”
    //
    // accUseBase_d1 = True  : 下一拍返回时不用 RAM 读值，
    //                         而是直接使用 accBase_d1 作为 base
    // accUseBase_d1 = False : 下一拍返回时使用 ram.io.rd_data 作为 base
    // =========================================================
    val accValid_d1   = Reg(Bool()) init(False)
    val accAddr_d1    = Reg(UInt(cfg.addrWidth bits)) init(0)
    val accInc_d1     = Reg(UInt(cfg.dataWidth bits)) init(0)
    val accUseBase_d1 = Reg(Bool()) init(False)
    val accBase_d1    = Reg(UInt(cfg.dataWidth bits)) init(0)

    // =========================================================
    // latest forwarding entry
    // 记录最近一个逻辑上最新的值
    // =========================================================
    val latestValid = Reg(Bool()) init(False)
    val latestAddr  = Reg(UInt(cfg.addrWidth bits)) init(0)
    val latestValue = Reg(UInt(cfg.dataWidth bits)) init(0)

    // =========================================================
    // 普通读命中 forwarding 时，打一拍返回
    // 保持 readSync 风格的一拍延迟
    // =========================================================
    val rdBypassValid_d1 = Reg(Bool()) init(False)
    val rdBypassData_d1  = Reg(UInt(cfg.dataWidth bits)) init(0)

    // =========================================================
    // 当前拍“返回阶段”组合信号
    // =========================================================
    val retValid = accValid_d1
    val retAddr  = accAddr_d1

    val retBase = UInt(cfg.dataWidth bits)
    when(accUseBase_d1) {
        retBase := accBase_d1
    } otherwise {
        retBase := ram.io.rd_data
    }

    val retValue = retBase + accInc_d1

    // =========================================================
    // 当前拍请求类型
    // =========================================================
    val accReq = io.wr.en && io.acc_en
    val wrReq  = io.wr.en && !io.acc_en
    val rdReq  = io.rd.en

    // =========================================================
    // forwarding 命中判断
    // 对新 acc 请求：
    //   retValue > latestValue > RAM
    // =========================================================
    val accHitRet    = accReq && retValid    && (io.wr.addr === retAddr)
    val accHitLatest = accReq && latestValid && (io.wr.addr === latestAddr) && !accHitRet

    // 对普通读：
    //   retValue > latestValue > RAM
    val rdHitRet     = rdReq && retValid    && (io.rd.addr === retAddr)
    val rdHitLatest  = rdReq && latestValid && (io.rd.addr === latestAddr) && !rdHitRet

    // =========================================================
    // 默认读输出
    // =========================================================
    io.rd.data := ram.io.rd_data
    when(rdBypassValid_d1) {
        io.rd.data := rdBypassData_d1
    }

    // =========================================================
    // 默认 RAM 端口
    // =========================================================
    ram.io.rd_en   := False
    ram.io.rd_addr := 0

    ram.io.wr_en   := False
    ram.io.wr_addr := 0
    ram.io.wr_data := 0

    // =========================================================
    // 默认：普通读 bypass 只保持一拍
    // =========================================================
    rdBypassValid_d1 := False

    // =========================================================
    // 默认：下一拍没有新的 acc 流水项
    // 只有本拍 accReq 时，后面才会覆盖成有效
    // =========================================================
    accValid_d1   := False
    accAddr_d1    := 0
    accInc_d1     := 0
    accUseBase_d1 := False
    accBase_d1    := 0

    // =========================================================
    // 1) 返回阶段
    // 如果本拍 retValid，则优先占用写口写回
    // =========================================================
    when(retValid) {
        ram.io.wr_en   := True
        ram.io.wr_addr := retAddr
        ram.io.wr_data := retValue

        // 返回结果成为当前逻辑上的最新值
        latestValid := True
        latestAddr  := retAddr
        latestValue := retValue
    }

    // =========================================================
    // 2) 接收本拍新请求
    // =========================================================

    // ---------------------------------------------------------
    // 2.1 acc 请求：读口优先给 acc
    // ---------------------------------------------------------
    when(accReq) {
        // 本拍接收到一条新的 acc，请把它送入 d1 流水级
        accValid_d1 := True
        accAddr_d1  := io.wr.addr
        accInc_d1   := io.wr.data

        when(accHitRet) {
            // 命中本拍返回值：下一拍不需要用 RAM 读值
            accUseBase_d1 := True
            accBase_d1    := retValue

        } elsewhen(accHitLatest) {
            // 命中 latest：下一拍也不需要用 RAM 读值
            accUseBase_d1 := True
            accBase_d1    := latestValue

        } otherwise {
            // 真 miss：需要 RAM 读旧值
            accUseBase_d1 := False
            ram.io.rd_en   := True
            ram.io.rd_addr := io.wr.addr
        }
    } otherwise {
        // -----------------------------------------------------
        // 2.2 本拍没有 accReq，普通写才允许尝试使用写口
        // 但如果 retValid，本拍写口已经被返回写回占用了
        // -----------------------------------------------------
        when(wrReq && !retValid) {
            ram.io.wr_en   := True
            ram.io.wr_addr := io.wr.addr
            ram.io.wr_data := io.wr.data

            latestValid := True
            latestAddr  := io.wr.addr
            latestValue := io.wr.data
        }

        // -----------------------------------------------------
        // 2.3 本拍没有 accReq，普通读才允许使用读口
        // 普通读也优先命中 ret / latest
        // -----------------------------------------------------
        when(rdReq) {
            when(rdHitRet) {
                rdBypassValid_d1 := True
                rdBypassData_d1  := retValue
            } elsewhen(rdHitLatest) {
                rdBypassValid_d1 := True
                rdBypassData_d1  := latestValue
            } otherwise {
                ram.io.rd_en   := True
                ram.io.rd_addr := io.rd.addr
            }
        }
    }
}

object GenAccSlice {
    val cfg = AccSliceConfig()
    def main(args: Array[String]): Unit = {
        GenConfig.rtl("mem/acc").generateVerilog(new AccSlice(cfg))
    }
}