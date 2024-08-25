li fp, -8
lbu a0, 0(fp) # numerator
lbu a1, 0(fp) # denominator
slli a1, a1, 7
li a4, 7
j 8 # loop2

# loop
slli a2, a2, 1
srli a1, a1, 1
addi a4, a4, -1
# loop2
blt a0, a1, 10
sub a0, a0, a1
ori a2, a2, 0b1
bgtz a4, -16 # loop

sb a2, 0(fp) # quotient
sb a0, 0(fp) # remainder
