package mem.acc

import spinal.core._
import spinal.core.sim._
import spinal.sim._
import common.AccSliceConfig

object AccSliceSim {
    def main(args: Array[String]): Unit = {
        val cfg = AccSliceConfig(
            dataWidth = 64,
            depth     = 512
        )

        SimConfig
            .compile(new AccSlice(cfg))
            .doSim { dut =>

                // =====================================================
                // 1. 建立时钟
                // forkStimulus(10) 表示建立一个周期为 10 的时钟
                // 同时会自动处理默认 reset 流程
                // =====================================================
                dut.clockDomain.forkStimulus(period = 10)

                // =====================================================
                // 2. 输入初始化
                // 仿真开始时，先把所有输入清零/拉空闲
                // =====================================================
                dut.io.rd.en   #= false
                dut.io.rd.addr #= 0

                dut.io.wr.en   #= false
                dut.io.wr.addr #= 0
                dut.io.wr.data #= 0

                dut.io.acc_en  #= false

                // 等几拍，让 reset 和初始状态稳定下来
                dut.clockDomain.waitSampling(5)

                // =====================================================
                // 3. 一些辅助函数
                // =====================================================

                // 等待 n 个时钟周期
                def step(n: Int = 1): Unit = {
                    dut.clockDomain.waitSampling(n)
                }

                // 把所有输入拉回空闲态
                def issueIdle(): Unit = {
                    dut.io.rd.en   #= false
                    dut.io.rd.addr #= 0

                    dut.io.wr.en   #= false
                    dut.io.wr.addr #= 0
                    dut.io.wr.data #= 0

                    dut.io.acc_en  #= false
                }

                // 发起一拍普通写请求
                // 注意：这里只负责“这一拍发请求”，不自动多等几拍
                def issueWrite(addr: BigInt, data: BigInt): Unit = {
                    dut.io.rd.en   #= false
                    dut.io.rd.addr #= 0

                    dut.io.wr.en   #= true
                    dut.io.wr.addr #= addr
                    dut.io.wr.data #= data

                    dut.io.acc_en  #= false
                }

                // 发起一拍 acc 请求
                // 表示对 addr 做 += data
                def issueAcc(addr: BigInt, data: BigInt): Unit = {
                    dut.io.rd.en   #= false
                    dut.io.rd.addr #= 0

                    dut.io.wr.en   #= true
                    dut.io.wr.addr #= addr
                    dut.io.wr.data #= data

                    dut.io.acc_en  #= true
                }

                // 发起一拍普通读请求
                def issueRead(addr: BigInt): Unit = {
                    dut.io.rd.en   #= true
                    dut.io.rd.addr #= addr

                    dut.io.wr.en   #= false
                    dut.io.wr.addr #= 0
                    dut.io.wr.data #= 0

                    dut.io.acc_en  #= false
                }

                // -----------------------------------------------------
                // 做一次“保守读”
                // 当前你的设计是 sync-read 风格，因此这里按：
                //   第1拍：发读请求
                //   第2拍：等待数据有效
                // 的方式来取值
                // -----------------------------------------------------
                def read(addr: BigInt): BigInt = {
                    issueRead(addr)
                    step(1)

                    issueIdle()
                    step(1)

                    dut.io.rd.data.toBigInt
                }

                // 检查某个地址的值是否符合预期
                def checkRead(addr: BigInt, golden: BigInt, msg: String): Unit = {
                    val got = read(addr)
                    println(s"[CHECK] $msg | addr=$addr got=$got expect=$golden")
                    assert(
                        got == golden,
                        s"[FAIL] $msg | addr=$addr got=$got expect=$golden"
                    )
                }

                // 为了做最终检查，这里维护一个简单的软件黄金模型
                // 这里只需要记录我们测试覆盖的几个地址
                val golden = scala.collection.mutable.Map[BigInt, BigInt]()
                    .withDefaultValue(BigInt(0))

                val mask = (BigInt(1) << cfg.dataWidth) - 1

                def goldenWrite(addr: BigInt, data: BigInt): Unit = {
                    golden(addr) = data & mask
                }

                def goldenAcc(addr: BigInt, data: BigInt): Unit = {
                    golden(addr) = (golden(addr) + data) & mask
                }

                // =====================================================
                // 4. 先做一个基础 sanity test
                // =====================================================
                println("========================================")
                println("Sanity Test")
                println("========================================")

                // write addr=3, data=10
                issueWrite(3, 10)
                goldenWrite(3, 10)
                step(1)

                issueIdle()
                step(3)

                checkRead(3, golden(3), "sanity write/read")

                // =====================================================
                // 5. 压力测试1：同地址连续 acc
                // =====================================================
                println("========================================")
                println("Stress Test 1: back-to-back acc on same address")
                println("========================================")

                // 当前 golden(3) = 10
                // 连续每拍都发 acc，不留大空隙
                issueAcc(3, 1)
                goldenAcc(3, 1)
                step(1)

                issueAcc(3, 2)
                goldenAcc(3, 2)
                step(1)

                issueAcc(3, 3)
                goldenAcc(3, 3)
                step(1)

                issueAcc(3, 4)
                goldenAcc(3, 4)
                step(1)

                // 不再发新请求，留若干拍让内部流水“排空”
                issueIdle()
                step(10)

                checkRead(3, golden(3), "same address consecutive acc")

                // =====================================================
                // 6. 压力测试2：不同地址交替 acc
                // =====================================================
                println("========================================")
                println("Stress Test 2: alternating addresses")
                println("========================================")

                // 先初始化两个地址
                issueWrite(5, 100)
                goldenWrite(5, 100)
                step(1)

                issueIdle()
                step(3)

                issueWrite(6, 200)
                goldenWrite(6, 200)
                step(1)

                issueIdle()
                step(3)

                // 交替发 acc
                issueAcc(5, 11)
                goldenAcc(5, 11)
                step(1)

                issueAcc(6, 22)
                goldenAcc(6, 22)
                step(1)

                issueAcc(5, 33)
                goldenAcc(5, 33)
                step(1)

                issueAcc(6, 44)
                goldenAcc(6, 44)
                step(1)

                issueIdle()
                step(10)

                checkRead(5, golden(5), "alternating acc addr 5")
                checkRead(6, golden(6), "alternating acc addr 6")

                // =====================================================
                // 7. 压力测试3：普通写后立刻连续 acc
                // =====================================================
                println("========================================")
                println("Stress Test 3: write then consecutive acc")
                println("========================================")

                issueWrite(8, 50)
                goldenWrite(8, 50)
                step(1)

                // 这里故意只留很少的间隔
                issueAcc(8, 5)
                goldenAcc(8, 5)
                step(1)

                issueAcc(8, 6)
                goldenAcc(8, 6)
                step(1)

                issueAcc(8, 7)
                goldenAcc(8, 7)
                step(1)

                issueIdle()
                step(10)

                checkRead(8, golden(8), "write followed by consecutive acc")

                // =====================================================
                // 8. 压力测试4：连续 acc 后再读
                // =====================================================
                println("========================================")
                println("Stress Test 4: consecutive acc then read")
                println("========================================")

                issueWrite(10, 7)
                goldenWrite(10, 7)
                step(1)

                issueIdle()
                step(3)

                issueAcc(10, 1)
                goldenAcc(10, 1)
                step(1)

                issueAcc(10, 2)
                goldenAcc(10, 2)
                step(1)

                issueAcc(10, 3)
                goldenAcc(10, 3)
                step(1)

                issueIdle()
                step(8)

                checkRead(10, golden(10), "read after burst acc")

                // =====================================================
                // 9. 最后统一做一次全检查
                // =====================================================
                println("========================================")
                println("Final Check")
                println("========================================")

                for(addr <- Seq[BigInt](3, 5, 6, 8, 10)) {
                    checkRead(addr, golden(addr), s"final check addr=$addr")
                }

                println("========================================")
                println("All stress tests passed.")
                println("========================================")

                issueIdle()
                step(5)
            }
    }
}