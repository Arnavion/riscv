li fp, -8
li a0, 5 # shoot
sb a0, 0(fp)
li a1, 1 # forward
li a2, 3 # enjoy

# loop
sb a1, 0(fp)
lbu a1, 0(fp)
czero.nez a3, a2, a1 # a1 = (a1 == 0) ? a2 : a0
czero.eqz a1, a0, a1 #
or a1, a1, a3        #
j -14 # loop
