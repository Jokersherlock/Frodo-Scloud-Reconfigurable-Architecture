from core import Simulator
from hardware.MMU import Engine
import numpy as np


if __name__ == "__main__":
    sim = Simulator()
    engine = Engine("engine",sim)
    matrix = np.array([[1,2,3,4],[4,5,6,7],[7,8,9,10]])
    S_bits = 5
    matrix_slice = engine.slice(matrix,S_bits)
    matrix_slice.visualize_matrix()
