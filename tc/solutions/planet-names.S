li a1, 32
li a2, 32
# loop
lbu a0, -8(zero)
sub a3, a0, a2
sb a3, -8(zero)
mv a2, zero
bne a0, a1, -16 # loop
mv a2, a1
j -24 # loop
