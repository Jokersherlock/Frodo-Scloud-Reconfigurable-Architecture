import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


# ============================================================
# Reset
# ============================================================

async def reset_dut(dut, cycles=5):
    """
    同步高电平复位
    """
    dut.reset.value = 1

    dut.rd_en.value = 0
    dut.rd_addr.value = 0

    dut.wr_en.value = 0
    dut.wr_addr.value = 0
    dut.wr_data.value = 0

    dut.acc_en.value = 0

    for _ in range(cycles):
        await RisingEdge(dut.clk)

    dut.reset.value = 0
    await RisingEdge(dut.clk)


# ============================================================
# Utility helpers
# ============================================================

async def step(dut, n=1):
    for _ in range(n):
        await RisingEdge(dut.clk)


def issue_idle(dut):
    dut.rd_en.value = 0
    dut.rd_addr.value = 0

    dut.wr_en.value = 0
    dut.wr_addr.value = 0
    dut.wr_data.value = 0

    dut.acc_en.value = 0


def issue_write(dut, addr, data):
    dut.rd_en.value = 0
    dut.rd_addr.value = 0

    dut.wr_en.value = 1
    dut.wr_addr.value = addr
    dut.wr_data.value = data

    dut.acc_en.value = 0


def issue_acc(dut, addr, data):
    dut.rd_en.value = 0
    dut.rd_addr.value = 0

    dut.wr_en.value = 1
    dut.wr_addr.value = addr
    dut.wr_data.value = data

    dut.acc_en.value = 1


def issue_read(dut, addr):
    dut.rd_en.value = 1
    dut.rd_addr.value = addr

    dut.wr_en.value = 0
    dut.wr_addr.value = 0
    dut.wr_data.value = 0

    dut.acc_en.value = 0


async def read_addr(dut, addr):
    """
    同步读接口：1拍发请求 + 1拍返回数据
    """
    issue_read(dut, addr)
    await RisingEdge(dut.clk)

    issue_idle(dut)
    await RisingEdge(dut.clk)

    return int(dut.rd_data.value)


async def check_read(dut, addr, expected, msg=""):
    got = await read_addr(dut, addr)

    dut._log.info(
        f"[CHECK] {msg} | addr={addr} got={got} expected={expected}"
    )

    assert got == expected, \
        f"[FAIL] {msg} | addr={addr} got={got} expected={expected}"


# ============================================================
# Main test
# ============================================================

@cocotb.test()
async def tb_acc_slice(dut):

    # --------------------------------------------------------
    # Start clock
    # --------------------------------------------------------
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # --------------------------------------------------------
    # Reset
    # --------------------------------------------------------
    await reset_dut(dut)

    # --------------------------------------------------------
    # Config
    # --------------------------------------------------------
    DATA_WIDTH = 64
    MASK = (1 << DATA_WIDTH) - 1

    # 可以通过环境变量改随机种子
    # 例如：make RANDOM_SEED=123
    seed = int(os.getenv("RANDOM_SEED", "42"))
    random.seed(seed)
    dut._log.info(f"==== RANDOM_SEED = {seed} ====")

    golden = {}

    def gget(addr):
        return golden.get(addr, 0)

    def gwrite(addr, data):
        golden[addr] = data & MASK

    def gacc(addr, data):
        golden[addr] = (gget(addr) + data) & MASK

    # ========================================================
    # Test 1: basic write/read
    # ========================================================

    dut._log.info("==== Test 1: basic write/read ====")

    issue_write(dut, 3, 10)
    gwrite(3, 10)
    await step(dut)

    issue_idle(dut)
    await step(dut, 3)

    await check_read(dut, 3, gget(3), "basic write/read")

    # ========================================================
    # Test 2: same address consecutive acc
    # ========================================================

    dut._log.info("==== Test 2: consecutive acc same addr ====")

    issue_acc(dut, 3, 1)
    gacc(3, 1)
    await step(dut)

    issue_acc(dut, 3, 2)
    gacc(3, 2)
    await step(dut)

    issue_acc(dut, 3, 3)
    gacc(3, 3)
    await step(dut)

    issue_acc(dut, 3, 4)
    gacc(3, 4)
    await step(dut)

    issue_idle(dut)
    await step(dut, 10)

    await check_read(dut, 3, gget(3), "same address acc")

    # ========================================================
    # Test 3: alternating addresses
    # ========================================================

    dut._log.info("==== Test 3: alternating acc ====")

    issue_write(dut, 5, 100)
    gwrite(5, 100)
    await step(dut)

    issue_idle(dut)
    await step(dut, 3)

    issue_write(dut, 6, 200)
    gwrite(6, 200)
    await step(dut)

    issue_idle(dut)
    await step(dut, 3)

    issue_acc(dut, 5, 11)
    gacc(5, 11)
    await step(dut)

    issue_acc(dut, 6, 22)
    gacc(6, 22)
    await step(dut)

    issue_acc(dut, 5, 33)
    gacc(5, 33)
    await step(dut)

    issue_acc(dut, 6, 44)
    gacc(6, 44)
    await step(dut)

    issue_idle(dut)
    await step(dut, 10)

    await check_read(dut, 5, gget(5), "alt acc addr5")
    await check_read(dut, 6, gget(6), "alt acc addr6")

    # ========================================================
    # Test 4: write then acc burst
    # ========================================================

    dut._log.info("==== Test 4: write then acc burst ====")

    issue_write(dut, 8, 50)
    gwrite(8, 50)
    await step(dut)

    issue_acc(dut, 8, 5)
    gacc(8, 5)
    await step(dut)

    issue_acc(dut, 8, 6)
    gacc(8, 6)
    await step(dut)

    issue_acc(dut, 8, 7)
    gacc(8, 7)
    await step(dut)

    issue_idle(dut)
    await step(dut, 10)

    await check_read(dut, 8, gget(8), "write+acc burst")

    # ========================================================
    # Test 5: 大批量随机测试（宽松模式）
    #
    # 目的：
    #   先用“操作后留足够拍数”的方式，验证大量随机功能正确性
    # ========================================================

    dut._log.info("==== Test 5: bulk random test (relaxed mode) ====")

    RELAXED_ITERS = 1000
    RELAXED_ADDR_MAX = 32
    RELAXED_DATA_MAX = 256

    for i in range(RELAXED_ITERS):
        op = random.randint(0, 99)
        addr = random.randint(0, RELAXED_ADDR_MAX - 1)
        data = random.randint(0, RELAXED_DATA_MAX - 1)

        if op < 35:
            # 普通写
            issue_write(dut, addr, data)
            gwrite(addr, data)
            await step(dut)

            issue_idle(dut)
            await step(dut, 3)

            # 偶尔立刻检查
            if random.random() < 0.2:
                await check_read(dut, addr, gget(addr), f"relaxed-write-{i}")

        elif op < 80:
            # acc
            issue_acc(dut, addr, data)
            gacc(addr, data)
            await step(dut)

            issue_idle(dut)
            await step(dut, 5)

            # 偶尔立刻检查
            if random.random() < 0.2:
                await check_read(dut, addr, gget(addr), f"relaxed-acc-{i}")

        else:
            # 读检查
            await check_read(dut, addr, gget(addr), f"relaxed-read-{i}")
            issue_idle(dut)
            await step(dut, 1)

    # ========================================================
    # Test 6: 大批量随机突发 acc 测试（burst mode）
    #
    # 目的：
    #   连续每拍都发 acc，专门测试打拍/连续累加/交替地址累加
    #
    # 策略：
    #   先打一串 burst，再 drain，最后统一检查
    # ========================================================

    dut._log.info("==== Test 6: bulk random burst acc test ====")

    BURST_GROUPS = 100
    BURST_LEN_MIN = 4
    BURST_LEN_MAX = 12
    BURST_ADDR_MAX = 16
    BURST_DATA_MAX = 64

    for g in range(BURST_GROUPS):
        burst_ops = []

        burst_len = random.randint(BURST_LEN_MIN, BURST_LEN_MAX)

        for _ in range(burst_len):
            addr = random.randint(0, BURST_ADDR_MAX - 1)
            data = random.randint(0, BURST_DATA_MAX - 1)
            burst_ops.append((addr, data))

        dut._log.info(f"[BURST {g}] len={burst_len} ops={burst_ops}")

        # 连续每拍打一条 acc
        for addr, data in burst_ops:
            issue_acc(dut, addr, data)
            gacc(addr, data)
            await step(dut)

        # 停下来，让内部流水排空
        issue_idle(dut)
        await step(dut, 12)

        # 随机检查若干地址
        for _ in range(5):
            addr = random.randint(0, BURST_ADDR_MAX - 1)
            await check_read(dut, addr, gget(addr), f"burst-check-group-{g}-addr-{addr}")

    # ========================================================
    # Test 7: 混合随机测试（write / acc / read，适中压力）
    #
    # 目的：
    #   同时覆盖：
    #     - 写后立刻 acc
    #     - 连续 acc
    #     - 交替地址
    #     - 随机读检查
    #
    # 注意：
    #   这里不做完全“每拍都随机乱发”的极限压力，
    #   而是控制一定的 drain，避免接口约束不明确时误报。
    # ========================================================

    dut._log.info("==== Test 7: mixed random regression ====")

    MIXED_ITERS = 1000
    MIXED_ADDR_MAX = 32
    MIXED_DATA_MAX = 128

    for i in range(MIXED_ITERS):
        op = random.randint(0, 99)
        addr = random.randint(0, MIXED_ADDR_MAX - 1)
        data = random.randint(0, MIXED_DATA_MAX - 1)

        if op < 25:
            issue_write(dut, addr, data)
            gwrite(addr, data)
            await step(dut)

            # 短暂空闲
            issue_idle(dut)
            await step(dut, random.randint(1, 3))

        elif op < 70:
            # 小 burst acc
            burst_len = random.randint(1, 4)
            for _ in range(burst_len):
                b_addr = random.randint(0, MIXED_ADDR_MAX - 1)
                b_data = random.randint(0, MIXED_DATA_MAX - 1)
                issue_acc(dut, b_addr, b_data)
                gacc(b_addr, b_data)
                await step(dut)

            issue_idle(dut)
            await step(dut, random.randint(4, 8))

        else:
            await check_read(dut, addr, gget(addr), f"mixed-read-{i}")
            issue_idle(dut)
            await step(dut, 1)

    # ========================================================
    # Final check
    # ========================================================

    dut._log.info("==== Final check ====")

    # 对前 32 个地址统一扫一遍
    for addr in range(32):
        await check_read(dut, addr, gget(addr), f"final check {addr}")

    dut._log.info("==== All cocotb tests passed ====")

    issue_idle(dut)
    await step(dut, 5)