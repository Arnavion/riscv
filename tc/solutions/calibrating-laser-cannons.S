li fp, -8
lbu a0, 0(fp)
slli a1, a0, 1
slli a0, a0, 3
sub a0, a0, a1
sb a0, 0(fp)
