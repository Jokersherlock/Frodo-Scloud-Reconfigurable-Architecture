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
    