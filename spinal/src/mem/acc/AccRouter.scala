package mem.acc

import spinal.core._
import common.AccumulatorConfig
import mem.port.AccPort

case class AccRouterIO(cfg: AccumulatorConfig) extends Bundle {
    // 外部设备作为 master 发 cmd / 收 rsp，所以这里用 slave(AccPort)
    val ports = Vec(slave(AccPort(cfg)), cfg.numSlots)

    // 连接到 Accumulator 的接口（路由器驱动 accumulator 的输入，因此需要 flip 方向）
    val acc = AccumulatorIO(cfg).flip()
}