li fp, -1
# loop
lbu a0, 0(fp)
addi a0, a0, -1
andi a0, a0, 0x03
sb a0, 0(fp)
j -8 # loop
