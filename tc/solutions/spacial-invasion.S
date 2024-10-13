li fp, -8
li a0, 5 # shoot
sb a0, 0(fp)
li a1, 1 # forward
li a2, 3 # enjoy

# loop
sb a1, 0(fp)
lbu a1, 0(fp)
snez a1, a1        # a1 = (a1 == 0) ? 3 : 5
sh1add a1, a1, a2  #    = (a1 != 0) * 2 + 3
j -12 # loop
