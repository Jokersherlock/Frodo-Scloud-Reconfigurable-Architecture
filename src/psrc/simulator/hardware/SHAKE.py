from __future__ import annotations
from typing import List, Any, Optional, Generator
from core import Simulator, HwModule, Delay, Task
from utils.matrix_processing import create_transrow_tasks_from_matrix
from utils.data import MatrixSlice
import hashlib
import numpy as np

class SHAKE(HwModule):
    def __init__(self, name: str, sim: Simulator,
                 keccak_latency: int = 24,
                 padding_latency: int = 3,
                 data_simulate_enable: bool = False,
                 input_width: int = 64,
                 output_width: int = 64,
                 parent: Optional[HwModule] = None):
        super().__init__(name, sim, parent)
        
        self.keccak_latency = keccak_latency
        self.padding_latency = padding_latency
        self.data_simulate_enable = data_simulate_enable
        self.shake = "SHAKE-256"
        self.input_width = input_width//8 #输入宽度，单位为字节
        self.output_width = output_width//8 #输出宽度，单位为字节

        self._register_stat("total_latency_calculated", 0)


    def _shake128(self,data,output_len):
        if self.data_simulate_enable:
            if isinstance(data, str):
                data = data.encode('utf-8')
            return hashlib.shake_128(data).digest(output_len)
        else:
            return 0
    
    def _shake256(self,data,output_len):
        if self.data_simulate_enable:
            if isinstance(data, str):
                data = data.encode('utf-8')
            return hashlib.shake_256(data).digest(output_len)
        else:
            return 0

    def _shake(self,data,output_len):
        if self.shake == "SHAKE-128":
            return self._shake128(data,output_len)
        elif self.shake == "SHAKE-256":
            return self._shake256(data,output_len)
        else:
            raise ValueError("shake只能是SHAKE-128或SHAKE-256")

    #只关心keccak的latency，输入输出的latency不在这里反映
    def _shake128_absorb_latency(self,data):
        len = len(data)
        if len % 8 != 0:
            raise ValueError("data长度不是8的倍数")
        len = len * 8
        if len < 1344:
            return  self.padding_latency + self.keccak_latency #填充需要3个周期
        else:
            round = len//1344
            latency = round * self.keccak_latency
            rest = len % 1344
            if rest != 0:
                latency += self.keccak_latency + self.padding_latency
            return latency
    
    def _shake256_absorb_latency(self,data):
        len = len(data)
        if len % 8 != 0:
            raise ValueError("data长度不是8的倍数")
        len = len * 8
        if len < 1088:
            return self.padding_latency + self.keccak_latency #填充需要3个周期
        else:
            round = len//1088
            latency = round * self.keccak_latency
            rest = len % 1088
            if rest != 0:
                latency += self.keccak_latency + self.padding_latency
            return latency

    
    def _shake128_squeeze_latency(self,output_len):
        if output_len % 8 != 0:
            raise ValueError("output_len不是8的倍数")
        output_len = output_len * 8
        if output_len <= 1344:
            return 0
        else:
            round = output_len//1344 - 1 #第一轮不需要squeeze
            latency = round * self.keccak_latency
            rest = output_len % 1344
            if rest != 0:
                latency += self.keccak_latency
            return latency
    
    def _shake256_squeeze_latency(self,output_len):
        if output_len % 8 != 0:
            raise ValueError("output_len不是8的倍数")
        output_len = output_len * 8
        if output_len <= 1088:
            return 0
        else:
            round = output_len//1088 - 1 #第一轮不需要squeeze
            latency = round * self.keccak_latency
            rest = output_len % 1088
            if rest != 0:
                latency += self.keccak_latency
            return latency

    
    def _shake_latency(self,data,output_len):
        if self.shake == "SHAKE-128":
            return self._shake128_absorb_latency(data) + self._shake128_squeeze_latency(output_len)
        elif self.shake == "SHAKE-256":
            return self._shake256_absorb_latency(data) + self._shake256_squeeze_latency(output_len)
        else:
            raise ValueError("shake只能是SHAKE-128或SHAKE-256")

    def execute(self,data,output_len):
        if self.busy:
            raise ValueError("SHAKE正在繁忙")
            return None,None
        self._set_busy()
        latency = self._shake_latency(data,output_len)
        if self.data_simulate_enable:
            result = self._shake(data,output_len)
        else:
            result = 0
        yield self.sim.delay(latency)
        self._set_idle()

        return result,latency

        


    

            
