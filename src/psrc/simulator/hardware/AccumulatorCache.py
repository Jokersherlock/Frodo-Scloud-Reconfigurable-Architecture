from __future__ import annotations
from typing import List, Any, Optional, Generator
from core import Simulator, HwModule, Delay, Task
from utils.matrix_processing import create_transrow_tasks_from_matrix
from utils.data import MatrixSlice
import numpy as np



class AccumulatorRegister:
    def __init__(self,target_accumulator=0):
        self.data = 0
        self.counter = 0
        self.target_accumulator = target_accumulator



class AccumulatorCache(HwModule):
    def __init__(self, name: str, sim: Simulator,
                 n_engines = 4,
                 register_num = 4,
                 data_simulate_enable = True,
                 #sparse_enable = True,
                 parent: Optional[HwModule] = None):
        super().__init__(name, sim, parent)

        self.n_engines = n_engines
        self.register_num = register_num


    #先写一个测试的
    #Scloud进行稀疏操作
    def _single_pe_cache_Sbits_2(self,fifo_list,weights_matrix,output_channel=8):
        registers = [AccumulatorRegister() for _ in range(self.register_num)]

        for i in range(self.register_num):
            registers[i].target_accumulator = i
        #register_next = registers.copy()
        
        accumulators = [0]*output_channel
        
        row_nums = [0]*self.register_num
        for i in range(self.register_num):
            row_nums[i] = fifo_list[i].num_rows
        
        print('row_nums',row_nums)
        cnt = 0
        latency = 0
        ptr = self.register_num
        #not_equal = 0
        while max(row_nums) > 0:
            latency += 1
            lane0 = cnt%4
            lane1 = (cnt+1)%4
            cnt += 2
            lane0_en = False
            lane1_en = False
            if row_nums[lane0] > 0:
                lane0_en = True
                lane0_row = fifo_list[lane0][fifo_list[lane0].num_rows-row_nums[lane0]]
                row_nums[lane0] -= 1
            if row_nums[lane1] > 0:
                lane1_en = True
                lane1_row = fifo_list[lane1][fifo_list[lane1].num_rows-row_nums[lane1]]
                row_nums[lane1] -= 1
           
            print('lane0_en,lane1_en',lane0_en,lane1_en)
           #都有数据
        #    if lane0_en and lane1_en:
        #        if lane0_row.target_accumulator != lane1_row.target_accumulator:
        #            not_equal += 1

            #每次替换1个
            if lane0_en and lane1_en:
                lane0_cache_miss = True
                lane1_cache_miss = True
                for i in range(self.register_num):
                    if registers[i].target_accumulator == lane0_row.target_accumulator:
                        lane0_cache_miss = False
                        lane0_register = i
                    if registers[i].target_accumulator == lane1_row.target_accumulator:
                        lane1_cache_miss = False
                        lane1_register = i
                print(lane0_row.target_accumulator,lane1_row.target_accumulator)
                
                if lane0_cache_miss or lane1_cache_miss:
                    print("cache miss") 
                else:
                    # registers[lane0_register].data += lane0_row.data
                    # registers[lane1_register].data += lane1_row.data

                    #替换
                    if lane0_row.target_accumulator <= lane1_row.target_accumulator:
                        # accumulators[registers[lane0_register].target_accumulator] = registers[lane0_register].data
                        # registers[lane0_register].data = accumulators[ptr]
                        registers[lane0_register].target_accumulator = ptr
                        ptr = (ptr+1)%output_channel
                    else:
                        # accumulators[registers[lane1_register].target_accumulator] = registers[lane1_register].data
                        # registers[lane1_register].data = accumulators[ptr]
                        registers[lane1_register].target_accumulator = ptr
                        ptr = (ptr+1)%output_channel
            elif lane0_en:
                    lane0_cache_miss = True
                    for i in range(self.register_num):
                        if registers[i].target_accumulator == lane0_row.target_accumulator:
                            lane0_cache_miss = False
                            lane0_register = i
                    print(lane0_row.target_accumulator)
                    if lane0_cache_miss:
                        print("cache miss")
                    else:
                        # registers[lane0_register].data += lane0_row.data
                        # accumulators[registers[lane0_register].target_accumulator] = registers[lane0_register].data
                        registers[lane0_register].data = accumulators[ptr]
                        registers[lane0_register].target_accumulator = ptr
                        ptr = (ptr+1)%output_channel
            elif lane1_en:
                    lane1_cache_miss = True
                    for i in range(self.register_num):
                        if registers[i].target_accumulator == lane1_row.target_accumulator:
                            lane1_cache_miss = False
                            lane1_register = i
                    print(lane1_row.target_accumulator)
                    if lane1_cache_miss:
                        print("cache miss")
                    else:
                        # registers[lane1_register].data += lane1_row.data
                        # accumulators[registers[lane1_register].target_accumulator] = registers[lane1_register].data
                        registers[lane1_register].data = accumulators[ptr]
                        registers[lane1_register].target_accumulator = ptr
                        ptr = (ptr+1)%output_channel

        return
