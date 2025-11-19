"""
累加器缓存替换策略模块

实现寄存器替换逻辑，减少累加器寄存器数量。
支持稀疏优化场景下的智能替换。
"""

from typing import Dict, Optional, Tuple, List
import numpy as np


class AccumulatorCache:
    """
    累加器缓存类，实现寄存器替换策略。
    
    核心思想：
    - 使用少量寄存器（如4个）存储多个输出通道的累加值
    - 当寄存器满时，选择"最不可能再被使用"的寄存器进行替换
    - 对于无稀疏情况：按bit_level计数，满S_bits即完成
    - 对于稀疏情况：跟踪每个通道已处理的bit_level集合
    """
    
    def __init__(self, num_registers: int = 4, S_bits: int = 5, sparse_enable: bool = True):
        """
        初始化累加器缓存。
        
        参数:
            num_registers: 寄存器数量（默认4个）
            S_bits: 位宽（Frodo=5, Scloud=2）
            sparse_enable: 是否启用稀疏优化
        """
        self.num_registers = num_registers
        self.S_bits = S_bits
        self.sparse_enable = sparse_enable
        
        # 寄存器池：每个寄存器存储 (target_accumulator_id, 累加值, bit_level进度)
        # bit_level进度：
        #   - 无稀疏：已处理的bit_level计数（0到S_bits）
        #   - 有稀疏：已处理的bit_level集合
        self.registers: List[Optional[Tuple[int, np.ndarray, any]]] = [None] * num_registers
        
        # 内存：存储被替换出去的累加值
        # key: target_accumulator_id, value: 累加值
        self.memory: Dict[int, np.ndarray] = {}
        
        # 统计信息
        self.replace_count = 0  # 替换次数
        self.memory_access_count = 0  # 内存访问次数
        
    def _is_register_available(self, reg_idx: int) -> bool:
        """检查寄存器是否可用（为空）"""
        return self.registers[reg_idx] is None
    
    def _find_available_register(self) -> Optional[int]:
        """查找可用的寄存器索引"""
        for i in range(self.num_registers):
            if self._is_register_available(i):
                return i
        return None
    
    def _get_register_by_target(self, target_acc: int) -> Optional[int]:
        """根据target_accumulator查找对应的寄存器索引"""
        for i in range(self.num_registers):
            if self.registers[i] is not None and self.registers[i][0] == target_acc:
                return i
        return None
    
    def _is_channel_complete(self, progress, current_bit_level: int) -> bool:
        """
        判断一个通道是否已经完成（不会再出现更小的bit_level）。
        
        参数:
            progress: 进度信息（计数或集合）
            current_bit_level: 当前处理的bit_level
        
        返回:
            True表示该通道已完成，可以安全替换
        """
        if not self.sparse_enable:
            # 无稀疏情况：如果进度计数 >= S_bits，说明已完成
            return progress >= self.S_bits
        else:
            # 有稀疏情况：如果当前bit_level是最小的，且该bit_level已处理过，说明完成
            # 更保守的策略：如果已处理过所有 >= current_bit_level 的bit_level，且current_bit_level是最小的可能值
            # 实际上，如果current_bit_level=0（LSB），且0已在progress中，说明完成
            if isinstance(progress, set):
                # 如果当前bit_level是最小的（0），且已在集合中，说明完成
                if current_bit_level == 0 and 0 in progress:
                    return True
                # 更保守：如果已处理过所有可能的bit_level（0到S_bits-1），说明完成
                if len(progress) == self.S_bits:
                    return True
            return False
    
    def _find_replacement_register(self, current_bit_level: int = -1) -> int:
        """
        查找最适合替换的寄存器。
        
        策略：
        1. 优先选择已完成（不会再被使用）的通道
        2. 如果都未完成，选择bit_level进度最小的（最接近完成）
        
        参数:
            current_bit_level: 当前处理的bit_level
        
        返回:
            寄存器索引
        """
        best_idx = 0
        best_score = float('inf')  # 分数越小越好（已完成 > 接近完成）
        
        for i in range(self.num_registers):
            if self.registers[i] is None:
                continue
            
            target_acc, acc_value, progress = self.registers[i]
            
            # 检查是否已完成
            if self._is_channel_complete(progress, current_bit_level):
                # 已完成的优先级最高（分数最小）
                return i
            
            # 计算"接近完成"的分数
            if not self.sparse_enable:
                # 无稀疏：进度计数越小，越接近完成
                score = progress
            else:
                # 有稀疏：已处理的bit_level数量越多，越接近完成
                # 但更关键的是：最小的未处理bit_level
                if isinstance(progress, set):
                    # 找到最小的未处理bit_level
                    processed_levels = sorted(progress)
                    if len(processed_levels) == 0:
                        score = self.S_bits  # 还没开始处理
                    else:
                        # 找到第一个"缺口"
                        for level in range(self.S_bits):
                            if level not in progress:
                                score = level
                                break
                        else:
                            score = self.S_bits  # 所有都处理过了
                else:
                    score = self.S_bits
            
            if score < best_score:
                best_score = score
                best_idx = i
        
        return best_idx
    
    def get_or_allocate(self, target_accumulator: int, pe_index: int,
                        current_bit_level: int = -1,
                        initial_value: Optional[np.int32] = None) -> Tuple[int, np.int32]:
        """
        获取或分配寄存器给指定的target_accumulator。
        
        参数:
            target_accumulator: 目标累加器ID（输出通道）
            pe_index: PE索引（用于累加值的维度，这里不使用但保留接口）
            initial_value: 初始值（如果从内存加载）
        
        返回:
            (寄存器索引, 累加值标量)
        """
        # 1. 检查是否已经在寄存器中
        reg_idx = self._get_register_by_target(target_accumulator)
        if reg_idx is not None:
            return reg_idx, self.registers[reg_idx][1]
        
        # 2. 检查内存中是否有
        if target_accumulator in self.memory:
            self.memory_access_count += 1
            acc_value = self.memory[target_accumulator]  # 标量，直接使用
            del self.memory[target_accumulator]
        elif initial_value is not None:
            acc_value = initial_value  # 标量，直接使用
        else:
            # 创建新的累加值（单个通道的累加值，是一个标量）
            acc_value = np.int32(0)
        
        # 3. 查找可用寄存器
        reg_idx = self._find_available_register()
        
        # 4. 如果没有可用寄存器，需要替换
        if reg_idx is None:
            # 尝试找到已完成的通道进行替换
            reg_idx = None
            for i in range(self.num_registers):
                if self.registers[i] is not None:
                    target_acc, acc_value, progress = self.registers[i]
                    # 检查是否已完成（保守策略：如果已处理过所有bit_level）
                    if not self.sparse_enable:
                        if progress >= self.S_bits:
                            reg_idx = i
                            break
                    else:
                        if isinstance(progress, set) and len(progress) == self.S_bits:
                            reg_idx = i
                            break
            
            # 如果没找到已完成的，选择最接近完成的
            if reg_idx is None:
                reg_idx = self._find_replacement_register(current_bit_level)
            
            self._evict_register(reg_idx)
            self.replace_count += 1
        
        # 5. 分配寄存器
        # 初始化进度：无稀疏用计数0，有稀疏用空集合
        if not self.sparse_enable:
            progress = 0
        else:
            progress = set()
        
        self.registers[reg_idx] = (target_accumulator, acc_value, progress)
        return reg_idx, acc_value
    
    def update_progress(self, reg_idx: int, bit_level: int):
        """
        更新寄存器的bit_level进度。
        
        参数:
            reg_idx: 寄存器索引
            bit_level: 刚处理完的bit_level
        """
        if self.registers[reg_idx] is None:
            return
        
        target_acc, acc_value, progress = self.registers[reg_idx]
        
        if not self.sparse_enable:
            # 无稀疏：简单计数+1
            progress = progress + 1
        else:
            # 有稀疏：添加到集合
            if isinstance(progress, set):
                progress.add(bit_level)
            else:
                progress = {bit_level}
        
        self.registers[reg_idx] = (target_acc, acc_value, progress)
    
    def _evict_register(self, reg_idx: int):
        """
        将寄存器内容写回内存并清空寄存器。
        
        参数:
            reg_idx: 寄存器索引
        """
        if self.registers[reg_idx] is None:
            return
        
        target_acc, acc_value, progress = self.registers[reg_idx]
        self.memory[target_acc] = acc_value  # 标量，不需要copy
        self.registers[reg_idx] = None
        self.memory_access_count += 1
    
    def flush_all(self) -> Dict[int, np.int32]:
        """
        将所有寄存器内容写回内存，返回所有累加值。
        
        返回:
            {target_accumulator_id: 累加值}
        """
        results = {}
        
        for i in range(self.num_registers):
            if self.registers[i] is not None:
                target_acc, acc_value, progress = self.registers[i]
                results[target_acc] = acc_value  # 标量，不需要copy
                self.memory[target_acc] = acc_value
                self.registers[i] = None
                self.memory_access_count += 1
        
        # 合并内存中的结果
        results.update(self.memory)
        self.memory.clear()
        
        return results
    
    def get_statistics(self) -> Dict[str, int]:
        """获取统计信息"""
        return {
            'replace_count': self.replace_count,
            'memory_access_count': self.memory_access_count,
            'current_registers_used': sum(1 for r in self.registers if r is not None),
            'memory_entries': len(self.memory)
        }

