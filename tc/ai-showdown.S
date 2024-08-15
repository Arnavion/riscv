# loop
lbu a0, -8(zero)
addi a0, a0, -1
andi a0, a0, 0b11
sb a0, -8(zero)
j -12 # loop
