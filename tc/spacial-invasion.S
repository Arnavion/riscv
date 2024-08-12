li a1, 3 # enjoy
li a2, 5 # shoot
sb a2, -8(zero)
li a3, 1 # forward
sb a3, -8(zero)
j 8 # loop
# shoot
sb a2, -8(zero)
# loop
lbu a0, -8(zero)
bnez a0, -8 # shoot
sb a1, -8(zero)
j -12 # loop
