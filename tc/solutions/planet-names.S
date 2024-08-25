li fp, -8
li a1, 32
li a2, 32
# loop
lbu a0, 0(fp)
sub a3, a0, a2
sb a3, 0(fp)
mv a2, zero
bne a0, a1, -10 # loop
mv a2, a1
j -16 # loop
