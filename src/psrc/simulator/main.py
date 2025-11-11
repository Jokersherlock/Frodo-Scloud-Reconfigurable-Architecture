from core import Simulator
from hardware.MMU import Engine
import numpy as np


if __name__ == "__main__":
    sim = Simulator()
    engine = Engine("engine",sim,data_simulate_enable=True)
    n =1344
    S = np.random.randint(-7, 8, size=(n,8))
    ##print("S",S)
    #print("S.T",S.T)
    #S = np.array([[2],[0],[3],[-1]])
    S_bits = 5
    # matrix_slice = engine.slice(S.T,S_bits)
    #matrix_slice.visualize_matrix()
    #print(matrix_slice.numpy_array)
    # fifo_list = engine.fifo(matrix_slice,S_bits)
    A = np.random.randint(-7, 8, size=(4,n))
    #result_matrix,latency = engine._caculate(fifo_list,A.T,S_bits)
    #result_matrix = result_matrix[:,0:8]
    result_matrix,latency = engine.execute_left(S,A,S_bits)
    #ref_accumulator = np.matmul(A,S)
    ref_accumulator = np.matmul(A,S)
    print(ref_accumulator)
    print(result_matrix)
    print(ref_accumulator==result_matrix)
    print(latency)