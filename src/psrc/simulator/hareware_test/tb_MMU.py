import sys
import os
# 添加父目录到路径，以便导入 core 和 hardware 模块
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core import Simulator
from hardware.MMU import MMU
import numpy as np
from utils.data import ProbabilityDistribution


if __name__ == "__main__":
    sim = Simulator()
    simulate_enable = False
    sparse_enable = False
    mmu = MMU("mmu",sim,data_simulate_enable=simulate_enable,sparse_enable=sparse_enable)
    mode = "Frodo-976"
    n = 976
    S_bits = 5
    if mode == "Scloud":
        dis = {-1: 0.25, 0: 0.5, 1: 0.25}
        S_bits = 2
    elif mode == "Frodo-640":
        dis = {
            0: 14.17,   1: 13.30,  -1: 13.30,   2: 11.01,  -2: 11.01,
            3: 8.03,   -3: 8.03,    4: 5.16,   -4: 5.16,    5: 2.93,
            -5: 2.93,    6: 1.46,   -6: 1.46,    7: 0.64,   -7: 0.64,
            -8: 0.25,    9: 0.085,  -9: 0.085,  10: 0.026,
            -10: 0.026,  11: 0.006, -11: 0.006,  12: 0.0015, -12: 0.0015,
        }
    elif mode == "Frodo-976":
        dis = {
            0: 17.21,   1: 15.68,  -1: 15.68,   2: 11.86,  -2: 11.86,
            3: 7.45,   -3: 7.45,    4: 3.88,   -4: 3.88,    5: 1.68,
            -5: 1.68,    6: 0.60,   -6: 0.60,    7: 0.18,   -7: 0.18,
            -8: 0.044,    9: 0.009,  -9: 0.009,  10: 0.0015,
            -10: 0.0015,
        }
    elif mode == "Frodo-1344":
        dis = {
            0: 27.90,   1: 21.85,  -1: 21.85,   2: 10.49,  -2: 10.49,
            3: 3.09,   -3: 3.09,    4: 0.555,  -4: 0.555,   5: 0.061,
            -5: 0.061,   6: 0.003,  -6: 0.003,
        }
    else:
        raise ValueError("mode只能是Scloud,Frodo-640,Frodo-976,Frodo-1344")

    print("测试mmu左乘")
    S = ProbabilityDistribution(dis).generate_matrix(shape=(n,8))
    A = np.random.randint(-7, 8, size=(4,n))
    ref_result = np.matmul(A,S)
    # 使用 spawn 启动任务，返回 Task 对象
    task = sim.spawn(mmu.execute_left, S, A, S_bits)
    sim.run()  # 运行模拟器直到所有任务完成
    # 从 Task 对象获取返回值
    result, latency = task.result
    if simulate_enable:
        print("ref_result",ref_result)
        print("result",result)
        #print("latency",latency)
        print("ref_result==result",np.all(ref_result==result))
    mmu.report_stats()

    print("测试mmu右乘")
    S = ProbabilityDistribution(dis).generate_matrix(shape=(8,4))
    A = np.random.randint(-7, 8, size=(4,n))
    ref_result = np.matmul(S,A)
    # 使用 spawn 启动任务，返回 Task 对象
    task = sim.spawn(mmu.execute_right, S, A, S_bits)
    sim.run()  # 运行模拟器直到所有任务完成
    # 从 Task 对象获取返回值
    result, latency = task.result
    if simulate_enable:
        print("ref_result",ref_result)
        print("result",result)
        #print("latency",latency)
        print("ref_result==result",np.all(ref_result==result))
    mmu.report_stats()
