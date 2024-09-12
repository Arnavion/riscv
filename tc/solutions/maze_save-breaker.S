li fp, -8

li a1, 1 # FORWARD
sb a1, 0(fp)

li a2, 2 # RIGHT

# loop
sb a2, 0(fp)

# loop2
lbu a0, 0(fp)
sub a3, a1, a0 # EMPTY -> FORWARD, WALL -> LEFT
sb a3, 0(fp)
bnez a0, -8 # loop2
j -12 # loop
