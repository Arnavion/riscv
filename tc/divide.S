li fp, -8
lbu a0, 0(fp) # numerator
lbu a1, 0(fp) # denominator
slli a1, a1, 7
li a4, 7
j 6 # loop2

# loop
srli a1, a1, 1
addi a4, a4, -1
# loop2
sltu a3, a0, a1       # a3 = (numerator < denominator) ? 1 : 0
czero.nez a5, a1, a3  # a5 = (numerator < denominator) ? 0 : denominator
sub a0, a0, a5
binvi a3, a3, 0       # a3 = (numerator >= denominator) ? 1 : 0
sh1add a2, a2, a3
bgtz a4, -22 # loop

sb a2, 0(fp) # quotient
sb a0, 0(fp) # remainder
