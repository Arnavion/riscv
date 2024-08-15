li a1, 32
li a2, 32
# loop
lb a0, -1(zero)
sub a3, a0, a2
sb a3, -1(zero)
mv a2, zero
bne a0, a1, -14 # loop
mv a2, a1
j -20 # loop
