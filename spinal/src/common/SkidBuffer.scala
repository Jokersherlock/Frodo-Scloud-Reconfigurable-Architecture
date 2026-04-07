package common
import spinal.core._
import spinal.lib._
import common.GenConfig

class SkidBuffer[T <: Data](dataType: HardType[T]) extends Component {
  val io = new Bundle {
    val in  = slave Stream(dataType())
    val out = master Stream(dataType())
  }
  // =========================
  // 1) 两个槽位：
  //    main : 当前对外输出的数据
  //    skid : 当下游突然反压时，临时兜住多出来的一拍
  // =========================
  val mainValid   = RegInit(False)
  val mainPayload = Reg(dataType())

  val skidValid   = RegInit(False)
  val skidPayload = Reg(dataType())

  // =========================
  // 2) 输出接口
  //    这版采用“纯寄存输出”，所以 out 只看 main
  // =========================
  io.out.valid   := mainValid
  io.out.payload := mainPayload

  // =========================
  // 3) 输入接口
  //    当 main 和 skid 都满时，不能再接收输入
  //    这里写成 !(mainValid && skidValid) 更直观
  // =========================
  io.in.ready := !(mainValid && skidValid)

  // =========================
  // 4) 握手事件
  // =========================
  val inFire  = io.in.valid  && io.in.ready
  val outFire = io.out.valid && io.out.ready

  // =========================
  // 5) 状态更新逻辑
  // =========================
  when(inFire && !outFire) {
    // 只有输入，没有输出
    when(!mainValid) {
      // main 空，优先写入 main
      mainPayload := io.in.payload
      mainValid   := True
    } otherwise {
      // main 已有数据，则写入 skid
      skidPayload := io.in.payload
      skidValid   := True
    }
  } elsewhen(!inFire && outFire) {
    // 只有输出，没有输入
    when(skidValid) {
      // skid 顶上来成为新的 main
      mainPayload := skidPayload
      mainValid   := True
      skidValid   := False
    } otherwise {
      // 没有后备数据了，main 清空
      mainValid := False
    }
  } elsewhen(inFire && outFire) {
    // 输入和输出同时发生
    when(skidValid) {
      // 原来是满的：
      //   main 被消费
      //   skid -> main
      //   新输入 -> skid
      mainPayload := skidPayload
      mainValid   := True

      skidPayload := io.in.payload
      skidValid   := True
    } otherwise {
      // 原来只有 main：
      //   main 被消费
      //   新输入直接补到 main
      mainPayload := io.in.payload
      mainValid   := True
    }
  }

  // 可选：用于帮助你调试思维
  // 合法状态不应该出现 main 空但 skid 非空
  assert(!( !mainValid && skidValid ))
}

object GenSkidBuffer {
  def main(args: Array[String]): Unit = {
    GenConfig.rtl("common").generateVerilog(new SkidBuffer(UInt(8 bits)))
  }
}