sb zero, -8(zero) # left
li a0, 1 # forward
sb a0, -8(zero)
sb zero, -8(zero)
sb a0, -8(zero)
sb a0, -8(zero)
sb a0, -8(zero)
sb a0, -8(zero)
sb zero, -8(zero)
sb a0, -8(zero)
li a1, 2 # right
sb a1, -8(zero)
sb a0, -8(zero)
li a2, 3 # enjoy
li a3, 4 # use
li a4, 92 # empty conveyor belt
# loop
lbu a0, -8(zero)
bne a0, a4, 12 # fruit
# idle
sb a2, -8(zero)
j -12 # loop
# fruit
lbu a5, 0(a0)
bnez a5, 12 # found_duplicate
sb a0, 0(a0)
j -20 # idle
# found_duplicate
sb a1, -8(zero)
sb a3 -8(zero)
