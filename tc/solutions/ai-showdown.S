li fp, -8
# loop
lbu a0, 0(fp)
addi a0, a0, -1
andi a0, a0, 0b11
sb a0, 0(fp)
j -8 # loop
