from __future__ import annotations
from typing import List, Any, Optional, Generator
from core import Simulator, HwModule, Delay, Task
from utils.matrix_processing import create_transrow_tasks_from_matrix
from utils.data import MatrixSlice
import hashlib
import numpy as np

class SHAKE(HwModule):
    def __init__(self, name: str, sim: Simulator,
                 latency: int = 24,
                 data_simulate_enable: bool = False,
                 input_width: int = 64,
                 output_width: int = 64,
                 parent: Optional[HwModule] = None):
        super().__init__(name, sim, parent)
        
        self.latency = latency
        self.data_simulate_enable = data_simulate_enable
        self.shake = "SHAKE-256"
        self.input_width = input_width//8 #输入宽度，单位为字节
        self.output_width = output_width//8 #输出宽度，单位为字节

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

    def _shake128_absorb_latency(self,data):
        len = len(data)
        
            
