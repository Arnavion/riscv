li fp, -8
lhu a0, 0(fp)

# loop
srli a1, a0, 7
xor a0, a0, a1
slli a1, a0, 9
xor a0, a0, a1
zext.h a0, a0
srli a1, a0, 8
xor a0, a0, a1
sh a0, 0(fp)
j -22 # loop
