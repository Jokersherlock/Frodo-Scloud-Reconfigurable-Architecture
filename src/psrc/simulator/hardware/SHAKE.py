from __future__ import annotations
from typing import List, Any, Optional, Generator
from core import Simulator, HwModule, Delay, Task
from utils.matrix_processing import create_transrow_tasks_from_matrix
from utils.data import MatrixSlice
from cryptography.hazmat.primitives import hashes
import numpy as np

class SHAKE(HwModule):
    def __init__(self, name: str, sim: Simulator,
                 latency: int = 24,
                 data_simulate_enable: bool = False,
                 parent: Optional[HwModule] = None):
        super().__init__(name, sim, parent)
        
        self.latency = latency
        self.data_simulate_enable = data_simulate_enable

    def _shake128(self,data):
        if self.data_simulate_enable:
            
