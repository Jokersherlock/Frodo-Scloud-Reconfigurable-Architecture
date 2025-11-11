from __future__ import annotations
from typing import List, Any, Optional, Generator
from core import Simulator, HwModule, Delay, Task
from utils.matrix_processing import create_transrow_tasks_from_matrix
from utils.data import MatrixSlice
import numpy as np

class Engine(HwModule):
    def __init__(self, name: str, sim: Simulator,
                    data_simulate_enable = False,
                    accumulator_strategy = "double_registers",
                    bank_ram_latency = 1,
                    parent: Optional[HwModule] = None):
        super().__init__(name, sim, parent)
        self.data_simulate_enable = data_simulate_enable
        self.nbar = 12
        self.mbar = 12

        self.accumulator_strategy = accumulator_strategy
        self.bank_ram_latency = bank_ram_latency

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
                    if matrix_slice.trans_rows[i*5+j].popcount != 0:
                        fifo_list[j].append(matrix_slice.trans_rows[i*5+j])
            for i in range(5):
                fifo_list[i] = MatrixSlice(fifo_list[i])
                # print("fifo_",i,fifo_list[i].num_rows)
            return fifo_list
        elif S_bits == 2:
            if matrix_slice.num_rows%2 != 0:
                raise ValueError("slice矩阵行数不是2的倍数")
            for i in range(matrix_slice.num_rows//4):
                for j in range(4):
                    if matrix_slice.trans_rows[i*4+j].popcount != 0:
                       fifo_list[j].append(matrix_slice.trans_rows[i*2+j])
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
    def _caculate_latency(self,fifo_list,S_bits=5):
        if self.accumulator_strategy == "double_registers":
            return self._caculate_latency_double_registers(fifo_list,S_bits)
        elif self.accumulator_strategy == "bank_ram":
            return self._caculate_latency_single_register(fifo_list,S_bits) + self.bank_ram_latency
        else:
            raise ValueError("accumulator_strategy只能是double_registers,bank_ram")

    def _caculate(self,fifo_list,weights_matrix,S_bits=5):
        #左乘时，4个PE处理4行不同的数据
        #4*4 4*nbar
        #右乘只需要软件上将A转置输入(对单个engine)
        #累加策略只影响latency
        if weights_matrix.shape[0] != 4:
            raise ValueError("weights_matrix行数不是4")
        
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
        latency = self._caculate_latency(fifo_list,S_bits)
        return accumulator,latency
        
    def execute_left(self,S_matrix,A_matrix,S_bits=5):
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
        if S_bits != 5 & S_bits != 2:
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
            accumulator,caculate_latency = self._caculate(fifo_list,A_matrix[:,i*4:(i+1)*4],S_bits)
            result_matrix += accumulator[:,0:S_matrix.shape[1]]
            latency += caculate_latency
            latency += 2 #假设slice latency为1,fifo latency为1
        
        #yield self.sim.delay(latency)

        return result_matrix,latency
        
    
        


        




    


        
        