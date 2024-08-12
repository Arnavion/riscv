lbu a0, -8(zero)

# loop
srli a1, a0, 1
xor a1, a0, a1
slli a2, a1, 1
zext.b a2, a2
xor a2, a1, a2
srli a0, a2, 2
xor a0, a0, a2
andi a1, a0, 0b11
sb a1, -8(zero)
j -36 # loop
