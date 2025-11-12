import numpy as np

class TransRow:
    """
    TransRow(二元行)任务对象。
    """
    
    def __init__(self, binary_row_data, bit_level, target_accumulator):
        """
        初始化一个 TransRow 任务。

        参数:
            binary_row_data (list or np.ndarray):
                这一行的 T-bit (或 K-bit) 二元数据。例如 [1, 0, 1, 1]。
                
            bit_level (int):
                该行对应的位级别。
                这将决定最终结果的“左移数目”。
                
            target_accumulator (int):
                该任务的计算结果最终应累加到的“目标输出通道”
        """
        
        # 1. 二元数据 (例如 [1, 0, 1, 1])
        # 我们将其存储为 numpy 数组以便后续可能的操作
        self.binary_data = np.asarray(binary_row_data, dtype=int)
        # 2. 左移数目 (即位级别)
        self.shift_amount = bit_level
        
        # 3. 目标输出通道 (供求和)
        self.target_accumulator = target_accumulator

        # --- 额外信息 (方便调试和扩展) ---
        # 该二元数据对应的整数值 (Node 值)，用于Hasse图查找
        self.value = int("".join(map(str, self.binary_data)), 2)
        
        # 该二元数据中 '1' 的个数
        self.popcount = np.sum(self.binary_data)
        
    # def __repr__(self):
    #     """返回一个简洁的字符串表示。"""
    #     row_str = "".join(map(str, self.binary_data))
    #     return (f"Task(Data: {row_str} (Val:{self.value}), "
    #             f"Shift: {self.shift_amount}, "
    #             f"TargetAcc: {self.target_accumulator})")

class MatrixSlice:
    """
    MatrixSlice(矩阵切片)对象，包含多个 TransRow 任务。
    """
    
    def __init__(self, trans_rows):
        """
        初始化一个 MatrixSlice 对象。

        参数:
            trans_rows (list): TransRow 对象的列表。
        """
        if not isinstance(trans_rows, list):
            raise TypeError("trans_rows 必须是一个列表。")
        
        # 验证所有元素都是 TransRow 对象
        for row in trans_rows:
            if not isinstance(row, TransRow):
                raise TypeError(f"列表中的元素必须是 TransRow 对象，但发现了 {type(row)}。")
        
        self.trans_rows = trans_rows
        self.num_rows = len(trans_rows)
        
        # 如果列表不为空，获取一些统计信息
        if self.num_rows > 0:
            self.row_width = len(trans_rows[0].binary_data)
            self.bit_levels = sorted(set(row.shift_amount for row in trans_rows))
            self.target_accumulators = sorted(set(row.target_accumulator for row in trans_rows))
        else:
            self.row_width = 0
            self.bit_levels = []
            self.target_accumulators = []

        self.numpy_array = self.to_numpy_array()
    
    def __len__(self):
        """返回 TransRow 的数量。"""
        return self.num_rows
    
    def __getitem__(self, index):
        """支持索引访问。"""
        return self.trans_rows[index]
    
    def __iter__(self):
        """支持迭代。"""
        return iter(self.trans_rows)
    
    def __repr__(self):
        """返回一个简洁的字符串表示。"""
        if self.num_rows == 0:
            return "MatrixSlice(空)"
        
        return (f"MatrixSlice(行数: {self.num_rows}, "
                f"行宽: {self.row_width}, "
                f"位级别: {self.bit_levels}, "
                f"目标累加器: {self.target_accumulators})")
    
    def summary(self):
        """
        返回矩阵切片的统计摘要信息。
        
        返回:
            dict: 包含统计信息的字典。
        """
        if self.num_rows == 0:
            return {
                "行数": 0,
                "行宽": 0,
                "位级别": [],
                "目标累加器": []
            }
        
        # 统计每个位级别的行数
        bit_level_counts = {}
        for row in self.trans_rows:
            level = row.shift_amount
            bit_level_counts[level] = bit_level_counts.get(level, 0) + 1
        
        # 统计每个目标累加器的行数
        accumulator_counts = {}
        for row in self.trans_rows:
            acc = row.target_accumulator
            accumulator_counts[acc] = accumulator_counts.get(acc, 0) + 1
        
        # 统计 popcount 分布
        popcounts = [row.popcount for row in self.trans_rows]
        
        return {
            "行数": self.num_rows,
            "行宽": self.row_width,
            "位级别": self.bit_levels,
            "位级别分布": bit_level_counts,
            "目标累加器": self.target_accumulators,
            "目标累加器分布": accumulator_counts,
            "Popcount统计": {
                "最小值": min(popcounts) if popcounts else 0,
                "最大值": max(popcounts) if popcounts else 0,
                "平均值": sum(popcounts) / len(popcounts) if popcounts else 0,
            }
        }
    
    def visualize(self, max_rows=20, show_details=True):
        """
        可视化矩阵切片的内容。
        
        参数:
            max_rows (int): 最多显示的行数。如果为 None，显示所有行。
            show_details (bool): 是否显示每行的详细信息。
        """
        if self.num_rows == 0:
            print("MatrixSlice: 空")
            return
        
        print("=" * 80)
        print(f"MatrixSlice 可视化")
        print("=" * 80)
        print(f"总行数: {self.num_rows}")
        print(f"行宽: {self.row_width}")
        print(f"位级别: {self.bit_levels}")
        print(f"目标累加器: {self.target_accumulators}")
        print("-" * 80)
        
        # 确定要显示的行数
        display_rows = self.num_rows if max_rows is None else min(max_rows, self.num_rows)
        
        for i in range(display_rows):
            row = self.trans_rows[i]
            row_str = "".join(map(str, row.binary_data))
            
            if show_details:
                print(f"行 {i:3d}: {row_str} | "
                      f"值={row.value:4d} | "
                      f"Popcount={row.popcount:2d} | "
                      f"位级别={row.shift_amount:2d} | "
                      f"目标累加器={row.target_accumulator:2d}")
            else:
                print(f"行 {i:3d}: {row_str}")
        
        if self.num_rows > display_rows:
            print(f"... (还有 {self.num_rows - display_rows} 行未显示)")
        
        print("=" * 80)
    
    def visualize_matrix(self):
        """
        以矩阵形式可视化所有 TransRow 的二元数据。
        """
        if self.num_rows == 0:
            print("MatrixSlice: 空")
            return
        
        print("=" * 80)
        print(f"MatrixSlice 矩阵视图 (共 {self.num_rows} 行 x {self.row_width} 列)")
        print("=" * 80)
        
        for i, row in enumerate(self.trans_rows):
            row_str = " ".join(map(str, row.binary_data))
            print(f"行 {i:3d} [位级={row.shift_amount:2d}, 目标={row.target_accumulator:2d}]: {row_str}")
        
        print("=" * 80)
    
    def get_rows_by_bit_level(self, bit_level):
        """
        获取指定位级别的所有 TransRow。
        
        参数:
            bit_level (int): 位级别。
            
        返回:
            list: 该位级别的 TransRow 列表。
        """
        return [row for row in self.trans_rows if row.shift_amount == bit_level]
    
    def get_rows_by_accumulator(self, accumulator):
        """
        获取指定目标累加器的所有 TransRow。
        
        参数:
            accumulator (int): 目标累加器索引。
            
        返回:
            list: 该目标累加器的 TransRow 列表。
        """
        return [row for row in self.trans_rows if row.target_accumulator == accumulator]
    
    def to_numpy_array(self):
        """
        将所有 TransRow 的二元数据转换为 numpy 数组。
        
        返回:
            np.ndarray: 形状为 (num_rows, row_width) 的二维数组。
        """
        if self.num_rows == 0:
            return np.array([]).reshape(0, 0)
        
        return np.array([row.binary_data for row in self.trans_rows])


class ProbabilityDistribution:
    """
    概率分布类，用于表示每个数值的概率，并生成满足该分布的矩阵。
    """
    
    def __init__(self, distribution):
        """
        初始化概率分布。
        
        参数:
            distribution (dict or list): 
                概率分布定义。可以是：
                - 字典: {value: probability} 或 {value: count}（会自动归一化）
                - 列表: [(value, probability), ...] 或 [(value, count), ...]
        
        示例:
            # 使用字典定义概率
            dist = ProbabilityDistribution({-1: 0.25, 0: 0.5, 1: 0.25})
            
            # 使用字典定义计数（会自动归一化为概率）
            dist = ProbabilityDistribution({-1: 1, 0: 2, 1: 1})
            
            # 使用列表定义
            dist = ProbabilityDistribution([(-1, 0.25), (0, 0.5), (1, 0.25)])
        """
        # 将输入转换为统一的字典格式
        if isinstance(distribution, dict):
            self._distribution_dict = distribution.copy()
        elif isinstance(distribution, list):
            # 列表格式：[(value, prob), ...]
            self._distribution_dict = {value: prob for value, prob in distribution}
        else:
            raise TypeError(f"distribution 必须是 dict 或 list，但收到了 {type(distribution)}")
        
        # 检查是否所有值都是数值
        if not all(isinstance(k, (int, float, np.integer, np.floating)) 
                   for k in self._distribution_dict.keys()):
            raise ValueError("分布的所有键（数值）必须是数字类型")
        
        if not all(isinstance(v, (int, float, np.integer, np.floating)) 
                   for v in self._distribution_dict.values()):
            raise ValueError("分布的所有值（概率/计数）必须是数字类型")
        
        # 归一化概率（如果总和不为1，则归一化）
        total = sum(self._distribution_dict.values())
        if total <= 0:
            raise ValueError("概率/计数的总和必须大于0")
        
        if abs(total - 1.0) > 1e-10:  # 如果总和不是1，则归一化
            self._distribution_dict = {k: v / total for k, v in self._distribution_dict.items()}
        
        # 提取数值和对应的概率
        self.values = np.array(list(self._distribution_dict.keys()))
        self.probabilities = np.array(list(self._distribution_dict.values()))
        
        # 验证概率总和为1（归一化后）
        prob_sum = np.sum(self.probabilities)
        if abs(prob_sum - 1.0) > 1e-10:
            raise ValueError(f"概率归一化后总和应为1，但得到 {prob_sum}")
    
    def __repr__(self):
        """返回概率分布的字符串表示。"""
        items = sorted(self._distribution_dict.items())
        items_str = ", ".join(f"{val}: {prob:.4f}" for val, prob in items)
        return f"ProbabilityDistribution({{{items_str}}})"
    
    def __getitem__(self, value):
        """获取指定数值的概率。"""
        return self._distribution_dict.get(value, 0.0)
    
    def get_values(self):
        """
        获取所有可能的数值。
        
        返回:
            np.ndarray: 所有可能的数值数组。
        """
        return self.values.copy()
    
    def get_probabilities(self):
        """
        获取所有数值对应的概率。
        
        返回:
            np.ndarray: 概率数组，与 values 对应。
        """
        return self.probabilities.copy()
    
    def generate_matrix(self, shape, dtype=None, random_state=None):
        """
        生成满足该概率分布的矩阵。
        
        参数:
            shape (tuple or int): 矩阵的形状。如果是整数，则生成一维数组。
            dtype: 输出数组的数据类型。如果为 None，则根据 values 的类型自动推断。
            random_state: 随机数生成器的种子或状态。可以是：
                - None: 使用全局随机数生成器
                - int: 作为种子创建新的随机数生成器
                - np.random.Generator: 使用指定的生成器
        
        返回:
            np.ndarray: 满足概率分布的矩阵。
        
        示例:
            dist = ProbabilityDistribution({-1: 0.25, 0: 0.5, 1: 0.25})
            matrix = dist.generate_matrix((10, 10))  # 生成 10x10 的矩阵
            matrix = dist.generate_matrix(100)      # 生成长度为 100 的一维数组
        """
        # 处理 shape 参数
        if isinstance(shape, int):
            shape = (shape,)
        elif not isinstance(shape, tuple):
            raise TypeError(f"shape 必须是 int 或 tuple，但收到了 {type(shape)}")
        
        # 确定数据类型
        if dtype is None:
            # 根据 values 的类型自动推断
            if np.issubdtype(self.values.dtype, np.integer):
                dtype = self.values.dtype
            else:
                dtype = self.values.dtype
        
        # 处理随机数生成器
        if random_state is None:
            rng = np.random.default_rng()
        elif isinstance(random_state, int):
            rng = np.random.default_rng(random_state)
        elif isinstance(random_state, np.random.Generator):
            rng = random_state
        else:
            raise TypeError(f"random_state 必须是 None、int 或 np.random.Generator，但收到了 {type(random_state)}")
        
        # 计算总元素数
        total_elements = np.prod(shape)
        
        # 使用 numpy 的 choice 函数根据概率分布生成随机数
        # 注意：numpy.random.choice 需要概率数组，且概率总和必须为1
        generated_values = rng.choice(
            self.values,
            size=total_elements,
            p=self.probabilities
        )
        
        # 重塑为指定形状
        matrix = generated_values.reshape(shape).astype(dtype)
        
        return matrix
    
    