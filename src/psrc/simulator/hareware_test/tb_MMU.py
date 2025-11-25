import sys
import os
# 添加父目录到路径，以便导入 core 和 hardware 模块
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core import Simulator
from hardware.MMU import MMU
import numpy as np
from utils.data import ProbabilityDistribution
import matplotlib.pyplot as plt

# 设置matplotlib支持中文显示
plt.rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei', 'DejaVu Sans']  # 用来正常显示中文标签
plt.rcParams['axes.unicode_minus'] = False  # 用来正常显示负号


def get_distribution(mode,n_PEs):
    if mode == "Scloud-128":
        dis = {-1: 0.25, 0: 0.5, 1: 0.25}
        m  = 600
        n = 600
        mbar = 8
        nbar = 8
        S_bits = 2
        hash_latency = np.ceil(24*n*16/1344)*n_PEs
    elif mode == "Scloud-192":
        dis = {-1: 0.25, 0: 0.5, 1: 0.25}
        m  = 928
        n = 896
        mbar = 8
        nbar = 8
        S_bits = 2
        hash_latency = np.ceil(24*n*16/1344)*n_PEs
    elif mode == "Scloud-256":
        dis = {-1: 0.25, 0: 0.5, 1: 0.25}
        m  = 1136
        n = 1120
        mbar = 12
        nbar = 11
        S_bits = 2
        hash_latency = np.ceil(24*n*16/1344)*4
    elif mode == "Frodo-640":
        dis = {
            0: 14.17,   1: 13.30,  -1: 13.30,   2: 11.01,  -2: 11.01,
            3: 8.03,   -3: 8.03,    4: 5.16,   -4: 5.16,    5: 2.93,
            -5: 2.93,    6: 1.46,   -6: 1.46,    7: 0.64,   -7: 0.64,
            -8: 0.25,    9: 0.085,  -9: 0.085,  10: 0.026,
            -10: 0.026,  11: 0.006, -11: 0.006,  12: 0.0015, -12: 0.0015,
        }
        n = 640
        m = 640
        mbar = 8
        nbar = 8
        S_bits = 5
        hash_latency = np.ceil(24*n*16/1088)*n_PEs
    elif mode == "Frodo-976":
        dis = {
            0: 17.21,   1: 15.68,  -1: 15.68,   2: 11.86,  -2: 11.86,
            3: 7.45,   -3: 7.45,    4: 3.88,   -4: 3.88,    5: 1.68,
            -5: 1.68,    6: 0.60,   -6: 0.60,    7: 0.18,   -7: 0.18,
            -8: 0.044,    9: 0.009,  -9: 0.009,  10: 0.0015,
            -10: 0.0015,
        }
        n = 976
        m = 976
        mbar = 8
        nbar = 8
        S_bits = 5
        hash_latency = np.ceil(24*n*16/1344)*n_PEs
    elif mode == "Frodo-1344":
        dis = {
            0: 27.90,   1: 21.85,  -1: 21.85,   2: 10.49,  -2: 10.49,
            3: 3.09,   -3: 3.09,    4: 0.555,  -4: 0.555,   5: 0.061,
            -5: 0.061,   6: 0.003,  -6: 0.003,
        }
        n = 1344
        m = 1344
        mbar = 8
        nbar = 8
        S_bits = 5
        hash_latency = np.ceil(24*n*16/1344)*n_PEs
    else:
        raise ValueError("mode只能是Scloud,Frodo-640,Frodo-976,Frodo-1344")
    return dis,n,mbar,nbar,S_bits,hash_latency


def Sparse_evaluation(mode,batch_size,multiply_type,config):
    #不使用稀疏
    sim = Simulator()
    #mmu = MMU("mmu",sim,**config)
    config['sparse_enable'] = False
    n_PEs = config['n_PEs']
    mmu = MMU("mmu",sim,**config)
    dis,n,mbar,nbar,S_bits,hash_latency = get_distribution(mode,n_PEs)
    if multiply_type == "left":
        S_matrix = ProbabilityDistribution(dis).generate_matrix(shape=(n,nbar))
        A = np.random.randint(-7, 8, size=(n_PEs,n))
        ref_result = np.matmul(A,S_matrix)
        task = sim.spawn(mmu.execute_left, S_matrix, A, S_bits)
        sim.run(print_progress=False)
        _, ref_latency = task.result
    elif multiply_type == "right":
        S_matrix = ProbabilityDistribution(dis).generate_matrix(shape=(mbar,n_PEs))
        A = np.random.randint(-7, 8, size=(n_PEs,n))
        ref_result = np.matmul(S_matrix,A)
        task = sim.spawn(mmu.execute_right, S_matrix, A, S_bits)
        sim.run(print_progress=False)
        _, ref_latency = task.result
    else:
        raise ValueError("multiply_type只能是left,right")

    # 当n_lanes=5时，只运行sparse_enable=False的结果，无需跑对照
    if config['n_lanes'] == 5:
        # 构建简化的统计信息
        stats = {
            'mode': mode,
            'count': 1,
            'mean': ref_latency,
            'median': ref_latency,
            'std': 0,
            'min': ref_latency,
            'max': ref_latency,
            'ref_latency': ref_latency,
            'hash_latency': hash_latency,
            'n_engines': config['n_engines'],
            'n_PEs': config['n_PEs'],
            'n_lanes': config['n_lanes'],
            'slice_latency': config['slice_latency'],
            'buffer_latency': config['buffer_latency'],
            'vs_ref_mean': 0,
            'vs_ref_ratio': 1.0,
            'cv': 0,
        }
        # 百分位数（常用性能指标）
        percentiles = [50, 75, 90, 95, 99]
        for p in percentiles:
            stats[f'p{p}'] = ref_latency
        latency_array = np.array([ref_latency])
        return stats, latency_array

    latency_list = []
    for i in range(batch_size):
        sim.reset()
        #mmu = MMU("mmu",sim,**config)
        config['sparse_enable'] = True
        mmu = MMU("mmu",sim,**config)
        if multiply_type == "left": 
            S_matrix = ProbabilityDistribution(dis).generate_matrix(shape=(n,nbar))
            A = np.random.randint(-7, 8, size=(n_PEs,n))
            task = sim.spawn(mmu.execute_left, S_matrix, A, S_bits)
            sim.run(print_progress=False)
            _, latency = task.result
        elif multiply_type == "right":
            S_matrix = ProbabilityDistribution(dis).generate_matrix(shape=(mbar,n_PEs))
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
        'mode': mode,
        'count': len(latency_list),
        'mean': np.mean(latency_array),
        'median': np.median(latency_array),
        'std': np.std(latency_array),
        'min': np.min(latency_array),
        'max': np.max(latency_array),
        'ref_latency': ref_latency,
        'hash_latency': hash_latency, # 参考延迟（单次运行）
        'n_engines': config['n_engines'],
        'n_PEs': config['n_PEs'],
        'n_lanes': config['n_lanes'],
        'slice_latency': config['slice_latency'],
        'buffer_latency': config['buffer_latency'],
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
    # print(f"\n{'='*60}")
    # print(f"稀疏性评估统计 - {mode} - {multiply_type}")
    # print(f"{'='*60}")
    # print(f"样本数量: {stats['count']}")
    # print(f"\n延迟统计 (cycles):")
    # print(f"  均值:     {stats['mean']:.2f}")
    # print(f"  中位数:   {stats['median']:.2f}")
    # print(f"  标准差:   {stats['std']:.2f}")
    # print(f"  最小值:   {stats['min']}")
    # print(f"  最大值:   {stats['max']}")
    # print(f"\n百分位数 (cycles):")
    # for p in percentiles:
    #     print(f"  P{p}:      {stats[f'p{p}']:.2f}")
    # print(f"\n参考延迟:  {stats['ref_latency']} cycles")
    # print(f"与参考比较: {stats['vs_ref_mean']:+.2f} cycles ({stats['vs_ref_ratio']:.2%})")
    # print(f"变异系数:   {stats['cv']:.4f}")
    # print(f"{'='*60}\n")
    # print(f"哈希延迟:  {hash_latency} cycles")
    
    return stats, latency_array

def print_stats(stats):
    print(f"\n{'='*60}")
    if 'mode' in stats:
        print(f"统计报告: {stats['mode']}")
    print(f"{'='*60}")
    if 'count' in stats:
        print(f"样本数量: {stats['count']}")
    if 'mean' in stats:
        print(f"\n延迟统计 (cycles):")
        print(f"  均值:     {stats['mean']:.2f}")
    if 'ref_latency' in stats:
        print(f"\n参考延迟:  {stats['ref_latency']} cycles")
    if 'vs_ref_mean' in stats and 'vs_ref_ratio' in stats:
        print(f"与参考比较: {stats['vs_ref_mean']:+.2f} cycles ({(1-stats['vs_ref_ratio']):.2%})")
    if 'cv' in stats:
        print(f"变异系数:   {stats['cv']:.4f}")
    if 'hash_latency' in stats:
        print(f"哈希延迟:  {stats['hash_latency']} cycles")
    #print(f"n_engines: {stats['n_engines']}")
    #print(f"accumulator_strategy: {stats['accumulator_strategy']}")
    print(f"{'='*60}\n")

def plot_latency_histogram(mode, batch_size, config, multiply_type="left"):
    """
    生成latency在sparse_enable使能时的频率分布直方图
    
    参数:
        mode: 算法名称，如"Frodo-640"
        batch_size: 批次大小
        config: 配置字典
        multiply_type: 乘法类型，"left"或"right"，默认为"left"
    
    返回:
        如果n_lanes=5，直接返回None
        否则返回latency数组和统计信息
    """
    # 如果n_lanes=5，直接返回
    if config['n_lanes'] == 5:
        print(f"n_lanes=5，跳过直方图生成")
        return None, None
    
    # 运行sparse_enable=True的测试，收集latency数据
    sim = Simulator()
    n_PEs = config['n_PEs']
    dis, n, mbar, nbar, S_bits, hash_latency = get_distribution(mode, n_PEs)
    
    latency_list = []
    for i in range(batch_size):
        sim.reset()
        config['sparse_enable'] = True
        mmu = MMU("mmu", sim, **config)
        if multiply_type == "left":
            S_matrix = ProbabilityDistribution(dis).generate_matrix(shape=(n, nbar))
            A = np.random.randint(-7, 8, size=(n_PEs, n))
            task = sim.spawn(mmu.execute_left, S_matrix, A, S_bits)
            sim.run(print_progress=False)
            _, latency = task.result
        elif multiply_type == "right":
            S_matrix = ProbabilityDistribution(dis).generate_matrix(shape=(mbar, n_PEs))
            A = np.random.randint(-7, 8, size=(n_PEs, n))
            task = sim.spawn(mmu.execute_right, S_matrix, A, S_bits)
            sim.run(print_progress=False)
            _, latency = task.result
        else:
            raise ValueError("multiply_type只能是left,right")
        latency_list.append(latency)
    
    # 转换为numpy数组
    latency_array = np.array(latency_list)
    
    # 计算合适的bins数量（基于数据范围和样本数）
    latency_min = int(np.min(latency_array))
    latency_max = int(np.max(latency_array))
    latency_range = latency_max - latency_min + 1
    
    # 对于整数延迟数据，使用更合理的bins策略
    if latency_range <= 100:
        # 如果范围较小，每个整数一个bin
        bins = np.arange(latency_min - 0.5, latency_max + 1.5, 1)
    else:
        # 如果范围较大，使用合理的bins数量（约30-50个）
        num_bins = min(50, max(30, int(np.sqrt(len(latency_array)))))
        bins = num_bins
    
    # 绘制直方图
    plt.figure(figsize=(10, 6))
    n, bins_edges, patches = plt.hist(latency_array, bins=bins, edgecolor='black', alpha=0.7, align='left')
    plt.xlabel('延迟 (cycles)', fontsize=12)
    plt.ylabel('频率', fontsize=12)
    plt.title(f'{mode} (sparse_enable=True)\n'
              f'n_engines={config["n_engines"]}, n_PEs={config["n_PEs"]}, n_lanes={config["n_lanes"]}, '
              f'batch_size={batch_size}', fontsize=12)
    plt.grid(True, alpha=0.3, axis='y')
    
    # 设置x轴为整数刻度
    ax = plt.gca()
    ax.xaxis.set_major_locator(plt.MaxNLocator(integer=True))
    
    # 添加统计信息
    mean_latency = np.mean(latency_array)
    median_latency = np.median(latency_array)
    std_latency = np.std(latency_array)
    plt.axvline(mean_latency, color='r', linestyle='--', linewidth=2, label=f'均值: {mean_latency:.2f}')
    plt.axvline(median_latency, color='g', linestyle='--', linewidth=2, label=f'中位数: {median_latency:.2f}')
    plt.legend(fontsize=10)
    
    # 添加文本统计信息
    stats_text = f'样本数: {len(latency_array)}\n'
    stats_text += f'均值: {mean_latency:.2f}\n'
    stats_text += f'中位数: {median_latency:.2f}\n'
    stats_text += f'标准差: {std_latency:.2f}\n'
    stats_text += f'最小值: {np.min(latency_array)}\n'
    stats_text += f'最大值: {np.max(latency_array)}'
    plt.text(0.02, 0.98, stats_text, transform=plt.gca().transAxes,
             fontsize=9, verticalalignment='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))
    
    plt.tight_layout()
    plt.show()
    
    # 构建统计信息
    stats = {
        'mode': mode,
        'count': len(latency_list),
        'mean': mean_latency,
        'median': median_latency,
        'std': std_latency,
        'min': np.min(latency_array),
        'max': np.max(latency_array),
        'hash_latency': hash_latency,
        'n_engines': config['n_engines'],
        'n_PEs': config['n_PEs'],
        'n_lanes': config['n_lanes'],
    }
    
    return stats, latency_array
    
def Performance_evaluation(batch_size,config):
    n_engines = config['n_engines']
    n_PEs = config['n_PEs']
    n_lanes = config['n_lanes']
    print(f"{'='*60}")
    print(f"n_engines: {n_engines}")
    print(f"n_PEs: {n_PEs}")
    print(f"n_lanes: {n_lanes}")

    modes = ["Frodo-640","Frodo-976","Frodo-1344","Scloud-128","Scloud-192","Scloud-256"]
    for mode in modes:
        print(f"{'='*60}")
        print(f"mode: {mode}")
        print(f"{'='*60}")
        stats, latency_array = Sparse_evaluation(mode,batch_size,"left",config)
        print_stats(stats)
        # stats, latency_array = Sparse_evaluation(mode,batch_size,"right",config)
        # print_stats(stats)
    print(f"{'='*60}\n")

if __name__ == "__main__":
    sim = Simulator()
    
    config = {
        'data_simulate_enable': False,
        'sparse_enable': True,
        'n_engines': 4,
        'n_PEs': 4,
        'n_lanes': 2,
        'slice_latency': 1,
        'buffer_latency': 1,
    }
    
    batch_size = 1000
    
    # stats, latency_array = Sparse_evaluation("Scloud-192",batch_size,"left",config)
    # print_stats(stats)

    config['n_engines'] = 8
    config['n_lanes'] = 1
    plot_latency_histogram("Frodo-640",batch_size,config)

    # config['n_lanes'] = 1
    # config['n_engines'] = 8
    # Performance_evaluation(batch_size,config)
    # config['n_engines'] = 4
    # config['n_lanes'] = 2
    # Performance_evaluation(batch_size,config)
    # config['n_engines'] = 2
    # config['n_lanes'] = 5
    # Performance_evaluation(batch_size,config)


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
