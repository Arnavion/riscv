# loop
lbu a0, -1(zero)
addi a0, a0, -1
andi a0, a0, 0x03
sb a0, -1(zero)
j -16 # loop
