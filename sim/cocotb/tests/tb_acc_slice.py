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
async def test_accslice(dut):

    # --------------------------------------------------------
    # Start clock
    # --------------------------------------------------------
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # --------------------------------------------------------
    # Reset
    # --------------------------------------------------------
    await reset_dut(dut)

    golden = {}

    def gget(addr):
        return golden.get(addr, 0)

    def gwrite(addr, data):
        golden[addr] = data

    def gacc(addr, data):
        golden[addr] = gget(addr) + data

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
    # Final check
    # ========================================================

    dut._log.info("==== Final check ====")

    for addr in [3, 5, 6, 8]:
        await check_read(dut, addr, gget(addr), f"final check {addr}")

    dut._log.info("==== All cocotb tests passed ====")

    issue_idle(dut)
    await step(dut, 5)