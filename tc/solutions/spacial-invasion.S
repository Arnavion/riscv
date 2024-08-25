li fp, -8
li a1, 3 # enjoy
li a2, 5 # shoot
sb a2, 0(fp)
li a3, 1 # forward
sb a3, 0(fp)
j 4 # loop
# shoot
sb a2, 0(fp)
# loop
lbu a0, 0(fp)
bnez a0, -4 # shoot
sb a1, 0(fp)
j -6 # loop
