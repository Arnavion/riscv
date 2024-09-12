li fp, -8
li a2, 37

# loop
lbu a0, 0(fp)
addi a1, a1, 1
bne a0, a2, -4 # loop

sb a1, 0(fp)
