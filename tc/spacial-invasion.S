li a1, 3 # enjoy
li a2, 5 # shoot
sb a2, -1(zero)
li a3, 1 # forward
sb a3, -1(zero)
j 6 # loop
# shoot
sb a2, -1(zero)
# loop
lb a0, -1(zero)
bnez a0, -8 # shoot
sb a1, -1(zero)
j -10 # loop
