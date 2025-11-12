from frodokem import FrodoKEM
from nist_kat import NISTKAT

print("Running FrodoKEM-640")
kem = FrodoKEM('FrodoKEM-640-SHAKE')
rng = NISTKAT.NISTRNG()
kem.randombytes = rng.randombytes
pk, sk = kem.kem_keygen()
ct,ss = kem.kem_encaps(pk)
# kem.kem_decaps(sk,ct)


# print("Running FrodoKEM-976")
# kem = FrodoKEM('FrodoKEM-976-SHAKE')
# rng = NISTKAT.NISTRNG()
# kem.randombytes = rng.randombytes
# pk, sk = kem.kem_keygen()
# ct,ss = kem.kem_encaps(pk)
# kem.kem_decaps(sk,ct)

# print("Running FrodoKEM-1344")
# kem = FrodoKEM('FrodoKEM-1344-SHAKE')
# rng = NISTKAT.NISTRNG()
# kem.randombytes = rng.randombytes
# pk, sk = kem.kem_keygen()
# ct,ss = kem.kem_encaps(pk)
# kem.kem_decaps(sk,ct)



