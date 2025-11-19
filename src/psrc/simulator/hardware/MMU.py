from __future__ import annotations
from typing import List, Any, Optional, Generator
from core import Simulator, HwModule, Delay, Task
from utils.matrix_processing import create_transrow_tasks_from_matrix
from utils.data import MatrixSlice
import numpy as np

# 导入累加器缓存模块
try:
    from .accumulator_cache import AccumulatorCache
except ImportError:
    # 如果导入失败，可能是路径问题，尝试直接导入
    import sys
    import os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from accumulator_cache import AccumulatorCache

class Engine(HwModule):
    def __init__(self, name: str, sim: Simulator,
                    data_simulate_enable = False,
                    accumulator_strategy = "double_registers",
                    bank_ram_latency = 1,
                    sparse_enable = True,
                    num_cache_registers = 4,  # 缓存寄存器数量
                    parent: Optional[HwModule] = None):
        super().__init__(name, sim, parent)
        self.data_simulate_enable = data_simulate_enable
        self.nbar = 12
        self.mbar = 12

        self.accumulator_strategy = accumulator_strategy
        self.bank_ram_latency = bank_ram_latency
        self.sparse_enable = sparse_enable
        self.num_cache_registers = num_cache_registers if num_cache_registers is not None else 4

        #self._register_stat("total_cycles_busy",0)
        self._register_stat("total_latency_calculated", 0)
        self._register_stat("cache_replace_count", 0)
        self._register_stat("cache_memory_access_count", 0)

    def slice(self,matrix,S_bits=5):
        return MatrixSlice(create_transrow_tasks_from_matrix(matrix,S_bits))

    def _fifo_latency(self,fifo_list):
        max_latency = 0
        for fifo in fifo_list:
            if fifo.num_rows > max_latency:
                max_latency = fifo.num_rows
        return max_latency + 1

    def fifo(self,matrix_slice,S_bits=5):
        fifo_list = []
        fifo_0 = []
        fifo_1 = []
        fifo_2 = []
        fifo_3 = []
        fifo_4 = []
        fifo_list.append(fifo_0)
        fifo_list.append(fifo_1)
        fifo_list.append(fifo_2)
        fifo_list.append(fifo_3)
        fifo_list.append(fifo_4)
        if S_bits == 5:
            if matrix_slice.num_rows%5 != 0:
                raise ValueError("slice矩阵行数不是5的倍数")
            for i in range(matrix_slice.num_rows//5):
                for j in range(5):
                    if self.sparse_enable:
                        if matrix_slice.trans_rows[i*5+j].popcount != 0:
                            fifo_list[j].append(matrix_slice.trans_rows[i*5+j])
                    else:
                        fifo_list[j].append(matrix_slice.trans_rows[i*5+j])
            for i in range(5):
                fifo_list[i] = MatrixSlice(fifo_list[i])
                # print("fifo_",i,fifo_list[i].num_rows)
            return fifo_list
        elif S_bits == 2:
            if matrix_slice.num_rows%2 != 0:
                raise ValueError("slice矩阵行数不是2的倍数")
            for i in range(matrix_slice.num_rows//2):
                for j in range(2):
                    if self.sparse_enable:
                        if matrix_slice.trans_rows[i*2+j].popcount != 0:
                            fifo_list[i%2+j].append(matrix_slice.trans_rows[i*2+j])
                    else:
                        fifo_list[i%2+j].append(matrix_slice.trans_rows[i*2+j])
            for i in range(5):
                fifo_list[i] = MatrixSlice(fifo_list[i])
            return fifo_list
        else:
            raise ValueError("S_bits只能是2或5")
    
    def _caculate_latency_double_registers(self,fifo_list,S_bits=5):
        #双寄存器结构
        latency = 0
        if S_bits == 5:
            row_nums = [0]*5
            for i in range(5):
                row_nums[i] = fifo_list[i].num_rows
            cnt = 0
            while max(row_nums) > 0:
                latency += 1
                lane0 = cnt%5
                lane1 = (cnt+1)%5
                if row_nums[lane0] > 0:
                    row_nums[lane0] -= 1
                if row_nums[lane1] > 0:
                    row_nums[lane1] -= 1
                cnt += 1
            return latency
        elif S_bits == 2:
            row_nums = [0]*4
            for i in range(4):
                row_nums[i] = fifo_list[i].num_rows
            cnt = 0
            while max(row_nums) > 0:
                latency += 1
                lane0 = cnt%4
                lane1 = (cnt+1)%4
                if row_nums[lane0] > 0:
                    row_nums[lane0] -= 1
                if row_nums[lane1] > 0:
                    row_nums[lane1] -= 1
                cnt += 1
        else:
            raise ValueError("S_bits只能是2或5")
        return latency
    
    def _caculate_latency_no_fifo(self,matrix_slice,S_bits=5):
        #无fifo默认不使用稀疏
        num_rows = matrix_slice.num_rows
        if S_bits == 5:
            latency = num_rows//5
        elif S_bits == 2:
            latency = num_rows//4
        else:
            raise ValueError("S_bits只能是2或5")
        
        latency += 2 #加法树两级延迟

        return latency


    def _caculate_latency_cache_registers(self, fifo_list, S_bits=5):
        """
        计算使用缓存寄存器策略的延迟。
        需要考虑寄存器替换和内存访问的延迟。
        """
        # 基础延迟：FIFO处理延迟
        base_latency = self._caculate_latency_double_registers(fifo_list, S_bits)
        
        # 估算替换次数和内存访问次数
        # 这里简化处理，实际应该根据数据流分析
        # 假设每个bit_level可能有替换操作
        estimated_replacements = 0
        if self.sparse_enable:
            # 稀疏情况下，替换更复杂，可能需要更多内存访问
            # 简化：假设每个FIFO可能有1-2次替换
            estimated_replacements = len(fifo_list) * 1
        else:
            # 无稀疏：替换次数较少
            estimated_replacements = len(fifo_list) // 2
        
        # 每次替换需要内存访问延迟
        memory_latency = estimated_replacements * self.bank_ram_latency
        
        return base_latency + memory_latency + 1  # +1 for FIFO latency
    
    def _caculate_latency(self,fifo_list,matrix_slice,S_bits=5):
        if self.accumulator_strategy == "double_registers":
            return self._caculate_latency_double_registers(fifo_list,S_bits) + 1 #fifo latency为1
        elif self.accumulator_strategy == "bank_ram":
            return self._caculate_latency_double_registers(fifo_list,S_bits) + self.bank_ram_latency + 1 #fifo latency为1
        elif self.accumulator_strategy == "no_fifo":
            return self._caculate_latency_no_fifo(matrix_slice,S_bits)
        elif self.accumulator_strategy == "cache_registers":
            return self._caculate_latency_cache_registers(fifo_list, S_bits)
        else:
            raise ValueError("accumulator_strategy只能是double_registers,bank_ram,no_fifo,cache_registers")

    def _caculate(self,fifo_list,weights_matrix,S_bits=5):
        #左乘时，4个PE处理4行不同的数据
        #4*4 4*nbar
        #右乘只需要软件上将A转置输入(对单个engine)
        #累加策略只影响latency
        if weights_matrix.shape[0] != 4:
            raise ValueError("weights_matrix行数不是4")
        
        # 如果使用缓存寄存器策略
        if self.accumulator_strategy == "cache_registers":
            return self._caculate_with_cache(fifo_list, weights_matrix, S_bits)
        
        # 原有策略
        accumulator = np.zeros((4,self.nbar))
        if self.data_simulate_enable:
            for fifo in fifo_list:
                for row in fifo.trans_rows:
                    index = row.target_accumulator
                    for i in range(4):
                        #4个不同的PE
                        #print("row.binary_data",row.binary_data)
                        for j in range(4):
                            if row.binary_data[j]: # W_binary[s,n,k] == 1
                                shift_amount = row.shift_amount # bit_level 's'
                                # 检查是否为 MSB (最高有效位)
                                is_msb = (shift_amount == (S_bits - 1)) # S_bits=5, MSB=4
                                # 获取 A_in[i, k] 的值 (假设A_in全为正数，如您所测)
                                input_val = weights_matrix[i][j]
                                if is_msb:
                                    # MSB 对应的部分和必须被减去
                                    accumulator[i][index] -= (input_val << shift_amount)
                                else:
                                    # 其他位对应的部分和是加上
                                    accumulator[i][index] += (input_val << shift_amount)
        #latency = self._caculate_latency(fifo_list,S_bits)
        return accumulator
    
    def _caculate_with_cache(self, fifo_list, weights_matrix, S_bits=5):
        """
        使用缓存寄存器策略进行计算。
        每个PE维护一个独立的缓存，每个缓存只存储单个通道的累加值。
        """
        # 为每个PE创建独立的缓存（每个PE有多个通道，但缓存只存储部分通道）
        caches = [AccumulatorCache(
            num_registers=self.num_cache_registers,
            S_bits=S_bits,
            sparse_enable=self.sparse_enable
        ) for _ in range(4)]
        
        # 按bit_level顺序处理（从高到低，即从MSB到LSB）
        # FIFO列表按bit_level排序：fifo_list[0]是最高bit_level，fifo_list[S_bits-1]是最低
        for bit_level in range(S_bits - 1, -1, -1):  # 从S_bits-1到0
            fifo_idx = S_bits - 1 - bit_level  # 对应FIFO索引
            if fifo_idx >= len(fifo_list):
                continue
            
            fifo = fifo_list[fifo_idx]
            for row in fifo.trans_rows:
                target_acc = row.target_accumulator
                
                for pe_idx in range(4):  # 4个PE
                    cache = caches[pe_idx]
                    
                    # 获取或分配寄存器（可能需要替换）
                    # 在分配前，检查是否需要替换已完成的通道
                    reg_idx, acc_value = cache.get_or_allocate(
                        target_acc, pe_idx,
                        current_bit_level=bit_level,
                        initial_value=None  # 首次分配时初始化为0
                    )
                    
                    # 执行计算
                    if self.data_simulate_enable:
                        for j in range(4):
                            if row.binary_data[j]:  # W_binary[s,n,k] == 1
                                shift_amount = row.shift_amount
                                is_msb = (shift_amount == (S_bits - 1))
                                input_val = weights_matrix[pe_idx][j]
                                
                                if is_msb:
                                    acc_value -= (input_val << shift_amount)
                                else:
                                    acc_value += (input_val << shift_amount)
                    
                    # 更新寄存器中的值
                    target_acc_cached, _, progress = cache.registers[reg_idx]
                    cache.registers[reg_idx] = (target_acc_cached, acc_value, progress)
                    
                    # 更新进度
                    cache.update_progress(reg_idx, bit_level)
            
            # 处理完当前bit_level后，检查并替换已完成的通道
            for pe_idx in range(4):
                cache = caches[pe_idx]
                # 检查所有寄存器，替换已完成的通道
                for reg_idx in range(cache.num_registers):
                    if cache.registers[reg_idx] is not None:
                        target_acc, acc_value, progress = cache.registers[reg_idx]
                        if cache._is_channel_complete(progress, bit_level):
                            # 该通道已完成，写回内存
                            cache._evict_register(reg_idx)
        
        # 收集所有结果
        accumulator = np.zeros((4, self.nbar))
        for pe_idx in range(4):
            results = caches[pe_idx].flush_all()
            for target_acc, acc_value in results.items():
                if target_acc < self.nbar:
                    accumulator[pe_idx, target_acc] = acc_value
        
        # 更新统计信息
        total_replace = sum(cache.replace_count for cache in caches)
        total_memory_access = sum(cache.memory_access_count for cache in caches)
        self._increment_stat("cache_replace_count", total_replace)
        self._increment_stat("cache_memory_access_count", total_memory_access)
        
        return accumulator
        
    def execute_left(self,S_matrix,A_matrix,S_bits=5):
        
        if self.busy:
            raise ValueError("Engine正在繁忙")
            return None,None

        self._set_busy()

        #左乘
        #4*m m*nbar
        if S_matrix.shape[1] != self.nbar & S_matrix.shape[1] != 8:
            raise ValueError("S_matrix列数不满足要求")
        if S_matrix.shape[0] % 4 != 0:
            raise ValueError("S_matrix行数不是4的倍数")
        if A_matrix.shape[1] != S_matrix.shape[0]:
            raise ValueError("A_matrix列数不等于S_matrix行数")
        if A_matrix.shape[0] != 4:
            raise ValueError("A_matrix行数不是4")
        if S_bits != 5 and S_bits != 2:
            raise ValueError("S_bits只能是2或5")
        
        #暂时不考虑fifo堵塞的情况
        #latency实际上就是caculate_latency+常数
        latency = 0
        result_matrix = np.zeros((4,S_matrix.shape[1]))
        #print("S_matrix",S_matrix)
        for i in range(S_matrix.shape[0]//4):
            S_slice = S_matrix[i*4:(i+1)*4,:].T
            #print("S_slice",S_slice)
            S_slice = self.slice(S_slice,S_bits)
            fifo_list = self.fifo(S_slice,S_bits)
            accumulator = self._caculate(fifo_list,A_matrix[:,i*4:(i+1)*4],S_bits)
            caculate_latency = self._caculate_latency(fifo_list,S_slice,S_bits)
            result_matrix += accumulator[:,0:S_matrix.shape[1]]
            latency += caculate_latency
            latency += 2 #假设slice latency为1,更新A需要1
        
        self._increment_stat("total_latency_calculated", latency)
        yield self.sim.delay(latency)
        self._set_idle()

        return result_matrix,latency

    def execute_right(self,S_matrix,A_matrix,S_bits=5):
        if self.busy:
            raise ValueError("Engine正在繁忙")
            return None,None
        self._set_busy()

        #右乘
        #mbar*4 4*n
        if S_matrix.shape[0] != self.nbar & S_matrix.shape[0] != 8:
            raise ValueError("S_matrix行数不满足要求")
        if S_matrix.shape[1] != 4:
            raise ValueError("S_matrix列数不是4")
        if A_matrix.shape[0] != S_matrix.shape[1]:
            raise ValueError("A_matrix行数不等于S_matrix列数")
        if A_matrix.shape[0] != 4:
            raise ValueError("A_matrix行数不是4")
        if S_bits != 5 and S_bits != 2:
            raise ValueError("S_bits只能是2或5")

        #暂时不考虑fifo堵塞的情况
        #latency实际上就是caculate_latency+常数
        latency = 0
        result_matrix = np.zeros((S_matrix.shape[0],A_matrix.shape[1])).T
        #print("S_matrix",S_matrix)
        for i in range(A_matrix.shape[1]//4):
            #print("S_slice",S_slice)
            S_slice = self.slice(S_matrix,S_bits)
            fifo_list = self.fifo(S_slice,S_bits)
            accumulator = self._caculate(fifo_list,A_matrix[:,i*4:(i+1)*4].T,S_bits)
            caculate_latency = self._caculate_latency(fifo_list,S_slice,S_bits)
            result_matrix[i*4:(i+1)*4,:]= accumulator[:,0:S_matrix.shape[0]]
            latency += caculate_latency
            latency += 2 #假设slice latency为1,更新A需要1
        result_matrix = result_matrix.T
        yield self.sim.delay(latency)
       
        self._increment_stat("total_latency_calculated", latency)
        #self._increment_stat("total_busy_cycles", latency)

        self._set_idle()

        return result_matrix,latency

    
class MMU(HwModule):
    def __init__(self, name: str, sim: Simulator,
                 n_engines = 4,
                 data_simulate_enable = True,
                 accumulator_strategy = "double_registers",
                 bank_ram_latency = 1,
                 sparse_enable = True,
                 num_cache_registers = 4,
                parent: Optional[HwModule] = None):
        super().__init__(name, sim, parent)
        self.n_engines = n_engines
        self.num_cache_registers = num_cache_registers
        self.engines = []
        for i in range(n_engines):
            self.engines.append(
                Engine(
                    name=f"engine_{i}",
                    sim=sim,
                    data_simulate_enable=data_simulate_enable,
                    accumulator_strategy=accumulator_strategy,
                    bank_ram_latency=bank_ram_latency,
                    sparse_enable=sparse_enable,
                    num_cache_registers=num_cache_registers,
                    parent=self
                )
            )
        
    def execute_left(self, S_matrix, A_matrix, S_bits=5):
        #左乘
        #4*n n*nbar
        #将n拆成n_engines组分给每个engine，之后再相加
        #考虑到这是最上层，因此我们不做整除判断，不整除的需要补0,虽然实际中并不会遇到
        #软件这里分组随便分了
        if S_matrix.shape[0] != A_matrix.shape[1]:
            raise ValueError("S_matrix行数不等于A_matrix列数")
        if A_matrix.shape[0] != 4:
            raise ValueError("A_matrix行数不是4")
        if S_bits != 5 and S_bits != 2:
            raise ValueError("S_bits只能是2或5")
        if self.busy:
            raise ValueError("MMU正在繁忙")
            return None, None
        self._set_busy()

        n = S_matrix.shape[0]  # S的行数，也是A的列数
        nbar = S_matrix.shape[1]  # S的列数
        
        # 计算每个engine分配的列数（n'）
        base_n_per_engine = n // self.n_engines
        remainder = n % self.n_engines
        
        # 分配任务给每个engine
        tasks = []
        result_matrix = np.zeros((4, nbar))
        max_latency = 0
        
        start_idx = 0
        for i in range(self.n_engines):
            # 计算当前engine分配的列数
            n_per_engine = base_n_per_engine + (1 if i < remainder else 0)
            end_idx = start_idx + n_per_engine
            
            # 提取当前engine的A和S切片
            A_slice = A_matrix[:, start_idx:end_idx]  # 4 * n'
            S_slice = S_matrix[start_idx:end_idx, :]  # n' * nbar
            
            # 如果n'不是4的倍数，需要补0
            if n_per_engine % 4 != 0:
                padding_size = 4 - (n_per_engine % 4)
                # A补列：4 * (n' + padding)
                A_slice = np.pad(A_slice, ((0, 0), (0, padding_size)), mode='constant', constant_values=0)
                # S补行：(n' + padding) * nbar
                S_slice = np.pad(S_slice, ((0, padding_size), (0, 0)), mode='constant', constant_values=0)
            
            # 启动engine任务
            task = self.sim.spawn(self.engines[i].execute_left, S_slice, A_slice, S_bits)
            tasks.append(task)
            
            start_idx = end_idx
        
        # 等待所有任务完成（通过yield等待所有任务）
        # yield tasks 会返回一个列表，包含所有任务的结果
        task_results = yield tasks
        
        # 收集所有engine的结果并累加
        for engine_result, engine_latency in task_results:
            result_matrix += engine_result
            max_latency = max(max_latency, engine_latency)
        
        self._set_idle()
        return result_matrix, max_latency

    
    def execute_right(self, S_matrix, A_matrix, S_bits=5):
        #右乘
        #mbar*4 4*n
        #将n拆成n_engines组分给每个engine，之后再相加
        #考虑到这是最上层，因此我们不做整除判断，不整除的需要补0,虽然实际中并不会遇到
        #软件这里分组随便分了
        if S_matrix.shape[1] != A_matrix.shape[0]:
            raise ValueError("S_matrix列数不等于A_matrix行数")
        if A_matrix.shape[0] != 4:
            raise ValueError("A_matrix行数不是4")
        if S_bits != 5 and S_bits != 2:
            raise ValueError("S_bits只能是2或5")
        if self.busy:
            raise ValueError("MMU正在繁忙")
            return None,None
        self._set_busy()

        mbar = S_matrix.shape[0]  # S的行数
        n = A_matrix.shape[1]  # A的列数
        
        # 计算每个engine分配的列数（n'）
        base_n_per_engine = n // self.n_engines
        remainder = n % self.n_engines
        
        # 分配任务给每个engine
        tasks = []
        result_parts = []  # 存储每个engine的结果部分
        max_latency = 0
        
        start_idx = 0
        for i in range(self.n_engines):
            # 计算当前engine分配的列数
            n_per_engine = base_n_per_engine + (1 if i < remainder else 0)
            end_idx = start_idx + n_per_engine
            
            # 提取当前engine的A切片
            A_slice = A_matrix[:, start_idx:end_idx]  # 4 × n'
            
            # 如果n'不是4的倍数，需要补0
            if n_per_engine % 4 != 0:
                padding_size = 4 - (n_per_engine % 4)
                # A补列：4 × (n' + padding)
                A_slice = np.pad(A_slice, ((0, 0), (0, padding_size)), mode='constant', constant_values=0)
            
            # S不需要切分，所有engine共用同一个S
            # 启动engine任务
            task = self.sim.spawn(self.engines[i].execute_right, S_matrix, A_slice, S_bits)
            tasks.append(task)
            
            start_idx = end_idx
        
        # 等待所有任务完成（通过yield等待所有任务）
        # yield tasks 会返回一个列表，包含所有任务的结果
        task_results = yield tasks
        
        # 收集所有engine的结果并按列拼接
        for i, (engine_result, engine_latency) in enumerate(task_results):
            # 计算当前engine实际应该返回的列数（去除补0的部分）
            n_per_engine = base_n_per_engine + (1 if i < remainder else 0)
            # 只取实际列数，去除补0的部分
            actual_result = engine_result[:, :n_per_engine]
            result_parts.append(actual_result)
            max_latency = max(max_latency, engine_latency)
        
        # 按列拼接所有结果
        result_matrix = np.hstack(result_parts)  # mbar × n
        
        self._set_idle()
        return result_matrix, max_latency

    def configure(self, config: dict):
        """
        通过字典配置MMU及其内部所有engine的参数。
        
        参数:
            config: 配置字典，可包含以下键：
                - n_engines: engine数量（如果改变，会重新创建engines）
                - data_simulate_enable: 数据模拟使能
                - accumulator_strategy: 累加器策略 ("double_registers", "bank_ram", "no_fifo", "cache_registers")
                - bank_ram_latency: bank RAM延迟
                - sparse_enable: 稀疏使能
                - num_cache_registers: 缓存寄存器数量
                - nbar: Engine的nbar参数（默认12）
                - mbar: Engine的mbar参数（默认12）
        """
        # 先更新MMU级别的通用参数
        if 'num_cache_registers' in config:
            self.num_cache_registers = config['num_cache_registers']

        # 更新MMU自身的参数
        if 'n_engines' in config:
            new_n_engines = config['n_engines']
            if new_n_engines != self.n_engines:
                # 如果engine数量改变，需要重新创建engines列表
                self.n_engines = new_n_engines
                # 获取当前engine的配置参数（用于新创建的engines）
                data_simulate_enable = config.get('data_simulate_enable', 
                                                  self.engines[0].data_simulate_enable if self.engines else True)
                accumulator_strategy = config.get('accumulator_strategy',
                                                 self.engines[0].accumulator_strategy if self.engines else "double_registers")
                bank_ram_latency = config.get('bank_ram_latency',
                                              self.engines[0].bank_ram_latency if self.engines else 1)
                sparse_enable = config.get('sparse_enable',
                                          self.engines[0].sparse_enable if self.engines else True)
                num_cache_registers = config.get('num_cache_registers',
                                                 self.num_cache_registers if self.engines else 4)
                
                # 重新创建engines列表
                self.engines = []
                for i in range(self.n_engines):
                    engine = Engine(
                        name=f"engine_{i}",
                        sim=self.sim,
                        data_simulate_enable=data_simulate_enable,
                        accumulator_strategy=accumulator_strategy,
                        bank_ram_latency=bank_ram_latency,
                        sparse_enable=sparse_enable,
                        num_cache_registers=num_cache_registers,
                        parent=self
                    )
                    # 如果配置中有nbar或mbar，也设置它们
                    if 'nbar' in config:
                        engine.nbar = config['nbar']
                    if 'mbar' in config:
                        engine.mbar = config['mbar']
                    self.engines.append(engine)
                return  # 如果重新创建了engines，直接返回，因为已经应用了所有配置
        
        # 更新现有engines的参数
        for engine in self.engines:
            if 'data_simulate_enable' in config:
                engine.data_simulate_enable = config['data_simulate_enable']
            if 'accumulator_strategy' in config:
                engine.accumulator_strategy = config['accumulator_strategy']
            if 'bank_ram_latency' in config:
                engine.bank_ram_latency = config['bank_ram_latency']
            if 'sparse_enable' in config:
                engine.sparse_enable = config['sparse_enable']
            if 'num_cache_registers' in config:
                engine.num_cache_registers = config['num_cache_registers']
            if 'nbar' in config:
                engine.nbar = config['nbar']
            if 'mbar' in config:
                engine.mbar = config['mbar']


        
    
        


        




    


        
        