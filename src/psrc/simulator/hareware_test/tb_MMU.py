import sys
import os
# 添加父目录到路径，以便导入 core 和 hardware 模块
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core import Simulator
from hardware.MMU import MMU
import numpy as np
from utils.data import ProbabilityDistribution


def get_distribution(mode):
    if mode == "Scloud":
        dis = {-1: 0.25, 0: 0.5, 1: 0.25}
        n = 600
        S_bits = 2
    elif mode == "Frodo-640":
        dis = {
            0: 14.17,   1: 13.30,  -1: 13.30,   2: 11.01,  -2: 11.01,
            3: 8.03,   -3: 8.03,    4: 5.16,   -4: 5.16,    5: 2.93,
            -5: 2.93,    6: 1.46,   -6: 1.46,    7: 0.64,   -7: 0.64,
            -8: 0.25,    9: 0.085,  -9: 0.085,  10: 0.026,
            -10: 0.026,  11: 0.006, -11: 0.006,  12: 0.0015, -12: 0.0015,
        }
        n = 640
        S_bits = 5
    elif mode == "Frodo-976":
        dis = {
            0: 17.21,   1: 15.68,  -1: 15.68,   2: 11.86,  -2: 11.86,
            3: 7.45,   -3: 7.45,    4: 3.88,   -4: 3.88,    5: 1.68,
            -5: 1.68,    6: 0.60,   -6: 0.60,    7: 0.18,   -7: 0.18,
            -8: 0.044,    9: 0.009,  -9: 0.009,  10: 0.0015,
            -10: 0.0015,
        }
        n = 976
        S_bits = 5
    elif mode == "Frodo-1344":
        dis = {
            0: 27.90,   1: 21.85,  -1: 21.85,   2: 10.49,  -2: 10.49,
            3: 3.09,   -3: 3.09,    4: 0.555,  -4: 0.555,   5: 0.061,
            -5: 0.061,   6: 0.003,  -6: 0.003,
        }
        n = 1344
        S_bits = 5
    else:
        raise ValueError("mode只能是Scloud,Frodo-640,Frodo-976,Frodo-1344")
    return dis,n,S_bits


def Sparse_evaluation(mode,batch_size,multiply_type,n_engines=4,accumulator_strategy="double_registers"):
    #不使用稀疏
    sim = Simulator()
    simulate_enable = False
    sparse_enable = False
    mmu = MMU("mmu",sim,data_simulate_enable=simulate_enable,sparse_enable=sparse_enable,n_engines=n_engines,accumulator_strategy=accumulator_strategy)
    dis,n,S_bits = get_distribution(mode)
    if multiply_type == "left":
        S_matrix = ProbabilityDistribution(dis).generate_matrix(shape=(n,8))
        A = np.random.randint(-7, 8, size=(4,n))
        ref_result = np.matmul(A,S_matrix)
        task = sim.spawn(mmu.execute_left, S_matrix, A, S_bits)
        sim.run(print_progress=False)
        _, ref_latency = task.result
    elif multiply_type == "right":
        S_matrix = ProbabilityDistribution(dis).generate_matrix(shape=(8,4))
        A = np.random.randint(-7, 8, size=(4,n))
        ref_result = np.matmul(S_matrix,A)
        task = sim.spawn(mmu.execute_right, S_matrix, A, S_bits)
        sim.run(print_progress=False)
        _, ref_latency = task.result
    else:
        raise ValueError("multiply_type只能是left,right")

    latency_list = []
    for i in range(batch_size):
        #清空sim和mmu
        sim = Simulator()
        simulate_enable = False
        sparse_enable = True
        mmu = MMU("mmu",sim,data_simulate_enable=simulate_enable,sparse_enable=sparse_enable,n_engines=n_engines,accumulator_strategy=accumulator_strategy)
        if multiply_type == "left": 
            S_matrix = ProbabilityDistribution(dis).generate_matrix(shape=(n,8))
            A = np.random.randint(-7, 8, size=(4,n))
            task = sim.spawn(mmu.execute_left, S_matrix, A, S_bits)
            sim.run(print_progress=False)
            _, latency = task.result
        elif multiply_type == "right":
            S_matrix = ProbabilityDistribution(dis).generate_matrix(shape=(8,4))
            A = np.random.randint(-7, 8, size=(4,n))
            task = sim.spawn(mmu.execute_right, S_matrix, A, S_bits)
            sim.run(print_progress=False)
            _, latency = task.result
        else:
            raise ValueError("multiply_type只能是left,right")
        latency_list.append(latency)
    
    # 转换为numpy数组便于统计
    latency_array = np.array(latency_list)
    
    # 基本统计量
    stats = {
        'count': len(latency_list),
        'mean': np.mean(latency_array),
        'median': np.median(latency_array),
        'std': np.std(latency_array),
        'min': np.min(latency_array),
        'max': np.max(latency_array),
        'ref_latency': ref_latency,  # 参考延迟（单次运行）
    }
    
    # 百分位数（常用性能指标）
    percentiles = [50, 75, 90, 95, 99]
    for p in percentiles:
        stats[f'p{p}'] = np.percentile(latency_array, p)
    
    # 与参考延迟的比较
    stats['vs_ref_mean'] = stats['mean'] - ref_latency
    stats['vs_ref_ratio'] = stats['mean'] / ref_latency if ref_latency > 0 else 0
    
    # 变异系数（标准差/均值，衡量相对波动）
    stats['cv'] = stats['std'] / stats['mean'] if stats['mean'] > 0 else 0
    
    # 打印统计结果
    print(f"\n{'='*60}")
    print(f"稀疏性评估统计 - {mode} - {multiply_type}")
    print(f"{'='*60}")
    print(f"样本数量: {stats['count']}")
    print(f"\n延迟统计 (cycles):")
    print(f"  均值:     {stats['mean']:.2f}")
    print(f"  中位数:   {stats['median']:.2f}")
    print(f"  标准差:   {stats['std']:.2f}")
    print(f"  最小值:   {stats['min']}")
    print(f"  最大值:   {stats['max']}")
    print(f"\n百分位数 (cycles):")
    for p in percentiles:
        print(f"  P{p}:      {stats[f'p{p}']:.2f}")
    print(f"\n参考延迟:  {stats['ref_latency']} cycles")
    print(f"与参考比较: {stats['vs_ref_mean']:+.2f} cycles ({stats['vs_ref_ratio']:.2%})")
    print(f"变异系数:   {stats['cv']:.4f}")
    print(f"{'='*60}\n")
    
    return stats, latency_array


if __name__ == "__main__":
    sim = Simulator()
    simulate_enable = False
    sparse_enable = False
    accumulator_strategy = "no_fifo"
    mmu = MMU("mmu",sim,data_simulate_enable=simulate_enable,sparse_enable=sparse_enable,accumulator_strategy=accumulator_strategy)
    mode = "Frodo-1344"
    n_engines = 4
    batch_size = 10
    dis,n,S_bits = get_distribution(mode)

    print("测试mmu左乘,mode:",mode)
    stats, latency_array = Sparse_evaluation(mode,batch_size,"left",n_engines=n_engines,accumulator_strategy=accumulator_strategy)
    print("stats",stats)

    print("测试mmu右乘,mode:",mode)
    stats, latency_array = Sparse_evaluation(mode,batch_size,"right",n_engines=n_engines,accumulator_strategy=accumulator_strategy)
    print("stats",stats)

    # print("测试mmu左乘")
    # S = ProbabilityDistribution(dis).generate_matrix(shape=(n,8))
    # A = np.random.randint(-7, 8, size=(4,n))
    # ref_result = np.matmul(A,S)
    # # 使用 spawn 启动任务，返回 Task 对象
    # task = sim.spawn(mmu.execute_left, S, A, S_bits)
    # sim.run()  # 运行模拟器直到所有任务完成
    # # 从 Task 对象获取返回值
    # result, latency = task.result
    # if simulate_enable:
    #     print("ref_result",ref_result)
    #     print("result",result)
    #     #print("latency",latency)
    #     print("ref_result==result",np.all(ref_result==result))
    # mmu.report_stats()

    # print("测试mmu右乘")
    # S = ProbabilityDistribution(dis).generate_matrix(shape=(8,4))
    # A = np.random.randint(-7, 8, size=(4,n))
    # ref_result = np.matmul(S,A)
    # # 使用 spawn 启动任务，返回 Task 对象
    # task = sim.spawn(mmu.execute_right, S, A, S_bits)
    # sim.run()  # 运行模拟器直到所有任务完成
    # # 从 Task 对象获取返回值
    # result, latency = task.result
    # if simulate_enable:
    #     print("ref_result",ref_result)
    #     print("result",result)
    #     #print("latency",latency)
    #     print("ref_result==result",np.all(ref_result==result))
    # mmu.report_stats()
