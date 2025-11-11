from __future__ import annotations
from typing import List, Any, Optional, Generator
from core import Simulator, HwModule, Delay, Task
from utils.matrix_processing import create_transrow_tasks_from_matrix
from utils.data import MatrixSlice
import numpy as np

class Engine(HwModule):
    def __init__(self, name: str, sim: Simulator,
                    parent: Optional[HwModule] = None):
        super().__init__(name, sim, parent)

    def slice(self,matrix,S_bits):
        return MatrixSlice(create_transrow_tasks_from_matrix(matrix,S_bits))





    


        
        