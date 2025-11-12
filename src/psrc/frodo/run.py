from frodokem import FrodoKEM  # 确保代码文件名为 frodokem.py

# 初始化 FrodoKEM 实例，选择变体 FrodoKEM-640-AES
frodo = FrodoKEM(variant="FrodoKEM-640-SHAKE")

# 运行密钥生成过程
public_key, secret_key = frodo.kem_keygen()

# 打印公钥和私钥
print("Public Key (pk):")
print(public_key.hex().upper())

print("\nSecret Key (sk):")
print(secret_key.hex().upper())
