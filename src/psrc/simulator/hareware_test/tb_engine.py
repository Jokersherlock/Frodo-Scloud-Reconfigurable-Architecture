import sys
import os
# 添加父目录到路径，以便导入 core 和 hardware 模块
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core import Simulator
from hardware.MMU import Engine
import numpy as np


if __name__ == "__main__":
    sim = Simulator()
    simulate_enable = False
    engine = Engine("engine",sim,data_simulate_enable=simulate_enable)
    n =int(1344/4)
    S_bits = 5
    print("测试engine左乘")
    S = np.random.randint(-7, 8, size=(n,8))
    A = np.random.randint(-7, 8, size=(4,n))
    ref_result = np.matmul(A,S)
    # 使用 spawn 启动任务，返回 Task 对象
    task = sim.spawn(engine.execute_left, S, A, S_bits)
    sim.run()  # 运行模拟器直到所有任务完成
    # 从 Task 对象获取返回值
    result, latency = task.result
    if simulate_enable:
        print("ref_result",ref_result)
        print("result",result)
        #print("latency",latency)
        print("ref_result==result",np.all(ref_result==result))
    engine.report_stats()

    print("测试engine右乘")
    S = np.random.randint(-1, 2, size=(8,4))
    A = np.random.randint(-7, 8, size=(4,n))
    ref_result = np.matmul(S,A)
    # 使用 spawn 启动任务，返回 Task 对象
    task = sim.spawn(engine.execute_right, S, A, S_bits)
    sim.run()  # 运行模拟器直到所有任务完成
    # 从 Task 对象获取返回值
    result, latency = task.result
    if simulate_enable:
        print("ref_result",ref_result)
        print("result",result)
        #print("latency",latency)
        print("ref_result==result",np.all(ref_result==result))
    engine.report_stats()
