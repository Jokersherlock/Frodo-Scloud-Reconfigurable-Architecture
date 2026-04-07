package mem.acc  

import spinal.core._
import common.GenConfig
import common.BuildConfig


class PseudoDpramSimple(
    dataWidth: Int,
    depth: Int
) extends Component {
    val addrWidth = log2Up(depth)
    val io = new Bundle{
        val wr_en = in Bool()
        val wr_addr = in UInt(addrWidth bits)
        val wr_data = in UInt(dataWidth bits)

        val rd_en = in Bool()
        val rd_addr = in UInt(addrWidth bits)
        val rd_data = out UInt(dataWidth bits)
    }

    val mem = Mem(Bits(dataWidth bits), depth)

    when(io.wr_en){
        mem.write(address = io.wr_addr, data = io.wr_data.asBits)
    }

    // 1-cycle sync read, gated by rd_en
    val rd_data_mem = mem.readSync(address = io.rd_addr, enable = io.rd_en)

    // 对齐到 readSync 输出的下一拍
    val same_addr_hit_d1 = RegNext(io.wr_en && io.rd_en && (io.wr_addr === io.rd_addr)) init(False)
    val bypass_d1 = RegNext(io.wr_data.asBits) init(B(0, dataWidth bits))

    io.rd_data := Mux(same_addr_hit_d1, bypass_d1, rd_data_mem).asUInt

}

class PseudoDpramIP(
    dataWidth: Int,
    addrWidth: Int
) extends BlackBox{
    val io = new Bundle {
        val addra = in UInt(addrWidth bits)
        val clka = in Bool()
        val dina = in Bits(dataWidth bits)
        val ena = in Bool()

        val addrb = in UInt(addrWidth bits)
        val clkb = in Bool()
        val doutb = out Bits(dataWidth bits)
        val enb = in Bool()
    }
    noIoPrefix()
    setDefinitionName("pseudo_dpram")
}

class PseudoDpram(
    dataWidth: Int,
    depth: Int
) extends Component {
    val addrWidth = log2Up(depth)
    val io = new Bundle{
        val wr_en = in Bool()
        val wr_addr = in UInt(addrWidth bits)
        val wr_data = in UInt(dataWidth bits)

        val rd_en = in Bool()
        val rd_addr = in UInt(addrWidth bits)
        val rd_data = out UInt(dataWidth bits)
    }

    if(BuildConfig.useIP){
        val dpram = new PseudoDpramIP(dataWidth, addrWidth)
        dpram.io.clka := clockDomain.readClockWire
        dpram.io.ena := io.wr_en
        dpram.io.addra := io.wr_addr
        dpram.io.dina := io.wr_data.asBits

        dpram.io.clkb := clockDomain.readClockWire
        dpram.io.enb := io.rd_en
        dpram.io.addrb := io.rd_addr
        io.rd_data := dpram.io.doutb.asUInt
    } else {
        val dpram = new PseudoDpramSimple(dataWidth, depth)
        dpram.io.wr_en := io.wr_en
        dpram.io.wr_addr := io.wr_addr
        dpram.io.wr_data := io.wr_data
        dpram.io.rd_en := io.rd_en
        dpram.io.rd_addr := io.rd_addr
        io.rd_data := dpram.io.rd_data
    }
}

// object GenPseudoDpram {
//     def main(args: Array[String]): Unit = {
//         GenConfig.rtl("mem/acc").generateVerilog(new PseudoDpram)
//     }
// }