from core import Simulator
from hardware.MMU import Engine
import numpy as np


if __name__ == "__main__":
    sim = Simulator()
    engine = Engine("engine",sim,data_simulate_enable=True)
    n =int(1344/4)
    S = np.random.randint(-1, 2, size=(n,8))
    A = np.random.randint(-7, 8, size=(4,n))
    sim.spawn(engine.execute_left,S,A)
    sim.run()
    engine.report_stats()
    # #n = 8
    #S = np.random.randint(-1, 2, size=(n,8))
    # S = np.random.randint(-1, 2, size=(8,4))
    # ##print("S",S)
    # #print("S.T",S.T)
    # #S = np.array([[1],[0],[-1],[1]])
    # #S= S.T
    # S_bits = 5
    # matrix_slice = engine.slice(S,S_bits)
    # #matrix_slice.visualize_matrix()
    # #print(matrix_slice.numpy_array)
    # fifo_list = engine.fifo(matrix_slice,S_bits)
    #A = np.random.randint(-7, 8, size=(4,n))
    # #A = np.array([[1,0,2,3],[1,2,3,0],[4,1,2,3],[2,3,4,1]])
    # #result_matrix,latency = engine._caculate(fifo_list,A.T,S_bits)
    # #result_matrix = result_matrix[:,0:8]
    # #result_matrix,latency = engine.execute_left(S,A,S_bits)
    # result_matrix,latency = engine.execute_right(S,A,S_bits)
    # #ref_accumulator = np.matmul(A,S)
    # #ref_accumulator = np.matmul(A,S)
    # #result_matrix = result_matrix[:,0:8]
    # ref_accumulator = np.matmul(S,A)
    # print(ref_accumulator)
    # print(result_matrix)
    # print(ref_accumulator==result_matrix)
    # print(latency)