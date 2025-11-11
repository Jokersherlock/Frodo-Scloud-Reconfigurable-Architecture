import numpy as np
from .data import TransRow

# --- 辅助函数：补码转换 ---
def to_twos_complement(value, S):
    """
    将一个整数转换为其 S 位补码二进制字符串，带有削峰处理。
    
    参数:
        value (int): 要转换的整数值。
        S (int): 补码位宽。
        
    返回:
        str: S 位的补码二进制字符串。
    """
    min_val = -(1 << (S - 1))
    max_val = (1 << (S - 1)) - 1
    
    # 削峰处理
    value = np.clip(value, min_val, max_val)
    
    if value < 0:
        value = (1 << S) + value
        
    return format(value, f'0{S}b') 

def create_transrow_tasks_from_matrix(W_int, S_bits):
    """
    接收一个整数权重矩阵 W_int,执行 S_bits 位切片，
    并返回一个 TransRow 对象的列表。

    参数:
        W_int (np.ndarray): N x K 的原始整数权重矩阵。
        S_bits (int): 量化位宽。

    返回:
        list: 包含 S*N 个 TransRow 对象的列表。
    """
    
    if W_int.ndim != 2:
        raise ValueError("输入的权重矩阵 W_int 必须是二维的。")
    N, K = W_int.shape # N=原始行数, K=原始列数(即TransRow宽度T)

    #print(f"正在从 {N}x{K} (S={S_bits}) 矩阵生成 {S_bits*N} 个 TransRow 任务...")

    # 1. 创建一个临时的 S*N x K 结构来存储二元数据
    #    我们使用一个列表的列表来构建
    temp_binary_rows = [[] for _ in range(S_bits * N)]
    
    # 2. 遍历原始矩阵，执行位切片
    #    这个过程在逻辑上等同于“转置”和“切片”
    for i in range(N): # 遍历原始 N 行
        for j in range(K): # 遍历原始 K 列
            # 获取 S-bit 补码字符串
            bin_str = to_twos_complement(W_int[i, j], S_bits)
            
            # 将 S 个 bit 分发到 S 个不同的目标行
            for s in range(S_bits): # s=0 是 MSB, s=S-1 是 LSB
                target_row_index = i * S_bits + s
                bit_value = int(bin_str[s])
                temp_binary_rows[target_row_index].append(bit_value)

    # 3. 遍历这个 S*N 的二元数据列表，创建 Task 对象
    task_list = []
    for r in range(S_bits * N): # r 是 (S*N, K) 矩阵中的行索引
        
        # 获取该行的二元数据
        binary_row_data = temp_binary_rows[r]
        
        # 获取该行对应的元数据
        original_row_idx = r // S_bits
        
        # 计算位级别 (0=LSB, S-1=MSB)
        # r % S_bits: 0=MSB, 1=Bit S-2, ..., S-1=LSB
        bit_level = S_bits - 1 - (r % S_bits) 
        
        # 创建并添加 Task 对象
        task = TransRow(binary_row_data, bit_level, original_row_idx)
        task_list.append(task)
        
    #print(f"成功创建 {len(task_list)} 个任务。")
    return task_list