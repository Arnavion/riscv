li fp, -8
sb a1, 0(fp) # left
li a0, 1 # forward
sb a0, 0(fp)
sb a1, 0(fp)
sb a0, 0(fp)
sb a0, 0(fp)
sb a0, 0(fp)
sb a0, 0(fp)
sb a1, 0(fp)
sb a0, 0(fp)
li a1, 2 # right
sb a1, 0(fp)
sb a0, 0(fp)
li a2, 3 # enjoy
li a3, 4 # use
li a4, 92 # empty conveyor belt
# loop
lbu a0, 0(fp)
bne a0, a4, 8 # fruit
# idle
sb a2, 0(fp)
j -8 # loop
# fruit
lbu a5, 0(a0)
bnez a5, 6 # found_duplicate
sb a0, 0(a0)
j -10 # idle
# found_duplicate
sb a1, 0(fp)
sb a3 0(fp)
