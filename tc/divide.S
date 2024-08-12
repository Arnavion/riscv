lbu a0, -8(zero) # numerator
lbu a1, -8(zero) # denominator
slli a1, a1, 7
li a4, 7
j 16 # loop2

# loop
slli a2, a2, 1
srli a1, a1, 1
addi a4, a4, -1
# loop2
blt a0, a1, 12
sub a0, a0, a1
ori a2, a2, 0b1
bgtz a4, -24 # loop

sb a2, -8(zero) # quotient
sb a0, -8(zero) # remainder
