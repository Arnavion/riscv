li fp, -8

li a0, 0x80 # guess
li a1, 0x80 # mask

# loop
sb a0, 0(fp)

# 0 => too high, next guess should be lower
# 1 => too low, next guess should be higher
lbu a2, 0(fp)

czero.eqz a2, a1, a2 # a0 = a2 ? (a0 ^ a1) : a0
xor a0, a0, a2       #    = a0 ^ (a2 ? a1 : 0)
srli a1, a1, 1
or a0, a0, a1

j -14 # loop
