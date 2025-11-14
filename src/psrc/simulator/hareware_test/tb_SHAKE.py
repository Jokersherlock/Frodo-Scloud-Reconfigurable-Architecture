import sys
import os
# 添加父目录到路径，以便导入 core 和 hardware 模块
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core import Simulator
from hardware.SHAKE import SHAKE
import numpy as np



if __name__ == "__main__":
    sim = Simulator()
    shake = SHAKE("shake",sim,data_simulate_enable=True)
    data = bytes.fromhex('10')
    print(len(data))
    len = 1
    result = shake._shake256(data,len)
    print("result",result.hex().upper())